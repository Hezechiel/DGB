# Divine Gestures: Babylon — Map Authoring Guide

> Companion to `architecture.md` §3 (data layer) and §4 (battle scene
> structure). Read those first if you haven't touched the map pipeline
> before — this doc is the step-by-step checklist for adding a new one,
> not the explanation of why it's built this way. Update this file
> whenever the map pipeline itself changes, the same as architecture.md.

---

## 0. WIP — tile-built map pipeline (in progress)

**Status, Sept 2026: `GreekPlateauMap.tscn` is the working test bed and is
complete, including its navmesh. `NordPlainsMap.tscn` is mid-migration to
the same structure (see "Nord Plains migration status" below). Until this
section is resolved and folded into the main checklist, §1–§4 still
describe the old single-`Sprite2D` pattern.**

Motivation: the flat-background approach couldn't reasonably produce
the tighter, funnel-shaped, SWFA-inspired arena layout the project is
moving toward (see the map-compaction design discussion) without
either a bespoke full-map background image per layout iteration or a
border/obstacle shape hand-painted into art that then has to be redone
every time the collision shape changes. Building the map from tiles
decouples layout iteration from art production.

What's actually built on `GreekPlateauMap.tscn` today:

- No background `Sprite2D` — removed entirely.
- `Terrain/TileMapLayer` — ground tiles, using the Greek tileset
  (`data/tilesets/greek_tileset.tres` — recreated from scratch for this
  map in Sept 2026, the old one removed). **The tileset has no Navigation
  Layer** — keep it that way (see §2.10).
- `Obstacles/TileMapLayer` — a second, separate `TileMapLayer` purely
  for obstacle *visuals* (terrain-like blob dressing), same tileset.
  Deliberately painted only with non-colliding tile variants — collision
  for these blobs comes from a separate node (below), never from this
  layer's own tile physics, to avoid two disagreeing collision sources for
  the same obstacle.
- `Patches/` — collision-only nodes for the large hand-shaped obstacle
  blobs: `LargePatch` (an inherited scene of `LargePatch.tscn`) and
  `LeftPatch`/`RightPatch` (two instances of `SmallPatch.tscn`). Both
  `LargePatch.tscn` and `SmallPatch.tscn` are themselves inherited scenes of
  `scenes/arena/obstacles/ObstaclePatch.tscn` — a script-free base
  scene (`StaticBody2D`, `collision_layer = 4` / `collision_mask = 0`,
  one `CollisionPolygon2D` in `Solids` build mode with a small
  placeholder square). Never leave that polygon empty — Godot errors
  trying to decompose a zero-point shape; the placeholder square is
  there so a fresh inherited scene is always valid before you trace
  over it. Each inherited scene overrides only the
  `CollisionPolygon2D.polygon` with its own hand-traced outline. None
  of these carry a `Sprite2D` texture — the look comes entirely from
  the `Obstacles/TileMapLayer` painting underneath; the polygon is
  purely physical. `Patches` is in the `nav_obstacle` group.
- `MapBorder` — `scenes/arena/maps/MapBorder.tscn` /
  `scripts/arena/map_border.gd`, providing the map's outer physical
  boundary as a non-rectangular "funnel" shape (rounded base areas
  pinched toward a center waist — the SWFA-style layout goal). Two
  implementations currently coexist inside the same scene for
  comparison: a parametric `@tool`-generated `CollisionPolygon2D`
  (currently disabled) and a hand-traced `CollisionPolygon2D2`
  (currently active) — **pick one and delete the other before
  release**; a `StaticBody2D` with two enabled shape children unions
  both, which was never the intent. Both must use
  `build_mode = Segments`, never `Solids` — see the pitfall in
  `architecture.md` §6. `MapBorder`'s shape is independent of
  `MapData.bounds`, which still exists purely as the camera-clamp/
  deploy-bounds rectangle (§2.8 below, unchanged). `MapBorder` is
  **not** in the `nav_obstacle` group — the navmesh outline is drawn
  by hand to match it instead (§2.10).
- `NavigationRegion2D` — the map's navmesh (Sept 2026). Walkable outline
  hand-drawn over the hand-traced `MapBorder` shape; holes baked from the
  `nav_obstacle` group (`Patches`, `PlayerStructures`, `EnemyStructures`).
  Full setup in §2.10; how movers use it in `architecture.md` §5
  Navigation.

**Nord Plains migration status (Sept 2026):** `NordPlainsMap.tscn` already
has `Terrain/TileMapLayer`, an obstacle-visual `TileMapLayer` (currently
under a node named `Obstacles2`), `Patches` (`LargePatch`, `LeftPatch`,
`RightPatch`), a `MapBorder` instance and a `NavigationRegion2D`. Still
open on it:

- Its `NavigationRegion2D`'s `NavigationPolygon` is a **copy of Greek
  Plateau's**, including Greek's baked result — the holes currently in it
  are Greek's patch/structure shapes, not Nord's. And `Patches`,
  `PlayerStructures`, `EnemyStructures` on Nord **aren't in the
  `nav_obstacle` group yet**, so a rebake right now would produce no holes
  at all. Fix: add the group to those three nodes, check the outline still
  matches Nord's border, then **Bake NavigationPolygon** (§2.10). Because
  the region exists, `BattleManager.has_navigation()` is already true on
  Nord — the direct-steering fallback no longer applies there, so movers
  on Nord currently follow the wrong mesh until this is rebaked.
- Old-pattern leftovers still in the scene: `Obstacles` with
  `Rock`/`Tree`/`Wall` instances and an unused `NavigationObstacle2D`.
  Either delete them (if the patches replace them) or put `Obstacles` in
  `nav_obstacle` too so the bake carves around them — otherwise movers
  will path straight into those rocks/walls and slide.
- Protection zones and turret/base positions were retuned on Greek for
  the tighter layout; check whether Nord's still reflect the older, larger
  layout.

Other things this pipeline explicitly does NOT do yet:

- No `Transitions`/`Water`/`Boundaries`/`Decorations`/`FX` layer
  split — only `Terrain` and `Obstacles` exist. A fuller category
  breakdown was discussed but only these two are actually built.
- Tileset naming/sharing per era (Greek vs. Norse art) isn't settled —
  check which tileset Nord's layers point at before Norse art diverges.

Before this becomes the real pipeline (replacing §1–§4 below rather
than sitting alongside them): resolve the generator-vs-hand-drawn
`MapBorder` duplication, finish the Nord Plains migration above, settle
the tileset naming, and decide whether the fuller
Terrain/Transitions/Water/Boundaries/Decorations layer split is worth
building or whether Terrain+Obstacles is enough.

---

## 1. What a map actually is

A map is two files that must agree with each other:

- **`data/maps/<id>.tres`** — a `MapData` resource: identity
  (`id`, `display_name`), a `release_ready` flag, bounds/camera tuning,
  hero spawn points, and a `map_scene` reference pointing at the second
  file.
- **`scenes/arena/maps/<Name>Map.tscn`** — a plain `Node2D` scene holding
  everything visually and structurally specific to that map: ground,
  obstacles, border, navmesh, `PlayerStructures`, `EnemyStructures`.

Neither file does anything by itself. At boot, the `MapDB` autoload scans
`data/maps/*.tres` into an id-keyed dictionary — the same pattern
`CardDB` uses for cards/units/heroes/spells. At runtime, `arena.tscn`
(the generic match shell: HUD, camera, deploy ghost, move marker,
denial-zone overlay — no map content of its own) resolves
`MatchConfig.map_id` through `MapDB.get_map()`, instantiates that map's
`map_scene` into its own empty `MapRoot` node, then configures
`BattleManager`/`ArenaCamera` from the resolved `MapData`. Adding a map
that follows this checklist requires **zero script changes** — the scan
picks it up automatically, and movers pick up the map's navmesh
automatically too (no per-map navigation code).

> **Note:** the table in §2.2 below describes the old single-`Sprite2D`
> structure. Both existing maps are moving to the tile-built structure in
> §0 — check there before using either as the reference implementation
> for a new map.

---

## 2. Checklist

### 2.1 Background art
Drop the background image into `assets/world/<name>.png`. Name it after
the map, not the era or a generic term (`greek_plateau.png`,
`nord_plains.png`) — this file's name is what disambiguates maps in the
asset browser once there are several per era. (Old pattern only — the
tile-built pipeline in §0 has no background image.)

### 2.2 Create the map scene — `scenes/arena/maps/<Name>Map.tscn`
Easiest path: duplicate an existing map scene and re-skin it, rather than
building from an empty scene — it keeps you from missing a node type
(but see §2.10 about rebaking a duplicated navmesh). Root node: `Node2D`,
named after the map (`<Name>Map`). Required children (old pattern):

| Node | Type | Notes |
|---|---|---|
| `Map` | `Sprite2D` | Background texture from §2.1. Existing maps use `scale = Vector2(0.7, 0.7)` — match it unless the new art was made at a different native resolution. |
| `TileMapLayer` | `TileMapLayer` | Ground collision. Physics layer/mask **must be `4`/`4`** (bit 3 = `structures`, per `project.godot`'s `layer_names`) — this is what makes impassable ground tiles collide the same way turrets/bases do. Don't invent a different layer for this. |
| `Obstacles` | `Node2D` | Container for `Rock`/`Tree`/`Wall` instances (see §2.6). Must be in the `nav_obstacle` group if it holds colliding obstacles (§2.10). |
| `NavigationRegion2D` | `NavigationRegion2D` | The map's navmesh — required on every map; see §2.10. |
| `PlayerStructures` | `Node2D` | Container — see §2.3/§2.7. In the `nav_obstacle` group. |
| `EnemyStructures` | `Node2D` | Container — see §2.3/§2.7. In the `nav_obstacle` group. |

`NavigationObstacle2D` (present on the old maps) is **not** needed — it
was never configured and nothing reads it; the navmesh bake replaces it.

### 2.3 Place structures — `PlayerStructures` / `EnemyStructures`
Each side needs, as direct children of its container:

- 1× `PlayerBase.tscn` / `EnemyBase.tscn`
- 3× `PlayerTurret.tscn` / `EnemyTurret.tscn` — by convention named
  `...TurretTop`, `...TurretBot`, `...TurretBase` (the base-lane turret).
  Turrets on the "bot" lane need `lane = "bot"` set (an export on
  `turret.tscn`) — this is purely a visual/animation-facing lane), so
  copy that convention across.
- 2× `HealingPod.tscn` per side (`...PodTop`, `...PodBot`) — see §2.5.

Structures self-register with `BattleManager` from their own `_ready()`
(combat registries, protection zones) — nothing needs to be wired by
hand or by path. `EnemyBase` currently sets `max_hp = 200` (double the
default) on both existing maps; carry that forward unless you're
deliberately rebalancing. Moving a structure changes the navmesh holes —
**rebake** afterwards (§2.10).

### 2.4 Set starting points — hero spawns
`MapData.hero_spawn_player` / `hero_spawn_enemy` (Vector2, in the
`.tres`, §2.8) are the single source of truth — `arena.gd` positions
both heroes from these fields directly. They are **not** derived from
any node in the map scene, so there's nothing to place in the editor for
this step; just pick sensible coordinates relative to each base's
position and set them in the `.tres`. Keep them on the navmesh (the blue
area with Debug → Visible Navigation on) and not hugging an obstacle —
the AI hero retreats to its spawn point, snapped onto the navmesh.

### 2.5 Set up healing pods
Positioned by hand as plain child-node placements of `HealingPod.tscn`
inside `PlayerStructures`/`EnemyStructures` (§2.3) — one per lane per
side, near but not on top of each base. No exported fields to configure
beyond position; team and cross-team usability are resolved automatically
from the node's name at runtime (`"Player"`/`"Enemy"` substring), so keep
naming them `HealingPod<Side><Lane>` (`HealingPodPlayerTop`, etc.). Pods
are `Area2D`, so the navmesh bake ignores them even though their container
is in `nav_obstacle` — they stay walkable, as they must. Place them on the
navmesh, not inside a hole.

### 2.6 Set up obstacles / environment
Old pattern: instance `Rock.tscn` / `Tree.tscn` / `Wall.tscn` under
`Obstacles`, positioning and re-texturing (via `AtlasTexture` regions into
the tileset/obstacle sheet) each one by hand — there's no data-driven
obstacle placement, this is direct scene authoring. `Wall` instances also
set `collision_size` per instance to match their sprite footprint.
Remember the `CollisionShape2D` "Local to Scene" rule (architecture.md
§6) if you duplicate a shape resource rather than letting the instance
create its own.

Tile-built pattern (§0): `ObstaclePatch`-inherited scenes under `Patches`
for collision, a separate obstacle `TileMapLayer` for the look.

Either way, every colliding obstacle's container must be in the
`nav_obstacle` group, and adding/moving/reshaping an obstacle means a
**rebake** (§2.10). Only rock/tree/wall/patch obstacle types exist today.
If you're introducing a new obstacle behavior (mountain/abyss/bush/mud/ice
— see the open question in game_design.md §6), that's new archetype work,
not something this checklist covers yet — design it as its own step
before authoring a map that depends on it. (Walkable-but-slowing terrain
like mud would need navigation layers or costs — not just a hole.)

### 2.7 Set up barriers / protection (denial) zones
Every structure (`PlayerBase`, `PlayerTurret*`, `EnemyBase`,
`EnemyTurret*`) exports `protection_zone: Rect2` directly on its scene
instance — set it by hand, per structure, per map. There is **no shared
formula** (architecture.md §3/§6) — this is deliberately hand-tuned to
each map's specific layout. Guidelines from the two existing maps:

- Each turret's zone should cover the territory it's meant to defend —
  typically a band running from the map's outer edge in to roughly the
  turret's own position, so destroying it opens exactly that slice
  (game_design.md §3.7 — losing one turret must not open more than its
  own territory).
- Each base's zone is typically a thin strip hugging the map's outer
  edge on that team's side.
- Zones combine additively per team — `BattleManager` just tracks
  whichever ones are currently registered, so overlapping coverage
  between a turret and its base is fine and expected.
- `DenialZoneOverlay` needs no per-map configuration — it reads
  `BattleManager.get_active_protection_zones()` live, so a correctly
  hand-tuned map gets correct denial-zone visuals for free.

### 2.8 Create `data/maps/<id>.tres`
`MapData` fields to set:

| Field | Guidance |
|---|---|
| `id` | `&"map_<name>"` — must be globally unique; `MapDB` push_errors on a duplicate. |
| `display_name` | Player-facing name, shown on the PreMatchFlow finding screen. |
| `release_ready` | `true` for a finished map ready for a real player pool; `false` for WIP/test maps (see §3). Defaults to `true` — set it explicitly to `false` while a map is still in progress. |
| `map_scene` | Points at the `.tscn` from §2.2. |
| `bounds` | `Rect2` spanning the full playable area — must match what the map scene actually looks like; both `BattleManager.deploy_bounds` and the camera's pan clamp derive from this alone. |
| `camera_edge_margin` / `camera_edge_pan_speed_max` | Drag-to-deploy edge-pan tuning. Existing default (100.0 / 650.0) is untouched on both current maps — revisit only if the new map is meaningfully larger/smaller. |
| `hero_spawn_player` / `hero_spawn_enemy` | See §2.4. |

### 2.9 Known gap — camera position/zoom aren't per-map yet
`ArenaCamera`'s initial `position` and `zoom` are hardcoded on the
`ArenaCamera` node inside `arena.tscn` (the shared shell) — they are
**not** part of `MapData` and `configure_map()` does not touch them; only
`bounds_min`/`bounds_max`/`edge_margin`/`edge_pan_speed_max` are
per-map. This happens to work today because both existing maps share the
same bounds size (~920×610). A map with meaningfully different
dimensions will likely need its starting framing fixed by hand, or this
gap closed properly (a `camera_start_position`/`camera_start_zoom` on
`MapData`, most likely) — not scoped yet, flag it if you hit it.

### 2.10 Navigation mesh — `NavigationRegion2D`
Every map needs one. Heroes and units find paths on it automatically
(`architecture.md` §5 Navigation); a map without one falls back to
straight-line steering, which gets movers stuck on concave obstacles.

1. **Tag the obstacles.** In the Node dock → Groups, add the group
   `nav_obstacle` to every container holding colliding obstacles or
   structures: `Patches`, `PlayerStructures`, `EnemyStructures` (and
   `Obstacles` if it holds `Rock`/`Tree`/`Wall` instances). Tag the
   container, not each child — the bake reads children too. **Never** tag
   `MapBorder`.
2. **Add the region.** Add a `NavigationRegion2D` as a direct child of the
   map root, create a new `NavigationPolygon` on it, and draw its outline
   by hand over the `MapBorder` shape (the hand-traced one).
3. **Set the NavigationPolygon properties** (Inspector):
   - Geometry → Parsed Geometry Type: `Static Colliders`
   - Geometry → Parsed Collision Mask: only layer 3 (value `4`) — the
     layer obstacles, structures and the border use
   - Geometry → Source Geometry Mode: `Groups With Children`
   - Geometry → Source Geometry Group Name: `nav_obstacle`
   - Agents → Radius: leave at the default `10` unless hero/unit
     collision sizes change (hero body circle 7 px; unit 16×16 box)
4. **Bake.** Select the `NavigationRegion2D` → **Bake NavigationPolygon**
   in the toolbar. Expect a blue mesh slightly inset from your outline
   (by the agent radius), with a hole around every patch, turret and base.
   Healing pods stay inside the walkable area (they're `Area2D`, not
   parsed). Your drawn outline is kept; only the blue fill is regenerated.
5. **Rebake whenever** an obstacle, structure or the border moves or
   changes shape. The bake is stored in the scene; nothing rebakes at
   runtime.

Pitfalls (details in `architecture.md` §6):
- A **duplicated** map scene or `NavigationRegion2D` carries the source
  map's baked mesh — always set the groups on the new map and rebake.
- The default Source Geometry Mode (`Root Node Children`) only parses the
  region's own children → a mesh with **no holes**.
- A **TileSet with a Navigation Layer** adds a second, overlapping navmesh
  that ignores the holes. Tilesets for maps must have no Navigation Layer.
- Not yet enforced: unit cards can still be deployed inside a navmesh hole
  (deploy validation doesn't check the navmesh yet).

---

## 3. `release_ready` and the current (temporary) random picker

`MapDB.get_random_map_id()` is explicitly a **testing-only** picker
(uniform random across every scanned map) — it does **not** filter by
`release_ready`, on purpose, so a WIP map stays visible while you're
testing it. `PreMatchFlow` calls it once per match and stores the result
in `MatchConfig.map_id`. There is no real mode/rotation/vote selection
logic yet, and no filtering by `release_ready` anywhere — both are open
(see game_design.md §6). Don't assume `release_ready = false` hides a
map from anything today; it currently hides it from nothing.

---

## 4. Verification checklist for a newly authored map

1. `MapDB` boots without a `push_error` (duplicate id, missing resource,
   bad path) — check the console on first run after adding the map.
2. Restart the match a few times from the main menu; confirm the new
   map's `display_name` shows up on the PreMatchFlow finding screen
   among the rotation.
3. When it's picked: ground renders at the right scale, obstacles collide
   correctly, both heroes spawn at sensible positions, all structures and
   healing pods appear where placed.
4. **Navigation:** turn on Debug → Visible Navigation. The blue mesh
   matches the border, has a hole around every obstacle/turret/base and
   none anywhere else (no leftover holes from another map), and covers
   both hero spawns and all four healing pods. Tap behind the largest
   obstacle — the hero paths around it; tap inside an obstacle — the move
   marker snaps to its edge. Deploy a squad behind an obstacle — it paths
   around to the nearest enemy structure. The enemy AI hero marches and
   retreats without getting stuck.
5. Drag a unit card near each side's structures and confirm the
   denial-zone overlay matches the protection zones you set in §2.7 —
   specifically, destroy a turret through play and confirm only that
   turret's own territory opens up, not the rest of that side's half.
6. Play a full match to completion (base destroyed or timer expiry) on
   the new map without errors.
