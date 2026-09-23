# Claude Code prompt — Navigation step 3: unit (minion) pathfinding

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

Steps 1 and 2 are done and tested. `player.gd` and `hero_dummy.gd` follow the navmesh through a `NavAgent` (`NavigationAgent2D`) child and a local `_nav_direction_to(goal)` helper. `BattleManager.has_navigation()` makes both fall back to direct steering on maps without a navmesh (Nord Plains today).

This step gives **units** (`unit.gd`, used by both `melee_unit.tscn` and `ranged_unit.tscn`) the same pathfinding. Unit movement already goes through one function, `_steer_towards(target_pos, delta)`, called from:
- `_process_marching()`: toward `structure_target`
- `_process_chasing()`: toward `combat_target`, a moving unit or hero

`_process_engaging()` doesn't move and isn't touched.

Unlike the heroes, units blend a **seek** direction with a **separation** vector. Only the seek direction comes from the navmesh. Separation stays exactly as it is, added on top.

## Files to read first

- `scripts/arena/unit.gd`
- `scenes/arena/units/melee_unit.tscn`
- `scenes/arena/units/ranged_unit.tscn`
- `scripts/arena/hero_dummy.gd`: reference only; copy its `_nav_direction_to()`, `_nav_goal`, `NAV_REPATH_DIST_SQ` pattern
- `scenes/arena/hero_dummy.tscn`: reference only; copy its `NavAgent` node properties

## Changes

### 1. Both unit scenes: add a `NavigationAgent2D`

Add a child `NavAgent` (type `NavigationAgent2D`) to the root node of **both** `melee_unit.tscn` and `ranged_unit.tscn`, with the same properties as `hero_dummy.tscn`'s `NavAgent`:
- `path_desired_distance = 4.0`
- `target_desired_distance = 8.0`
- avoidance off, everything else default

Both scenes attach `unit.gd` and `@onready` resolves `$NavAgent`, so a missing node in either scene would crash that archetype. Both scenes must get it.

### 2. `scripts/arena/unit.gd`

**a) Fields.** Add these near the other movement fields (`sep_timer`, `cached_sep`), with the same Slovak comment as in `hero_dummy.gd`:
- `@onready var nav_agent: NavigationAgent2D = $NavAgent`
- `var _nav_goal: Vector2 = Vector2.INF`
- `const NAV_REPATH_DIST_SQ := 16.0 * 16.0`

**b) Helper.** Add `_nav_direction_to(goal: Vector2) -> Vector2`, copied **verbatim** from `hero_dummy.gd`, including the comment. This is deliberate duplication per `architecture.md` §6 (three separate movement pipelines). Do not extract a shared helper.

**c) `_steer_towards()`.** Replace
```gdscript
var to_target: Vector2 = target_pos - global_position
...
var seek_dir: Vector2 = to_target.normalized()
```
with
```gdscript
var seek_dir: Vector2 = _nav_direction_to(target_pos)
```
Remove the now-unused `to_target` local; otherwise GDScript warns about an unused variable. Keep everything else in the function exactly as it is:
- the root early-return
- the separation timer and `compute_separation()` cache
- `steer = seek * seek_strength + cached_sep * separation_strength`
- the `steer.length() < 0.001` fallback to `seek_dir`
- `last_direction`, animation, `velocity`, `move_and_slide()`

Add one short Slovak comment: the navmesh gives only the seek direction, and separation is still added on top.

No other changes. Units have no respawn and no revive (`die()` ends in `queue_free()`), so there's no `_nav_goal` reset to add. The goal-change threshold already repaths when a unit switches between MARCHING and CHASING, or when `structure_target` changes.

## DO NOT TOUCH

- `player.gd`, `hero_dummy.gd`, their scenes, `BattleManager.gd`, `arena.gd`: steps 1–2 are done and tested.
- The unit state machine (`MARCHING`/`CHASING`/`ENGAGING` priority), `_update_structure_target()`, AggroRange and AttackRange handlers, `_reacquire_*`, target validation.
- `compute_separation()` and every `separation_*` / `seek_strength` / `max_neighbors` export. Only the seek direction changes; tuning comes later if needed.
- `_process_engaging()`, windup (`windup_left`, `_start_attack_windup`, `_resolve_attack_hit`), status effects, `die()`, spawn animation, the animation functions.
- Unit scene collision layers and masks, shapes, and `AttackRange`/`AggroRange` radii.
- `BattleManager.spawn_unit()` / `_formation_offset()`, and `is_deploy_position_valid()`. Deploying onto the navmesh is the next step.
- Any map scene or the NavigationPolygon resource.

## Explicitly OUT of scope

- RVO avoidance (`avoidance_enabled`) as a replacement for separation
- Retuning separation for chokepoints
- Deploy validation / snapping spawn positions onto the navmesh
- Fixing `ranged_unit.tscn`'s root node being named `MeleeUnit`. Noted, not this step.

## VERIFY

Static checks:
- `grep -n "NavAgent" scenes/arena/units/melee_unit.tscn scenes/arena/units/ranged_unit.tscn` → exactly one node in each, same properties as `hero_dummy.tscn`'s.
- `grep -n "_nav_direction_to" scripts/arena/unit.gd` → the definition plus exactly 1 call site (`_steer_towards`).
- `grep -n "to_target" scripts/arena/unit.gd` → no results.
- `grep -n "velocity_computed\|set_velocity\|avoidance" scripts/arena/unit.gd` → no results.
- `git diff --stat` shows only `unit.gd`, `melee_unit.tscn` and `ranged_unit.tscn`.
- No new warnings in the editor's script panel for `unit.gd`.

Runtime tests on **Greek Plateau** (turn on Debug → Visible Navigation):
1. Deploy a melee squad behind `LargePatch` relative to the nearest enemy turret → the squad paths around the patch and reaches the turret. It doesn't stack against the patch.
2. Same with a ranged squad → it paths around, stops at its attack range, and fires.
3. Enemy AI card plays: enemy squads also path around obstacles toward player structures.
4. A squad keeps its spacing while walking (separation still works) and still funnels through a narrow gap between a patch and the border without getting permanently stuck.
5. Squad aggro on an enemy unit on the far side of an obstacle → it chases around the obstacle (CHASING), then engages.
6. A chased target keeps moving → the chaser follows without stutter (no repath every frame).
7. Destroy a turret → units retarget the next structure and path to it.
8. Storm slow, Stun and Net root on a walking squad → the effects behave as before, and units resume their path afterwards.
9. Performance: several squads from both teams on the field at once. No visible frame drops compared to before on the test device.

Runtime test on **Nord Plains**:
10. Units behave exactly as before this change (direct seek + separation), with no errors.

Stop after this step and report: the diff summary, anything in the plan you changed, and any test you couldn't run.
