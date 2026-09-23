# Claude Code prompt — Camera: edge-aware bounds clamp + per-map camera zoom/start

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

The maps were compacted: both map borders and navmesh outlines now span about x −390…390, y −171…171. The camera still shows far past the map edges, for two reasons.

1. **The clamp limits the camera's centre, not what's on screen.** `arena_camera.gd::_clamp_to_bounds()` clamps `position` (the screen centre) into `bounds_min`/`bounds_max`. The visible area extends half a screen beyond that on every side. At zoom 3 on the 1170×540 base viewport, that's ±195 × ±90 world px. `recenter_on_player()` has its own copy of the same centre-only clamp.
2. **Zoom and start position aren't per-map.** They're hardcoded on the `ArenaCamera` node in `arena.tscn` (`position = (-250, 0)`, `zoom = (3, 3)`). `configure_map()` only sets bounds and edge-pan tuning. This is the known gap in `map_authoring_guide.md` §2.9 / `architecture.md` §6.

This step fixes both:
- `MapData.bounds` means "the rectangle the **screen** may show", and becomes the map's outline rectangle.
- `MapData` gains a per-map zoom.
- The camera starts centred on the player's spawn, clamped.

## Files to read first

- `scripts/arena/arena_camera.gd`
- `scripts/arena/map_data.gd`
- `scripts/arena/arena.gd` (`_ready()`, the order of `configure_map()` vs. hero spawn)
- `scenes/arena/arena.tscn` (the `ArenaCamera` node)
- `data/maps/greek_plateau.tres`, `data/maps/nord_plains.tres`
- `scripts/BattleManager.gd` (`configure_map()`, `deploy_bounds`): read only
- `scripts/arena/ui/minimap.gd`: read only; it also reads `MapData.bounds`
- `project.godot` `[display]`: read only; stretch mode is `canvas_items` / `expand`

## Changes

### 1. `scripts/arena/arena_camera.gd`: edge-aware clamp

Add one helper and route both clamp sites through it:

```gdscript
# Clamp pre STRED kamery tak, aby OKRAJE obrazovky ostali v bounds_min/max.
# Viditelna polovica sveta = velkost viewportu / zoom / 2 — pocita sa pri
# kazdom volani (ziadny cache), takze sedi pre kazdy pomer stran zariadenia
# (stretch aspect = expand) aj po zmene zoomu. Ak je mapa v niektorej osi
# mensia nez obrazovka, kamera sa v tej osi centruje na stred bounds.
func _clamp_point(p: Vector2) -> Vector2:
	var half_view := get_viewport_rect().size / zoom / 2.0
	var lo := bounds_min + half_view
	var hi := bounds_max - half_view
	var out := p
	out.x = (bounds_min.x + bounds_max.x) * 0.5 if lo.x > hi.x else clampf(p.x, lo.x, hi.x)
	out.y = (bounds_min.y + bounds_max.y) * 0.5 if lo.y > hi.y else clampf(p.y, lo.y, hi.y)
	return out
```

- `_clamp_to_bounds()` becomes `position = _clamp_point(position)`.
- In `recenter_on_player()`, replace the two `clampf` lines on `target_pos` with `target_pos = _clamp_point(target_pos)`.
- Every other existing `_clamp_to_bounds()` call stays where it is (lock follow, drag pan, edge pan, `_apply_mode`).
- Update the comment above `bounds_min`/`bounds_max`: the values come from `MapData.bounds` at runtime, and they mean what the screen may show, not where the centre may go.

If the plan finds that `get_viewport_rect().size` isn't the right visible-size source under `canvas_items`/`expand`, say so and propose the correct one. Don't guess silently.

### 2. `scripts/arena/map_data.gd`: per-map zoom

Add, next to the other camera fields:

```gdscript
# Zoom kamery pre tuto mapu (uniformny, Camera2D.zoom = Vector2(z, z)).
# Vacsie = priblizenejsie. Predtym napevno na ArenaCamera v arena.tscn.
@export var camera_zoom: float = 3.0
```

No separate start-position field: the camera starts on `hero_spawn_player`, which `MapData` already has, clamped by the new clamp. Update the comment on `bounds`: it's the map's outline rectangle, shared by the camera (what the screen may show), `deploy_bounds` and the minimap.

### 3. `arena_camera.gd::configure_map()`: apply zoom and start position

After the existing bounds and edge-pan assignments:

```gdscript
	zoom = Vector2(map_data.camera_zoom, map_data.camera_zoom)
	# start na spawne hraca — zoom MUSI byt nastaveny pred clampom (clamp z neho pocita)
	position = map_data.hero_spawn_player
	_clamp_to_bounds()
```

Check in the plan that nothing later in `arena.gd::_ready()` or `_deferred_init()` / `_apply_mode()` overwrites this for the unlocked-camera case. The lock-camera case snapping onto the hero afterwards is fine and expected.

### 4. `scenes/arena/arena.tscn`: remove the misleading `ArenaCamera` overrides

On the `ArenaCamera` node, delete the property lines `limit_left`, `limit_top`, `limit_right`, `limit_bottom` (forced wide open in `_ready()` anyway), `bounds_min`, `bounds_max` and `edge_pan_speed_max` (all overwritten by `configure_map()`). Leave `position` and `zoom` as editor-preview values only. No other changes to `arena.tscn`.

### 5. Map data: set the new bounds

In both `data/maps/greek_plateau.tres` and `data/maps/nord_plains.tres`:
- `bounds = Rect2(-390, -171, 780, 342)`: the border / navmesh outline extents of both maps today
- `camera_zoom = 3.0`: explicit, same as today

Leave the other fields as they are. I'll tune these values myself afterwards.

## DO NOT TOUCH

- The pan/drag logic, soft-follow and return ramp, the edge-pan speed math, the lock-mode logic, `_screen_to_world()`, and the native-limit override in `_ready()`.
- `BattleManager.gd`: `deploy_bounds` keeps reading `MapData.bounds` unchanged. It gets smaller as a consequence of step 5; that's intended.
- `minimap.gd`: it adapts to the new bounds aspect by itself.
- `arena.gd`: call order stays the same. Only report in the plan if a change is needed.
- Map scenes, the MapBorder, NavigationPolygons, heroes, units, `card_hand.gd`.

## Explicitly OUT of scope

- Pinch-to-zoom or any runtime zoom control
- A separate `camera_start_position` field on `MapData`, if the spawn-derived start turns out to be enough
- Camera shake or smoothing changes
- Automatically deriving `bounds` from `MapBorder`: it stays a hand-set rectangle in the `.tres`

## VERIFY

Static checks:
- `grep -n "clampf" scripts/arena/arena_camera.gd` → only inside `_clamp_point()`. Not in `recenter_on_player()` and not in `_clamp_to_bounds()`.
- `grep -n "camera_zoom" scripts/` → defined in `map_data.gd`, used once in `arena_camera.gd::configure_map()`.
- `grep -n "limit_\|bounds_min\|bounds_max\|edge_pan_speed_max" scenes/arena/arena.tscn` → no results.
- `git diff --stat` shows only `arena_camera.gd`, `map_data.gd`, `arena.tscn` and the two map `.tres` files.

Runtime tests (both maps, both camera lock modes from Settings):
1. **Unlocked:** drag the camera to each of the four sides and corners → the screen edge stops at the map edge; no empty space past the border. It doesn't snap or jitter when you release.
2. **Locked:** walk the hero into each corner of the map → the camera follows but stops at the edge, and the hero moves off-centre toward the corner. That's correct.
3. **Recenter button** with the hero near an edge → the tween lands on the clamped position with no jump at the end.
4. **Drag-to-deploy edge-pan** near every screen edge → it pans up to the map edge and stops.
5. **Match start**, unlocked mode → the camera starts on the player's spawn area (clamped), not at the old hardcoded `(-250, 0)` unless that's where the spawn is.
6. Change `camera_zoom` in `greek_plateau.tres` to 2.0, then 4.0 → the zoom changes on that map only, and the edge clamp stays correct at both. Set a zoom where the map is smaller than the screen on one axis (e.g. 1.5) → the camera centres on that axis and doesn't jitter. Restore 3.0.
7. If you can, run a different window aspect (resize the game window, or the Android test device) → the edges still stop at the map border.
8. **Deploy:** unit and spell drops outside the new `bounds` are red. Inside the map, nothing changes.
9. The minimap still maps positions correctly with the new bounds.

Stop after this step and report: the diff summary, anything in the plan you changed, and any test you couldn't run.
