# Claude Code prompt — Navigation step 2: AI hero (hero_dummy) pathfinding

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

Step 1 is done and tested. `player.gd` follows the navmesh through a `NavAgent` (`NavigationAgent2D`) child and a `_nav_direction_to(goal)` helper. `BattleManager.has_navigation()` / `snap_to_navigation()` exist and fall back to direct steering on maps without a navmesh (Nord Plains today).

This step gives the **AI hero** (`hero_dummy.gd`) the same pathfinding. Its movement already goes through one function, `_steer_towards(target_pos)`, called from three places in `_physics_process`:
- heal pod (LOW_HP)
- retreat to spawn (LOW_HP, no ready pod)
- enemy structure (NORMAL)

So the change is small: the direction inside `_steer_towards()` comes from the navmesh instead of a straight line. The AI's decision logic stays exactly as it is.

## Files to read first

- `scripts/arena/hero_dummy.gd`
- `scenes/arena/hero_dummy.tscn`
- `scripts/arena/player.gd`: reference only; copy its `_nav_direction_to()` pattern
- `scenes/arena/player.tscn`: reference only; copy its `NavAgent` node properties
- `scripts/BattleManager.gd` (`has_navigation`, `snap_to_navigation`, `hero_spawn_positions`)

## Changes

### 1. `scenes/arena/hero_dummy.tscn`: add a `NavigationAgent2D`

Add a child `NavAgent` (type `NavigationAgent2D`) to the root `HeroDummy`, with exactly the same properties as `player.tscn`'s `NavAgent`:
- `path_desired_distance = 4.0`
- `target_desired_distance = 8.0`
- avoidance off, everything else default

### 2. `scripts/arena/hero_dummy.gd`

**a) Fields.** Near the other `@onready` vars, add `@onready var nav_agent: NavigationAgent2D = $NavAgent`. Also add `var _nav_goal: Vector2 = Vector2.INF` and `const NAV_REPATH_DIST_SQ := 16.0 * 16.0`, with the same comment as in `player.gd`.

**b) Helper.** Add `_nav_direction_to(goal: Vector2) -> Vector2`, copied **verbatim** from `player.gd`, including the Slovak comment. This duplication is deliberate, not a refactor candidate: `architecture.md` §6 keeps the three movement pipelines separate, and this is a four-line helper.

**c) `_steer_towards()`.** Replace
```gdscript
var dir := (target_pos - global_position).normalized()
```
with
```gdscript
var dir := _nav_direction_to(target_pos)
```
Leave the rest of the function as it is: the root early-return, `last_direction`, `update_animation(dir)`, `velocity = dir * eff_speed`, `move_and_slide()`.

**d) Snap the retreat point.** In the LOW_HP retreat branch of `_physics_process`, the spawn point is used both as the steering goal and in an 8 px arrival check. If the spawn point is within the navmesh's agent-radius margin of an obstacle, the path ends a few pixels short and the arrival check never passes, so the hero walks into the wall forever. Snap it once when it's read:
```gdscript
var retreat: Vector2 = BattleManager.snap_to_navigation(
		BattleManager.hero_spawn_positions.get(team, global_position))
```
Add one Slovak comment explaining why. `snap_to_navigation()` returns the point unchanged when there's no navmesh, so Nord Plains behaves as before.

**e) Reset the stale path.** Set `_nav_goal = Vector2.INF` in `die()` and in `revive()`. In `revive()`, put it next to the existing `structure_target = null` / `heal_target = null` cache clears.

No other changes. The goal-change threshold in the helper already makes the agent repath when the AI switches target (structure → pod → spawn), so the HP-state flip needs no extra code.

## DO NOT TOUCH

- `player.gd`, `player.tscn`, `BattleManager.gd`, `arena.gd`: step 1 is done and tested.
- `unit.gd` and the unit scenes: next step.
- AI decision logic in `hero_dummy.gd`: `_update_structure_target()`, `_update_heal_target()`, the HeroAI state branching, `is_marching_or_retreating`, the fire / self-defense logic, `TARGET_CHECK_INTERVAL`, `SELF_DEFENSE_RANGE_RATIO`.
- Attack windup / cancel (`_perform_attack`, `_cancel_attack_windup`, the `take_damage()` HP-flip cancel), status effects, healing handlers, animation functions, `_on_hurtbox_input_event`.
- `HeroAI.gd`: it stays scene-blind. Navigation belongs in the hero script, not in the autoload.
- Any map scene or the NavigationPolygon resource.

## Explicitly OUT of scope

- RVO avoidance / `NavigationObstacle2D`
- Smarter AI (lane choice, kiting, flanking): only the pathing changes, not the decisions
- Snapping structure or pod targets. A structure sits inside a navmesh hole, so its path ends at the edge; the helper's `is_navigation_finished()` direct-steering fallback plus the `AttackRange` overlap check cover the last few pixels. That's the same case `player.gd` already handles for chasing turrets.
- Extracting a shared navigation helper or component

## VERIFY

Static checks:
- `grep -n "NavAgent" scenes/arena/hero_dummy.tscn` → one node, same properties as `player.tscn`'s.
- `grep -n "_nav_direction_to" scripts/arena/hero_dummy.gd` → the definition plus exactly 1 call site (`_steer_towards`).
- `grep -n "normalized()" scripts/arena/hero_dummy.gd`: the only direct `(target_pos - global_position).normalized()` left is inside `_nav_direction_to()`'s fallbacks, not in `_steer_towards()`. (`_try_fire()`'s `last_direction` line is aiming, not movement; it stays.)
- `grep -n "snap_to_navigation" scripts/arena/hero_dummy.gd` → 1 hit, in the retreat branch.
- `grep -n "velocity_computed\|set_velocity\|avoidance" scripts/arena/hero_dummy.gd` → no results.
- `git diff --stat` shows only `hero_dummy.gd` and `hero_dummy.tscn`.

Runtime tests on **Greek Plateau** (turn on Debug → Visible Navigation):
1. At match start, the enemy hero marches to the nearest player structure and paths around `LargePatch` and the side patches instead of sliding along them.
2. It stops in range of the turret and attacks, same as before.
3. Damage it below 20% HP (key H hurts the *player*, so use units, spells or your own attacks) → it breaks off, paths to a ready healing pod around obstacles, and the heal triggers when it arrives.
4. With all pods on cooldown at LOW_HP → it paths back to its spawn and stands idle there. No walking-in-place against a wall.
5. After it heals above 50% → it re-targets a structure and paths there. No stutter from the old path.
6. Stun or root it mid-path → it stops, then continues when the effect ends.
7. Kill it, wait for the respawn → the first march after respawn paths normally, with no leftover path.
8. Its attack windup still cancels on the LOW_HP flip, same as before.

Runtime test on **Nord Plains**:
9. The AI hero behaves exactly as before this change (direct steering), with no errors.

Stop after this step and report: the diff summary, anything in the plan you changed, and any test you couldn't run.
