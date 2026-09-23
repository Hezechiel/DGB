# Claude Code prompt — Navigation step 1: player hero pathfinding (NavigationAgent2D)

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

`GreekPlateauMap.tscn` now has a baked `NavigationRegion2D` (NavigationPolygon: walkable outline = map border, holes carved from the `nav_obstacle` group = `Patches`, `PlayerStructures`, `EnemyStructures`). Nothing uses it yet. The player hero today steers in a straight line toward `InputR.move_target` (or toward `primary_target` when chasing) and only slides along colliders, so it gets stuck on the large patch and on concave parts of the border.

This step makes **only the player hero** (`player.gd`) follow navmesh paths. Enemy hero, units and deploy validation come in later, separate steps.

`NordPlainsMap.tscn` has **no** `NavigationRegion2D` yet. On that map the player must behave exactly as it does today (direct steering). This fallback is required, not optional.

## Files to read first

- `scripts/arena/player.gd`
- `scenes/arena/player.tscn`
- `scripts/arena/arena.gd` (`_unhandled_input` tap-to-move)
- `scripts/BattleManager.gd` (`arena_root`, `configure_map`)
- `scripts/InputRouter.gd`
- `scenes/arena/maps/GreekPlateauMap.tscn` (only to confirm the `NavigationRegion2D` exists — do not modify it)

## Changes

### 1. `scripts/BattleManager.gd`: two navigation helpers

Add them near `configure_map()`. Both are public because they are called from outside the autoload.

```gdscript
# Ma aktualna mapa navmesh? False na mapach bez NavigationRegion2D (NordPlains
# zatial) a aj prvy physics frame po nacitani mapy, kym NavigationServer
# nesynchronizoval mapu (iteration_id == 0). Volajuci vtedy padaju spat na
# priame riadenie (stare spravanie).
func has_navigation() -> bool:
	if arena_root == null:
		return false
	var nav_map: RID = arena_root.get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(nav_map) == 0:
		return false
	return not NavigationServer2D.map_get_regions(nav_map).is_empty()

# Prisunie bod na najblizsie miesto na navmeshi (tap do prekazky / za hranicu
# mapy). Bez navmeshu vrati bod nezmeneny.
func snap_to_navigation(pos: Vector2) -> Vector2:
	if not has_navigation():
		return pos
	return NavigationServer2D.map_get_closest_point(arena_root.get_world_2d().navigation_map, pos)
```

No new per-match state, so `reset_match_state()` is untouched.

### 2. `scripts/arena/arena.gd`: snap the tap target

In `_unhandled_input`, right after `world_pos` is computed, snap it with `world_pos = BattleManager.snap_to_navigation(world_pos)` before `InputR.set_move_target(world_pos)` and `move_marker.show_at(world_pos)`. The marker must show the snapped point. Add one short Slovak comment. No other changes in arena.gd.

### 3. `scenes/arena/player.tscn`: add a `NavigationAgent2D`

Add a child `NavAgent` (type `NavigationAgent2D`) to the root `Player`:

- `path_desired_distance = 4.0`
- `target_desired_distance = 8.0` (matches the existing 8.0 stop radius in `get_move_input()`)
- `avoidance_enabled = false` (leave RVO off; explicitly out of scope)
- all other properties at their defaults (debug off)

### 4. `scripts/arena/player.gd`: follow the path

- Add `@onready var nav_agent: NavigationAgent2D = $NavAgent`.
- Add `var _nav_goal: Vector2 = Vector2.INF`: the last goal sent to the agent. Setting `target_position` every frame would repath every frame, so only resend when the goal actually moved.
- Add `const NAV_REPATH_DIST_SQ := 16.0 * 16.0`: a goal that moved less than 16 px keeps the current path. This matters for chasing a moving target.
- Add one helper that every movement source uses:

```gdscript
# Smer k cielu cez navmesh. Bez navmeshu (NordPlains / prvy frame) = priamy
# smer, identicky so starym spravanim. Cesta sa prepocita len ked sa ciel
# posunie o viac ako NAV_REPATH_DIST (chase pohybliveho ciela), nie kazdy frame.
func _nav_direction_to(goal: Vector2) -> Vector2:
	if not BattleManager.has_navigation():
		return (goal - global_position).normalized()
	if _nav_goal == Vector2.INF or _nav_goal.distance_squared_to(goal) > NAV_REPATH_DIST_SQ:
		_nav_goal = goal
		nav_agent.target_position = goal
	if nav_agent.is_navigation_finished():
		return (goal - global_position).normalized()
	var next := nav_agent.get_next_path_position()
	return (next - global_position).normalized()
```

Why `is_navigation_finished()` falls back to the direct direction: a chase goal (turret/base) sits inside a navmesh hole, so the path ends at the hole's edge. The last few pixels are covered by direct steering plus the existing attack-range check, same as today.

- **`get_move_input()`**: replace `return to_target.normalized()` with `return _nav_direction_to(InputR.move_target)`. Keep the existing 8.0 px arrival check and the `InputR.clear_move_target()` exactly as they are. When the target is cleared there, also reset `_nav_goal = Vector2.INF`.
- **Chase branch in `_physics_process`**: replace `move_dir = (primary_target.global_position - global_position).normalized()` with `move_dir = _nav_direction_to(primary_target.global_position)`.
- Reset `_nav_goal = Vector2.INF` in `on_new_move_command()`, `die()` and `revive()`, so a stale path is never reused.

Everything downstream of `move_dir` stays exactly as it is: normalization, `last_direction`, animations, root/slow, `velocity.move_toward(...)`, `move_and_slide()`. The agent only decides direction, never velocity. Do not use `NavigationAgent2D.velocity`, `velocity_computed` or `set_velocity()`.

Keep the `move_dir == Vector2.ZERO` semantics that the auto-target check relies on. `get_move_input()` must still return `Vector2.ZERO` when there is no tap target.

## DO NOT TOUCH

- `hero_dummy.gd`, `unit.gd`, their scenes, `HeroAI.gd`, `enemy_card_ai.gd`: later steps.
- `is_deploy_position_valid()` / `is_card_target_valid()`: deploy-on-navmesh is a later step.
- Any map scene (`GreekPlateauMap.tscn`, `NordPlainsMap.tscn`, `MapBorder.tscn`) and the NavigationPolygon resource.
- Attack windup / cancel logic (`_perform_attack`, `_cancel_attack_windup`, `set_primary_target`), status effects, healing handlers, animation functions.
- `InputRouter.gd`.
- `reset_match_state()` in any autoload.

## Explicitly OUT of scope

- RVO avoidance / `NavigationObstacle2D`
- Path smoothing beyond Godot's default corridor funnel
- A debug path line drawn in-game (Godot's Debug → Visible Navigation is enough)
- Any refactor into a shared movement/navigation component. Per `architecture.md` §6, the three movement pipelines stay separate on purpose.

## VERIFY

Static checks:
- `grep -n "NavAgent" scenes/arena/player.tscn` → one node, `avoidance_enabled` not true.
- `grep -n "_nav_direction_to" scripts/arena/player.gd` → the definition plus exactly 2 call sites (`get_move_input`, chase branch).
- `grep -n "velocity_computed\|set_velocity\|avoidance" scripts/arena/player.gd` → no results.
- `grep -n "snap_to_navigation\|has_navigation" scripts/` → defined in `BattleManager.gd`, used in `arena.gd` and `player.gd` only.
- The game starts with no new errors or warnings in the Output panel.

Runtime tests on **Greek Plateau** (turn on Debug → Visible Navigation):
1. Tap on the far side of `LargePatch` → the hero walks around it and doesn't slide along it.
2. Tap *inside* a patch → the move marker appears at the patch edge and the hero walks there and stops.
3. Tap outside the map border → the marker snaps inside the border, and the hero doesn't grind against the wall.
4. Tap an enemy turret on the far side of an obstacle → the hero paths around it, stops when in range, and attacks.
5. Chase the enemy hero while it moves → the hero follows smoothly without stuttering (no repath every frame).
6. Tap to move, then tap a new spot mid-walk → it changes course immediately.
7. Get stunned or rooted mid-path → the hero stops, then continues the same path when the effect ends.
8. Die and respawn → the first tap after respawn paths normally, with no leftover path from before death.
9. Start an attack, then tap to move before the damage point → the swing cancels exactly as before.

Runtime test on **Nord Plains** (restart until it's picked):
10. Tap-to-move and chase behave exactly as before this change (direct steering), with no errors.

Stop after this step and report: the diff summary, anything in the plan you changed, and any test you couldn't run.
