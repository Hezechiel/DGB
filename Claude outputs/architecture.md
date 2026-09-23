# Divine Gestures: Babylon — Architecture
 
> Technical companion to `docs/game_design.md`. Session rules and environment setup
> live in `CLAUDE.md`. Update this file when an architectural decision is made.
 
---
 
## 1. Guiding principles
 
- **Behavior in scenes, data in resources.** Archetype scenes (melee unit, hero)
  carry scripts, collision, and state machines; individual units/heroes/cards are
  Inspector-edited `.tres` files (`CardData`, `UnitData`, `HeroData`).
  `SpriteFrames` is a Resource too and is swapped onto `AnimatedSprite2D` at
  runtime — animation **names are a contract** shared by all archetypes.
- **Resources are shared instances.** Read stats from `.tres` freely; never write
  runtime state (HP etc.) back into a resource.
- **Network-ready by ID.** Nothing gameplay-relevant is ever transmitted as a
  resource or node — only `StringName` IDs + position + team. Both clients resolve
  IDs from an identical baked database. Control mode (local/AI/remote) is a local
  spawn-time decision, not data.
- **Single entry points.** Units and heroes are instantiated in exactly one place
  each (`BattleManager.spawn_unit`, `BattleManager.spawn_hero`). Local input, the
  future AI controller, and future network handlers are all just callers.
- **Per-match state is explicitly reset.** `BattleManager.reset_match_state()` is
  called from `arena._enter_tree()` — before children `_ready()` runs, because
  turrets/bases self-register in their own `_ready()`.
---
 
## 2. Autoloads
 
| Autoload | Role |
|---|---|
| `BattleManager` | Match state owner: team registries, structures, spawn entry points, hero respawn, match timer, `match_ended`. Also the navigation query helpers `has_navigation()` / `snap_to_navigation()` (§5 Navigation) — stateless wrappers over `NavigationServer2D`, no per-match state of their own. |
| `CardDB` | Startup scan of `data/cards/`, `data/units/`, `data/heroes/`, `data/spells/` into id-keyed dictionaries. Handles `.tres.remap` suffixes in Android exports. Duplicate-id guard. |
| `MapDB` | Same scan pattern as `CardDB`, over `data/maps/` into a single id-keyed `MapData` dictionary. Exposes `get_map(id)`, `list_map_ids()`, and a TEMP `get_random_map_id()` (uniform random, ignores `release_ready` on purpose — see §3) used by `PreMatchFlow` for testing until real map selection exists. |
| `EnergySystem` | Per-team energy: float pools, base regen, and a modifier list (temporary regen multipliers / cost reductions). **Zero scene/UI dependencies by design** — pure state+math so it ports to an authoritative server as-is; its only dependency is `CardDB` (cost lookup). Driven by the caller (`arena.gd` today): `reset_match_state()` / `start()` / `stop()`. Emits `energy_int_changed`. |
| `HealingSystem` | Per-team pod cooldowns + active heal-over-time state. **Zero scene/UI dependencies by design**, same contract as `EnergySystem` — no scene/node/Area2D/Sprite2D references, pure state+math so it ports to an authoritative server as-is. Third autoload with its own `reset_match_state()` (same pattern as `EnergySystem`). Death safeguard lives in the hero scripts: `die()` calls `HealingSystem.cancel_heal(team)`, which clears the active HoT and emits `heal_ended` — the same signal path a normally-completed heal uses to clear the health bar's pending band. Emits `pod_ready`, `heal_instant`, `heal_tick`, `heal_started`, `heal_ended`. |
| `MatchConfig` | Placeholder holder for pre-match display data (rank, `map_id`, both players' name/faction). `map_id` is set once by `PreMatchFlow` via `MapDB.get_random_map_id()` — `MatchConfig` itself never calls `MapDB` or resolves a display name, staying a plain data holder with no logic it doesn't own. Populated by `setup_placeholder_match()` today; matchmaking later. Display-only, never networked. |
| `InputR` | Input routing (tap-to-move targets, gesture state). |
| `Settings` | Persistent user settings. |
| `Music` | Audio. |
| `HeroAI` | Per-team HP-threshold hysteresis for the AI-controlled hero (`NORMAL` / `LOW_HP`, 20%→50% band). **Zero scene/UI dependencies by design** — pure state+math, same contract as `EnergySystem`/`HealingSystem`. Doesn't know about pods, positions, targets, or navigation — that decision-making and pathing lives in `hero_dummy.gd`. Own `reset_match_state()`. |

`BattleManager.arena_root` is injected by `arena.gd` each match (autoload has no
scene of its own to parent spawned nodes under).
 
---
 
## 3. Data layer
 
```
data/
  cards/    CardData     — id, display_name, cost, scroll_texture (AtlasTexture
                           region of the scroll spritesheet), unit_data,
                           unit_count, formation_radius
  units/    UnitData     — id, archetype_scene, max_hp, damage, attack_cooldown,
                           speed, target_filter, sprite_frames, attack_type
                           (MELEE/RANGED, Sept 2026), attack_range,
                           projectile_scene, damage_point_ratio
    frames/ SpriteFrames — extracted animation sets, swappable per unit
  heroes/   HeroData     — id, stats, projectile_scene, sprite_frames
                           (no archetype_scene: control mode picks the scene)
  spells/   SpellData    — id, display_name, spell_type (int: 0=STORM,
                           1=STUN, 2=NET), radius, cast_time,
                           zone_duration, effect_duration, damage,
                           tick_interval, slow_multiplier, sprite_frames
                           (animation names are a contract: "drag", "cast")
  maps/     MapData      — id, display_name, release_ready, map_scene,
                           bounds (Rect2), camera_edge_margin,
                           camera_edge_pan_speed_max, hero_spawn_player,
                           hero_spawn_enemy
```
 
Resolution chain for a played card:
`card_id → CardDB.get_card() → CardData.unit_data → archetype_scene.instantiate()
→ configure(data, team) → add to arena`.
 
A card with `unit_count > 1` summons a squad: `BattleManager.spawn_unit()` returns
`Array[Node]` and places each unit with a **deterministic** ring offset
(`_formation_offset()`, no RNG) so both clients derive an identical formation from
the same `{card_id, position, team}` message. Squad size lives on `CardData`, not
`UnitData`: one unit archetype can back both a single-unit and a squad card.
`BattleManager` also self-registers healing pods (`register_healing_pod()`,
called from each pod's own `_ready()`, same pattern as turrets/bases) and
exposes `get_nearest_ready_healing_pod(team, from_pos)` — strict own-side-first:
falls through to the opposite side only if the caller's own side has no
ready pod. `owning_side` on each pod is derived from its node name at
runtime (`"Player"` in the name → `"player"`), not a scene field — pods
remain fully cross-team usable for the actual heal trigger; `owning_side`
only affects AI seek-preference.
`BattleManager` tracks **protection zones** the same self-register way as
healing pods: `_protection_zones: Dictionary = {"player": [], "enemy": []}`,
populated by each structure's own `_ready()` (`register_protection_zone(zone,
owner_team)`) and cleared by its destruction handler
(`unregister_protection_zone(zone, owner_team)`) — turret/base scripts hold
their zone as an `@export var protection_zone: Rect2`, hand-tuned per
structure per map (no shared formula; see each map scene's per-node values —
`map_authoring_guide.md` has the full checklist).
`get_active_protection_zones(team) -> Array` returns a `.duplicate()` of the
live list (never the internal array itself) — used both by
`is_deploy_position_valid()` and by the UI overlay in §4. `deploy_bounds`
(the map's outer `Rect2`, set by `configure_map()`, §6) and protection zones
are two separate checks: `is_deploy_position_valid(pos, team)` first rejects
anything outside `deploy_bounds`, then rejects anything inside a **currently
active** zone belonging to the opposing team — a destroyed structure's zone
is simply absent from the list, no special-casing needed. `reset_match_state()`
resets `_protection_zones` back to the empty dict alongside the other
per-match registries. `is_card_target_valid()` (spell targeting) does **not**
consult protection zones at all — only `deploy_bounds` — which is what keeps
spells targetable anywhere on the map (`game_design.md` §3.11).
`CardData` carries **either** `unit_data` **or** `spell_data`, never both —
`CardDB._load_into()` guards this at load time and `push_error`s on a card
with neither or both. Resolution chain for a played spell:
`card_id → CardDB.get_card() → CardData.spell_data → BattleManager.cast_spell()`.
`CardDB` scans `data/spells/` as a fourth resource directory, same pattern
(and same `.tres.remap` handling) as cards/units/heroes.
`SpellData` carries **two separate durations** — `zone_duration` (how long
the area lives on the map) and `effect_duration` (how long stun/root/slow
lasts on a unit that was hit). They are not interchangeable: Storm's zone
outlives the short slow it refreshes each tick, which is what makes leaving
the zone matter. `zone_duration = 0.0` is the "instant" configuration (one
tick at impact, then free) used by Stun and Net.

`MapData` follows the same scan/lookup pattern as the other four resource
types: the `MapDB` autoload (§2) scans `data/maps/` into an id-keyed
dictionary at startup, exactly like `CardDB`. `arena.tscn` is a generic
match shell — HUD, `ArenaCamera`, `MoveMarker`, `DenialZoneOverlay`,
`DeployGhost`, and an empty `MapRoot` node — and holds **no** map content
of its own (§4). At the top of `_ready()` it resolves
`map_data = MapDB.get_map(MatchConfig.map_id)`, instantiates
`map_data.map_scene` into `MapRoot` **synchronously** (not
`call_deferred` — the map's structures must self-register into
`BattleManager` before the hero-spawn code later in the same `_ready()`),
then calls `BattleManager.configure_map(map_data)` (sets the mutable
`deploy_bounds`) and `arena_camera.configure_map(map_data)` (sets
`bounds_min`/`bounds_max`/`edge_margin`/`edge_pan_speed_max`).
`MatchConfig.map_id` is set once per match by `PreMatchFlow`, via
`MapDB.get_random_map_id()` — a uniform-random **TEMP** picker used for
testing multiple maps, not real map selection (open question,
`game_design.md` §6). `MapData.release_ready` (default `true`) marks
whether a map belongs in a future real player-facing pool; the TEMP
random picker deliberately ignores it so WIP maps stay visible while
testing — nothing filters on it yet. This is what unifies the two
previously-independent hardcoded bounds systems (§6) into one per-map
resource, and adding a new map is authoring a new `.tres` + a new map
`.tscn` (no script changes — the `MapDB` scan picks it up automatically;
see `map_authoring_guide.md` for the full checklist). Structures
(turrets/bases/healing pods) are **not** part of `MapData` — their
positions and `protection_zone` rects live on the structure nodes
themselves in each map's own `.tscn` (`scenes/arena/maps/<Name>Map.tscn`),
hand-tuned per map (see the protection-zone paragraph above and
`game_design.md` §3.7). The navigation mesh is **not** part of `MapData`
either — it lives in each map scene's own `NavigationRegion2D` (§5
Navigation).

**WIP, Sept 2026 — map visual pipeline is being migrated to tiles, one map
at a time.**
`GreekPlateauMap.tscn` was reworked as the test bed to build the map
entirely from `TileMapLayer`s instead of one background `Sprite2D` + a
single ground-collision `TileMapLayer` — the background `Sprite2D` node is
gone entirely on that map, and it now also carries the map's
`NavigationRegion2D` (§5). `NordPlainsMap.tscn` is **mid-migration** to the
same structure (`Terrain`, `Patches`, `MapBorder`, `NavigationRegion2D`
added) but still also carries its old `Rock`/`Tree`/`Wall` obstacles and
`NavigationObstacle2D`, and its navmesh is not yet correctly set up (see
`map_authoring_guide.md` §0). Don't treat either map as a finished template
for a third map without checking with the author first;
`map_authoring_guide.md` §0 has the running list of what's unresolved
before this becomes the real pipeline (and replaces, rather than sits
alongside, the checklist in that doc's §1–§4).
---
 
## 4. Battle scene structure
 
- `scenes/arena/arena.tscn` — the generic match shell, not map content:
  HUD, `ArenaCamera`, `MoveMarker`, `DenialZoneOverlay`, `DeployGhost`,
  and an empty `MapRoot` mount node. Resolves and instantiates its map at
  runtime (§3) — holds no lanes, structures, or terrain of its own.
  `_unhandled_input` tap-to-move snaps the tapped world position onto the
  navmesh (`BattleManager.snap_to_navigation()`) before handing it to
  `InputR.set_move_target()` and `MoveMarker.show_at()`, so the marker
  always shows the point the hero will actually reach (§5 Navigation).
- `scenes/arena/maps/<Name>Map.tscn` (e.g. `GreekPlateauMap.tscn`,
  `NordPlainsMap.tscn`) — one per map, instantiated into `arena.tscn`'s
  `MapRoot` at runtime. Holds that map's two horizontal lanes; per team:
  Base + 3 turrets (Top, Bot, Base). Structures self-register with
  BattleManager (combat registries **and** their `protection_zone` Rect2,
  §3); destroyed structures become wrecks (**no `queue_free()`**), which
  also unregisters their protection zone, permanently opening that slice
  of the map (`game_design.md` §3.7). See `map_authoring_guide.md` for the
  full checklist to add a new one.
  **Tile-built structure (`GreekPlateauMap.tscn`; `NordPlainsMap.tscn`
  mid-migration — see the note in §3 and `map_authoring_guide.md` §0):**
  ground is a `Terrain/TileMapLayer` (no background `Sprite2D`), obstacles
  split into a visual `Obstacles/TileMapLayer` plus collision-only
  `Patches/*` instances (`LargePatch.tscn`/`SmallPatch.tscn`, both
  inheriting a script-free base scene, `ObstaclePatch.tscn` —
  `StaticBody2D`, `collision_layer=4`/`collision_mask=0`, one
  `CollisionPolygon2D` in `Solids` build mode seeded with a small
  placeholder square so it's never an invalid empty polygon), a
  `MapBorder` node (`scenes/arena/maps/MapBorder.tscn` /
  `scripts/arena/map_border.gd`) giving the map an actual outer physical
  boundary, and one `NavigationRegion2D` (§5 Navigation). `Patches`,
  `PlayerStructures` and `EnemyStructures` are in the `nav_obstacle`
  group — that's what carves the navmesh holes; `MapBorder` is
  deliberately not.
  **Old structure (NordPlains before its migration):** background
  `Sprite2D`; one ground-collision `TileMapLayer`; `Obstacles` with
  `Rock`/`Tree`/`Wall` instances; an unconfigured `NavigationObstacle2D`
  that nothing reads (a leftover — safe to delete once the migration is
  done); no physical outer boundary, only the logical `MapData.bounds`
  rectangle (camera clamp + deploy check).
- `scenes/arena/units/melee_unit.tscn` and `scenes/arena/units/ranged_unit.tscn`
  (Sept 2026) — two sibling archetype scenes (CharacterBody2D + Hurtbox +
  AttackRange + AggroRange + AnimatedSprite2D + HealthBar + TargetMarker +
  `NavAgent`), **both attaching the same `unit.gd` script** — they differ only
  in scale and their own scene-baked `AnimatedSprite2D`/`AttackRange` defaults
  (editor-preview/crash-prevention values only, same footgun as
  `player.tscn`/`hero_dummy.tscn`, see `hero_authoring_guide.md` §1 —
  `configure()` always overwrites both from `UnitData` at spawn). Melee vs.
  ranged combat *behavior* is a data branch inside `unit.gd`
  (`UnitData.attack_type`), not a script fork — see §5 and
  `unit_authoring_guide.md`. Siege archetypes, if they diverge in movement/
  targeting rather than just attack resolution, would be a genuine new
  sibling script; a third *attack type* would not. **Both scenes must carry
  the `NavAgent` child** — `unit.gd` resolves it with `@onready`, so a scene
  missing it crashes on spawn (§6). `ranged_unit.tscn`'s root node is still
  named `MeleeUnit` (duplication leftover, harmless, rename when convenient).
- `scenes/arena/player.tscn` — locally-controlled hero. Carries a `NavAgent`
  (`NavigationAgent2D`) child (§5 Navigation).
- `scenes/arena/hero_dummy.tscn` (`hero_dummy.gd`) — AI-controlled enemy hero
  avatar. Movement/targeting/combat logic ported from `player.gd` (same
  fields, `find_nearest_enemy()`/`_try_fire()`/`fire_bolt()`, same
  animation helpers), driven instead by `HeroAI`'s hp-state output:
  `NORMAL` → march toward nearest enemy structure (`BattleManager.
  get_nearest_structure()`, interval-refreshed same as `unit.gd`); `LOW_HP`
  → seek nearest ready healing pod (`BattleManager.
  get_nearest_ready_healing_pod()`), falling back to retreat toward own
  spawn if no pod anywhere is ready (retreat point snapped onto the navmesh,
  §5). Walking onto a pod triggers the heal automatically via the pod's
  existing `area_entered` handler — no explicit "use pod" call from the AI.
  All three destinations go through the single `_steer_towards()`, which
  follows the navmesh via its own `NavAgent` child. Card-play AI lives in
  `enemy_card_ai.gd`. Now also wires `target_marker` (see §6).
  Both expose `configure(data, team)`, `die()`, `revive()`.
- `scenes/arena/DeployGhost.tscn` (`deploy_ghost.gd`) — world-space drag-to-deploy
  preview: a translucent circle at the drop position, green = legal, red = not.
  Drawn in `_draw()` (no assets). Sibling of `MoveMarker`, driven by `arena.gd`
  from `CardHand` signals (CardHand is in a CanvasLayer; the ghost is world-space).
  One child, `ScrollAnim` (`AnimatedSprite2D`, no frames assigned in the scene) —
  plays the spell's `"drag"` animation just above the circle while dragging.
  `configure_for_card()` runs **once per drag** (from `deploy_preview_started`)
  and sets both the radius and the animation: spell cards get the spell's *real*
  `radius` so the circle shows exactly what will be hit; unit cards get the flat
  `unit_radius` and no animation. Per-frame position still comes through
  `deploy_preview_updated`, whose signature is unchanged.
- `scenes/arena/DenialZoneOverlay.tscn` (`denial_zone_overlay.gd`) — world-space
  UI hint, sibling of `DeployGhost`, drawn in `_draw()` at a fixed
  `position = Vector2(0,0)` (it draws directly in the zones' own world-space
  coordinates, unlike `DeployGhost` which recenters on the drag point). Cheap
  per-zone approach instead of a shader: `show_for_card(card)` (called from
  `deploy_preview_started`) iterates
  `BattleManager.get_active_protection_zones(enemy_team)` and `draw_rect()`s
  each one directly — no composite "hole" geometry, so overlapping zones look
  slightly darker where they overlap (accepted cosmetic trade-off; no live
  per-frame re-evaluation mid-drag). `show_for_card()` early-outs to
  `visible = false` when `card.spell_data != null`, since spells aren't
  restricted by protection zones (`game_design.md` §3.11) — only unit-card
  drags show the overlay. `hide_zones()` (from `deploy_preview_ended`) hides
  it again. `DRAGGING_TEAM` is currently a hardcoded `"player"` const, same
  TEMP assumption as `card_hand.gd` (only the local player drags cards today).
- `scenes/arena/HealingPod.tscn` (`healing_pod.gd`) — static pickup, `Area2D`
  with `collision_layer=0`, `collision_mask=24` (bits 4+5 — same hurtbox mask
  pattern as `LightningBolt`). Team is resolved on `area_entered` from the
  entering Area2D's `player_hurtbox`/`enemy_hurtbox` group, not layer bits —
  cross-team usable by design (either hero can use either pod). Activation is
  a `Sprite2D` texture swap (`pod_active.png`/`pod_inactive.png`), no
  `AnimatedSprite2D`. Cooldown and HoT state live in `HealingSystem`; the node
  is sensor + visual only. 4 static placements per map scene (inside
  `PlayerStructures`/`EnemyStructures`), one per lane per side
  (`HealingPodPlayerTop/Bot`, `HealingPodEnemyTop/Bot`). Being an `Area2D`,
  a pod is ignored by the navmesh bake even though its parent container is
  in the `nav_obstacle` group — pods stay walkable, which is required.
- `scenes/arena/SpellZone.tscn` (`spell_zone.gd`) — the **single** runtime
  node behind every spell. `Node2D` with a single `CastAnim`
  (`AnimatedSprite2D`) child, **no `Area2D` and no
  collision shape**: targeting is a per-tick radius query, not physics
  overlap. Two phases driven in `_process`: `PHASE_CAST` (lasts
  `cast_time`, draws a warning circle, applies nothing) then `PHASE_ZONE`
  (first tick fires *exactly* at impact, then every `tick_interval` for
  `zone_duration`, re-querying targets each time). `zone_duration = 0.0`
  → one tick, then `queue_free()`. Spawned by `BattleManager.cast_spell()`
  with the same `instantiate() → configure() → add_child()` contract units
  and heroes use. During `PHASE_CAST`, `CastAnim` plays the spell's `"cast"`
  animation stretched via `speed_scale` to finish *exactly* at impact, then
  stops and hides — the placeholder `_draw()` circle (orange = casting,
  purple = active zone) carries the zone phase alone until impact/duration
  art exists.
- `scenes/arena/ui/EnergyBar.tscn` (`energy_bar.gd`) — player energy bar in the
  HUD. Polls `EnergySystem.get_energy("player")` each frame for the fill. `Bar`
  is a `TextureProgressBar` (gold fill texture, left-to-right) behind a
  `FrameOverlay` stone frame, with an `EmptyBg` ColorRect showing through empty
  cells; the count label updates from `energy_int_changed`. `bar` stays typed
  `Range`, so the swap from the placeholder `ProgressBar` needed no script change.
- `scenes/hud/HUD.tscn` (CanvasLayer) — TouchScreenButtons (pause, recenter),
  `CardHand` (hand + draw cycle in `card_hand.gd`; `play_card(slot_index, world_pos)`
  is the single card-play entry point — drag-to-deploy calls it today, future
  double-tap and the network handler call the same function — which now also
  spends energy via `EnergySystem.try_spend()` and refuses unaffordable plays; emits
  `deploy_preview_started` (once, at drag start, carrying the `CardData`) /
  `deploy_preview_updated` / `deploy_preview_ended` for `arena.gd` to drive the
  DeployGhost), `EnergyBar`, `MatchInfoBar` (timer label, tower icons, two
  `RespawnCounter`s driven by BattleManager signals).
  `play_card()` branches on payload type: `unit_data` → `BattleManager.spawn_unit()`,
  `spell_data` → `BattleManager.cast_spell()`. Both the live drag preview and
  the release check call `BattleManager.is_card_target_valid(card, pos, team)`.
- `scenes/ui/PreMatchFlow.tscn` (`prematch_flow.gd`) — placeholder pre-match
  flow: a "searching for battle" panel then a versus panel, each ~1s, then
  `change_scene_to_file(arena.tscn)`. Reached from the main-menu Battle card
  (§8). Also resolves this match's map: calls `MapDB.get_random_map_id()` into
  `MatchConfig.map_id` once, and shows the resolved `MapData.display_name`
  on the finding screen (§3). Faction/avatar are ColorRect placeholders
  pending assets.
### Key BattleManager signals
 
`match_ended(winner)`, `match_time_tick(seconds_left)`,
`hero_died(team, respawn_seconds)`, `hero_respawn_tick(team, seconds_left)`,
`hero_respawned(team)`.
 
---
 
## 5. Combat & movement model
 
- `team` is a String (`"player"`/`"enemy"`); groups `team_player`/`team_enemy`.
- **Collision layers are computed at runtime** in `_ready()` from team
  (hurtbox layer constants in `unit.gd`); never baked per-team into scenes.
- Unit state machine: `MARCHING → CHASING (AggroRange) → ENGAGING (AttackRange)`.
  March target = `BattleManager.get_nearest_structure()`, refreshed on an interval,
  not per frame. Separation steering with cached interval updates. Units only
  collide with layer 4 (`collision_mask = 4`: structures/obstacles/border) —
  not with each other or with heroes; separation is the only thing spacing a
  squad apart.
- **Navigation (Sept 2026) — every mover follows a baked navmesh; the
  navmesh only picks the direction, never the velocity.**
  - *Map side.* Each map scene carries one `NavigationRegion2D`. Its
    `NavigationPolygon`'s walkable **outline** is hand-drawn to match the
    `MapBorder` shape; the **holes** are baked from source geometry:
    `Parsed Geometry Type = Static Colliders`, `Parsed Collision Mask = 4`,
    `Source Geometry Mode = Groups With Children`, group `nav_obstacle`
    (on `Patches`, `PlayerStructures`, `EnemyStructures`). `MapBorder` is
    intentionally outside the group (§6). Agent radius is the default 10 px
    (hero body circle is 7 px; unit 16×16 box reaches ~11 px at the corners —
    accepted, they just slide past corners). Baked **at edit time, static**:
    nothing on the map changes topology mid-match (structure wrecks never
    `queue_free()`), so there's no runtime rebaking.
  - *Mover side.* `player.tscn`, `hero_dummy.tscn`, `melee_unit.tscn` and
    `ranged_unit.tscn` each carry a `NavAgent` (`NavigationAgent2D`) child —
    `path_desired_distance = 4`, `target_desired_distance = 8`, avoidance
    **off**. Each of the three scripts has its **own verbatim copy** of
    `_nav_direction_to(goal) -> Vector2` (same deliberate duplication as the
    status effects, §6). It returns only a unit direction; each script's
    existing pipeline (windup lock, root, slow, `velocity`, `move_and_slide()`,
    animation) is unchanged. `NavigationAgent2D.velocity` / `velocity_computed`
    are not used anywhere.
  - *Where it plugs in.* `player.gd`: `get_move_input()` (tap-to-move) and
    the `primary_target` chase branch. `hero_dummy.gd`: inside
    `_steer_towards()`, so march, pod-seek and retreat all path. `unit.gd`:
    inside `_steer_towards()`, where the navmesh direction replaces only the
    **seek** term — separation is still added on top, unchanged.
  - *Repath rule.* The agent's `target_position` is only re-sent when the
    goal moved more than 16 px (`NAV_REPATH_DIST_SQ`) since the last one
    (`_nav_goal`), so chasing a moving target doesn't recompute the path
    every frame. `_nav_goal = Vector2.INF` forces a fresh path — reset on
    tap-to-move arrival and `on_new_move_command()` (player), and in
    `die()`/`revive()` (both heroes). Units never revive, so they don't reset.
  - *Goals inside a hole.* A structure sits inside a navmesh hole, so the path
    ends at the hole's edge; when `is_navigation_finished()` is true the helper
    falls back to direct steering for the last few pixels and the existing
    `AttackRange` overlap check takes over. No snapping of structure/pod goals.
  - *Queries.* `BattleManager.has_navigation()` is false when the current map
    has no `NavigationRegion2D` **and** on the first physics frame after load
    (`map_get_iteration_id() == 0`, server not synced yet) — every
    `_nav_direction_to()` then falls back to straight-line steering, i.e. the
    pre-navmesh behavior. `BattleManager.snap_to_navigation(pos)` returns the
    closest navmesh point (unchanged without a navmesh); used for the
    tap-to-move target (`arena.gd`) and the AI hero's retreat point (a spawn
    point inside the 10 px agent-radius margin would otherwise never satisfy
    the 8 px arrival check).
  - *Not built yet.* Deploy validation doesn't consult the navmesh —
    `is_deploy_position_valid()` still only checks bounds, own half and
    protection zones, so a unit card can be dropped inside a patch (next
    step: reject positions off the navmesh). No RVO avoidance — deliberately
    off; if squads clump at chokepoints the first lever is separation
    tuning, RVO is a separate decision (it changes how velocity is owned).
- **Minions get a two-phase attack windup too (Sept 2026), but a
  deliberately simpler one than heroes'.** `UnitData.attack_type`
  (MELEE/RANGED) and a data-driven `attack_range` (replacing what used to
  be a scene-baked `AttackRange` radius) drive `_process_engaging()`:
  on entering range, the unit winds up for `damage_point_ratio` (same
  0.0-1.0 semantics and 0.7 default as `HeroData`) of the live-derived
  `"attack"` animation duration, then resolves — direct `take_damage()` for
  MELEE, or spawns the same `projectile.tscn` heroes already fire for
  RANGED — and `attack_cooldown` (unchanged field, now playing the role
  `HeroData.recovery_time` plays for heroes) starts counting from that
  point. Unlike heroes, this is implemented as a **plain countdown
  (`windup_left`) inside the existing synchronous `_physics_process` state
  machine, not an `await` coroutine** — `unit.gd` had no async patterns
  before this and shouldn't gain one just for a windup timer. The payoff:
  since nothing disables `_physics_process` during a minion's windup (unlike
  heroes' `set_physics_process(false)`), the pre-existing stun
  freeze-and-resume behavior (see §6) already covers a stun landing
  mid-swing correctly, with no direct-cancel hook needed. Minions also get
  **no** cancel-on-new-command mechanic — they have no player-issued
  commands to cancel on, and no AI retreat state either; a target leaving
  `attack_range` mid-windup is left to the existing march-state fallthrough
  (`ENGAGING → CHASING` silently abandons the pending windup, no hit, no
  explicit cancel-animation) rather than a built interrupt system. Full
  detail in `unit_authoring_guide.md` §2.2.
- **Hero attacks are an interruptible two-phase cast-point (Sept 2026).**
  Targeting priority is unchanged: manual primary target (tap) with chase,
  auto-target fallback without chase. The swing itself now splits at
  `HeroData.damage_point_ratio` (0.0-1.0, default `0.7`) of the live-derived
  cast-point (`attack_left`'s `frame_count/speed`, same derivation as
  always). Before that fraction elapses the hero hasn't committed — a
  genuinely new command (a new tap-to-move, or an explicit tap on a
  *different* target) cancels the swing for free: no damage, `fire_left`
  reset to 0, animation snapped to idle, movement unlocked immediately.
  Re-issuing the same target mid-swing is a no-op, not a cancel. At/after
  the damage point the hit lands right then and movement unlocks
  immediately either way, with `recovery_time` now counting from the
  damage point rather than the old full-animation end. This replaced a
  single monolithic movement-lock for the whole `attack_left` duration
  with no way to interrupt it — the cause of a "hero feels rooted mid-fight"
  bug (tap-move, arrive, auto-fire on a newly-arrived enemy, then be stuck
  for the full swing before the next tap-move could even register). Full
  mechanic and per-hero tuning guidance live in `hero_authoring_guide.md`
  §2.2 — this doc covers the *why*, that one covers the *how to tune it
  per hero*.
- **AI retreat interrupts an in-progress swing.** `hero_dummy.gd`'s
  `HeroAI` NORMAL⇄LOW_HP hysteresis flip cancels a mid-swing attack via
  the same cancel path player commands use, hooked into `take_damage()`
  rather than `_physics_process` (see §6 for why). Meant to be the first
  of several future AI "interrupt and reconsider" triggers (e.g. spotting
  a higher-priority target) — only the HP-retreat one exists today.
- Hero death: hide + disable (collision & hurtbox zeroed deferred → attackers get
  `area_exited` and disengage), unregister, respawn via BattleManager countdown.
- Range checks use `distance_squared_to()`.
- **Deploy zone:** `BattleManager.is_deploy_position_valid(pos, team)` is the single
  source of truth — the live drag preview (circle colour) and the spawn on release
  both call it, so they cannot disagree. Today: inside `DEPLOY_BOUNDS` and on the
  team's own half (midline `x = 0`). It is **positional only** (takes no `card_id`);
  energy affordability is a *separate* check and is deliberately NOT folded in here,
  so the red circle never conflates "bad spot" with "can't afford". Future zone
  rules (expansion on turret kill, obstacles / off-navmesh rejection) go inside
  this function.
  - **Spell targeting:** `BattleManager.is_card_target_valid(card, pos, team)`
  is the single source of truth for *both* card types and wraps (never
  modifies) `is_deploy_position_valid()`. Spells: inside `DEPLOY_BOUNDS`
  only, either half. Units: the existing own-half rule, untouched.
- **AoE queries:** `BattleManager.get_targets_in_radius(pos, radius, affected_team)`
  is the shared radius query — **team-scoped by parameter, never
  position-only**. `SpellZone` passes the caster's *opposing* team, so
  spells can't friendly-fire. Public (no leading underscore) because it is
  called from outside the autoload; future AoE unit attacks should call this
  same helper rather than rolling their own overlap scan.
- **Spell effects are a re-query per tick, never a snapshot.** `SpellZone`
  calls `get_targets_in_radius()` fresh on every tick, so a unit that walks
  into an active Storm gets hit and one that walks out stops being hit.
  Holding a target array across time was the *old* model and was deliberately
  removed — if a future spell needs stick-to-the-target behaviour
  (poison/bleed), that belongs as per-unit state on the victim, like the
  status timers, not as an array held by the caster.
- **`cast_spell()` applies nothing.** It validates the card and spawns a
  `SpellZone`; all timing and all effect application live on that node. This
  keeps every spell's lifetime bound to the arena scene tree.
- **Status effects** live as plain per-instance state (`stun_left`,
  `root_left`, `slow_left`, `slow_multiplier` + `apply_stun()` /
  `apply_root()` / `apply_slow()`) duplicated **independently** in
  `unit.gd`, `player.gd`, and `hero_dummy.gd` — no shared base class, same
  principle as the HealingSystem signal hooks. Stun short-circuits at the
  top of `_physics_process` (movement *and* attack cooldown both freeze);
  root zeroes movement only, inside the steering function; slow multiplies
  the velocity magnitude. None of the three interacts with navigation: the
  agent's path simply waits while the mover is stunned/rooted and resumes
  afterwards. **Sept 2026: `player.gd`/`hero_dummy.gd`'s
  `apply_stun()` additionally cancels a mid-swing attack outright (see the
  bullet above and §6) — this is no longer byte-identical to `unit.gd`'s
  version. `unit.gd` gained its own windup (`windup_left`, see above) but
  deliberately did NOT gain an equivalent cancel call: its windup is a
  plain `_physics_process` timer rather than an `await` coroutine, so the
  existing freeze-and-resume stun behavior already pauses it correctly —
  adding a direct cancel there would be solving a problem `unit.gd` doesn't
  have.**
---
 
## 6. Conventions & known pitfalls (hard-won)
 
- Signal connections in `_ready()`, not the Inspector.
- `configure()` must be callable **before** `add_child()` — use `$Node` paths
  inside it, not `@onready` vars.
- Child `_ready()` runs before parent `_ready()` → per-match resets belong in the
  arena's `_enter_tree()`.
- `is_instance_valid()` guards wherever a stored target can die.
- `CollisionShape2D` shape resources: mark **Local to Scene**; never mutate shared
  shapes at runtime.
- Leash/exit logic: don't rely on `body_exited` at the same boundary as
  `body_entered`; use `_physics_process` distance checks.
- `get_path()` is reserved on Node — lane paths use `get_lane_path()`.
- Android: `.tres.remap` suffix stripping in any `DirAccess` scan;
  `emulate_mouse_from_touch = true`; `TextureButton` for menus,
  `TouchScreenButton` in-game.
- UI art scaling: `TextureRect` with `EXPAND_IGNORE_SIZE` +
  `KEEP_ASPECT_CENTERED` — never manual scale factors.
- Autoload state outlives scenes: every new per-match variable in BattleManager
  **must** be added to `reset_match_state()` (or documented as persistent).
- Card drag input is tracked in `card_hand.gd::_input()` by touch index, not in
  `_gui_input`. `_input` runs before the GUI system and before `_unhandled_input`,
  so consuming there deterministically starves `arena_camera.gd` (pan) and
  `arena.gd` (tap-to-move). `Card._gui_input` only detects the press and hands off
  to `CardHand.begin_drag()`. The drag path deliberately does NOT use
  `InputR.suppress_next_release()` — it consumes its own release; that one-shot flag
  would otherwise linger and swallow the next tap-to-move.
- **Resolved:** the above starvation is why drag-to-deploy needed its own
  camera hook instead of reusing `arena_camera.gd`'s pan handler. `ArenaCamera`
  now exposes `begin_deploy_pan()` / `update_deploy_pan(screen_pos)` /
  `end_deploy_pan()`, driven from `arena.gd`'s existing
  `deploy_preview_started` / `deploy_preview_updated` / `deploy_preview_ended`
  handlers rather than from raw input — `deploy_preview_updated` now also
  carries the drag's screen position (not just world position) specifically
  so the camera can do screen-edge proximity panning without ever needing the
  starved input events. Runs independently of `Settings.lock_camera` (checked
  in `_physics_process` *before* the lock gate); only the post-release
  behaviour branches on lock state, and does so by reusing the existing
  `_return_timer`/`_return_ramp`/`return_delay`/`return_ramp_time` fields
  rather than adding a parallel return mechanism.
- **`Camera2D`'s native `limit_left`/`limit_right`/`limit_top`/`limit_bottom`
  are a second, engine-level clamp — separate from `arena_camera.gd`'s own
  `bounds_min`/`bounds_max` + `_clamp_to_bounds()`.** Both can be active at
  once, and the engine's native limit wins if it's more restrictive, which
  makes changing `bounds_min`/`bounds_max` in the Inspector look like it does
  nothing. `arena_camera.gd` now forces the native limits wide open in
  `_ready()` so `bounds_min`/`bounds_max` is unconditionally the only clamp
  that applies, regardless of whatever `limit_*` values happen to be saved on
  the `Camera2D` node (easy to inherit by duplicating a scene, since it's a
  separate Inspector section from the script's own exported vars).
- **Resolved:** the two independently-hardcoded bounds systems referenced
  above (native `Camera2D` limits vs. the script's own `bounds_min`/
  `bounds_max`) are now both driven from one place — `MapData.bounds`,
  applied via `arena_camera.configure_map(map_data)` — and
  `BattleManager.deploy_bounds` (formerly a `const DEPLOY_BOUNDS`, now
  mutable) is set from the same resource via
  `BattleManager.configure_map(map_data)`, both called once from
  `arena.gd._ready()`. One `MapData.tres` per map now fully describes bounds,
  camera pan tuning, and hero spawn points (§3).
- **`ArenaCamera`'s initial `position`/`zoom` are NOT per-map.** They're
  hardcoded on the `Camera2D` node inside `arena.tscn` (the shared shell) —
  `configure_map()` only ever touches `bounds_min`/`bounds_max`/
  `edge_margin`/`edge_pan_speed_max`. Works today because both existing
  maps (`GreekPlateauMap`, `NordPlainsMap`) share the same bounds size; a
  map with meaningfully different dimensions will likely need this
  addressed (a `camera_start_position`/`camera_start_zoom` on `MapData`,
  most likely) — noted in `map_authoring_guide.md` §2.9, not built yet.
- `CardHand` is inside a CanvasLayer → screen→world goes through
  `get_viewport().get_canvas_transform()`, not plain `get_canvas_transform()`
  (which returns the layer transform). Node2Ds like `arena.gd` use the plain form.
- **A second autoload (`EnergySystem`) now holds per-match state outside
  `BattleManager.reset_match_state()`.** Its OWN `reset_match_state()` must be called
  from `arena._enter_tree()` alongside BattleManager's. Same pitfall as the
  BattleManager reset rule above, second owner: every new per-match field in
  EnergySystem must be reset there, or it leaks across matches (leaked modifiers,
  stale energy).
- HUD child `process_mode`: the `HUD` CanvasLayer is `WHEN_PAUSED` (so the settings
  overlay runs while paused); children that must run DURING play set their own
  `process_mode`. `EnergyBar` is `PAUSABLE` — it polls in `_process()`, so inheriting
  `WHEN_PAUSED` would freeze the bar during play and only move it while paused.
- Typing a bar reference as `Range` (the shared base of `ProgressBar` and
  `TextureProgressBar`) let the energy bar's placeholder→textured swap happen
  with zero script change — `energy_bar.gd` still only touches
  `min_value`/`max_value`/`value`. Reach for the base class when a UI node is a
  known future art-swap target.
- **A third autoload (`HealingSystem`) also holds per-match state outside
  `BattleManager.reset_match_state()`.** Its OWN `reset_match_state()` must be
  called from `arena._enter_tree()` alongside BattleManager's and
  EnergySystem's. Same pitfall as the EnergySystem reset rule above, third
  owner: every new per-match field in HealingSystem must be reset there, or it
  leaks across matches (stale pod cooldowns, stuck HoT).
- Hero `Hurtbox` groups (`player_hurtbox`/`enemy_hurtbox`) — added for
  collision-layer/team wiring — turned out reusable as a plain team-detection
  signal for non-combat systems too, not just combat targeting:
  `HealingPod._on_area_entered()` reads the group off the entering Area2D to
  resolve team, no layer-bit math needed. Worth reaching for before inventing
  a parallel team-tag mechanism.
- **Autoload enums can't be used as type annotations or `match` patterns.**
  `HeroAI.State` can't do `var s: HeroAI.State` or `match s: HeroAI.State.X:`
  — an autoload is a singleton *instance*, not a `class_name`, so its enum
  isn't a real type in that sense. Runtime access like
  `HeroAI.State.LOW_HP` in expressions/comparisons is fine; cache the
  value as untyped/`int` and branch with `if`/`elif` instead of `match`.
- **A fourth autoload (`HeroAI`) holds per-match state outside
  `BattleManager.reset_match_state()`.** Same pitfall as `EnergySystem`/
  `HealingSystem`: its own `reset_match_state()` must be called from
  `arena._enter_tree()` alongside the other three, or the low-HP hysteresis
  flag leaks across matches.
- `hero_dummy.tscn`'s `TargetMarker` node existed unused in the scene since
  its creation — `melee_unit.tscn` hides its own copy in the scene file,
  but the hero scene didn't, so it was invisibly always-on until wired up
  in `hero_dummy.gd` (`set_targeted()` + hidden in `_ready()`/`die()`).
  Worth double-checking for other copy-pasted scene subtrees with the same
  silently-active-node issue.
- `BattleManager`'s healing-pod registry needs the same `tree_exited`
  cleanup as the unit registries (`register()`), not the "permanent wreck,
  never freed" pattern turrets/bases use — `single_use` pods (future
  portable pods) actually `queue_free()` themselves, unlike turrets/bases.
- **Status effects are duplicated by design, not by omission.** `apply_stun`/
  `apply_root`/`apply_slow` are near-identical in three files (Sept 2026:
  `player.gd`/`hero_dummy.gd`'s `apply_stun()` now additionally cancels a
  mid-swing attack, see below — so the three are no longer byte-identical,
  but the divergence is a direct, intentional consequence of only heroes
  having a lockable windup at all). Resist the refactor into a shared parent
  or component: the three scripts have genuinely different movement
  pipelines (`unit.gd` steers with separation, `player.gd` blends
  tap-to-move with chase, `hero_dummy.gd` is single-target steering) and
  the *insertion points* differ even though the timers don't. A shared
  class would force those pipelines to converge. `MapDB` follows the same
  discipline: it duplicates `CardDB`'s scan/load pattern verbatim rather
  than extracting a shared base class (see §2/§3) — two unrelated small
  scanners, not a reason to generalize yet. **`_nav_direction_to()` (§5
  Navigation) follows the same rule** — three verbatim copies, one per
  movement script, plugged in at each script's own insertion point. Keep the
  three copies in sync by hand if one changes.
- **A stunned unit's `attack_left` also stops ticking.** The stun early-return
  sits *above* the cooldown decrement in `_physics_process`, so a unit
  stunned mid-cooldown resumes with the same cooldown remaining rather than
  attacking instantly on recovery. Intentional; don't "fix" it by moving the
  decrement above the stun check. **Heroes diverge from this for an
  in-progress swing specifically (Sept 2026):** a locked windup disables
  `_physics_process` entirely (`set_physics_process(false)`), so the
  freeze-and-resume behavior above literally cannot apply to a mid-swing
  stun — the stun timer wouldn't even be evaluated until the swing finished
  on its own. `player.gd`/`hero_dummy.gd`'s `apply_stun()` now calls
  `_cancel_attack_windup()` directly when landing mid-swing, canceling the
  attack outright instead of pausing it. `unit.gd` minions are unaffected
  (no cast-point system to interrupt) and this bullet's original
  freeze-and-resume behavior still fully applies to their plain
  `attack_cooldown` timer, and to a hero's own *cooldown* between swings —
  and (Sept 2026) to `unit.gd`'s new `windup_left` timer too, by the same
  logic: it's just another countdown that lives inside `_physics_process`,
  which already early-returns on `stun_left > 0.0` before reaching it. This
  is the reason `unit.gd`'s windup was deliberately built as a plain timer
  rather than a copy of the hero `await` pattern — it gets correct stun
  behavior for free instead of needing the direct-cancel workaround heroes
  required.
- **`attack_range` as a stat name collides with `attack_range` as an
  Area2D node reference.** `unit.gd` used to have only
  `@onready var attack_range: Area2D = $AttackRange`; adding a data-driven
  `attack_range: float` stat (Sept 2026, mirroring `HeroData`) required
  renaming the node reference to `attack_range_area`, matching the split
  `player.gd`/`hero_dummy.gd` already used (`attack_range: float` stat vs.
  `attack_range_area: Area2D` node). Any future archetype adding a
  `HeroData`/`UnitData`-style data-driven range stat should use this same
  `<stat>` / `<stat>_area` naming split from the start rather than
  colliding with whatever `@onready` name came first.
- **A locked windup disables `_physics_process` outright, so anything meant
  to interrupt it can't wait for the next physics frame.** `_perform_attack()`'s
  `set_physics_process(false)` (unless `can_move_while_attacking`) means the
  entire per-frame update — including any status-timer countdown or state
  check — simply doesn't run until the windup ends or cancels on its own.
  Every interrupt trigger added so far (`on_new_move_command()`,
  `set_primary_target()` targeting a new node, `apply_stun()`, and
  `hero_dummy.gd`'s HP-hysteresis flip via `take_damage()`) is therefore
  hooked directly at the call site that changes the relevant state, calling
  `_cancel_attack_windup()` synchronously — never inferred later inside
  `_physics_process`. Keep this pattern for any future interrupt condition
  (e.g. an AI "higher-priority target spotted" trigger).
- **Timed multi-second effects belong on a scene node, not in an autoload.**
  Storm's damage-over-time was originally an `await`-based loop inside
  `BattleManager` holding a target snapshot across several seconds — which
  survived units dying (`is_instance_valid()` per tick) but was *not* safe
  against a match ending or scene change mid-loop. Moving the timing into
  `SpellZone`'s `_process` fixed that for free: the node is a child of the
  arena, so match end, scene change, and `reset_match_state()` all clean it
  up with no guard code. Reach for this pattern before adding another
  `await` chain to an autoload. Note the deliberate consequence —
  **`SpellZone` state is intentionally absent from every
  `reset_match_state()`**, unlike the four autoloads; scene ownership is the
  reset mechanism.
- **Never mutate a shared `SpriteFrames` at runtime.** Stretching a spell's
  cast animation to fit `cast_time` is done with
  `AnimatedSprite2D.speed_scale` on the *node*
  (`speed_scale = frame_count / animation_speed / cast_time`), never with
  `set_animation_speed()` / `set_animation_loop()` on the resource — those
  would leak across every instance using that resource. Same rule as "never
  write runtime state back into a resource" in §1, one step further: playback
  parameters are node state too.
- **Animation names are a contract for spells as well as units.** Spell
  `SpriteFrames` must expose `"drag"` and `"cast"`; both playback sites guard
  with `has_animation()`, so a spell with a missing or absent frames resource
  degrades to the plain circle instead of erroring. `"cast"` is authored with
  `loop = 1` and is never visibly seen looping because the node hides it at
  the phase flip — don't "fix" the resource.
- **Control siblings draw in child order — later siblings draw on top —
  regardless of each one's own `visible` state.** A hidden fullscreen overlay
  declared *before* an opaque sibling in the scene tree stays visually buried
  under it even once `visible = true`; the fix is `Control.move_to_front()`
  at open time, not a permanent scene reorder. First hit on `MainMenu.tscn`'s
  `SettingOverlay`/`CreditsOverlay` vs. `Background` (§8) — worth checking
  first whenever a Control-based overlay "doesn't show" despite `visible`
  being true and no texture/logic bug found.
- **A `Node2D` child of a `Control` container is not auto-arranged by it.**
  Containers (`HBoxContainer`, `CenterContainer`, …) only lay out `Control`
  children; a `Node2D` (e.g. an `AnimatedSprite2D`) parented under one keeps
  whatever `position` it's given, unaffected by the container's sizing pass.
  Center or position it manually — via the parent Control's `resized` signal,
  not a hardcoded offset, so it stays correct across the different canvas
  shapes `window/stretch/aspect = "expand"` produces per device. First hit on
  `MainMenu.tscn`'s hero showcase (§8).
- **A filled (`Solids` build-mode) `CollisionPolygon2D` is for something you
  can't enter, not for something you can't leave.** `MapBorder`'s first
  version used `Solids`, which treats the whole polygon interior as solid
  mass — the hero spawned inside the border's own footprint and got pushed
  *out* of the playable area instead of contained by it. `build_mode =
  Segments` is the correct mode for any boundary/containment shape (a
  two-sided wall along the outline only, no fill); `Solids` stays correct
  for actual obstacles (rocks, `ObstaclePatch` blobs) where the whole
  footprint should genuinely be impassable from every direction. Don't
  copy `build_mode` between the two use cases — they solve opposite
  problems.
- **`MapBorder.tscn` currently carries two `CollisionPolygon2D` children**
  — `CollisionPolygon2D` (written by `map_border.gd`'s `@tool` parametric
  generator) and `CollisionPolygon2D2` (hand-traced), with only the
  hand-drawn one enabled (`disabled = true` on the generated one) for
  side-by-side testing. This is a deliberate temporary state for
  comparison, not a finished design — **pick one approach and remove the
  other's node before release**; a `StaticBody2D` with two enabled shape
  children unions both, which was never the intent here. The navmesh's
  walkable outline is hand-drawn to match the **hand-traced** border; if the
  border shape changes, redraw the outline and rebake.
- **Navmesh bake source: groups, never "everything on layer 4".** The
  `NavigationPolygon`'s default `Source Geometry Mode = Root Node Children`
  only parses nodes *under* the `NavigationRegion2D` — obstacles living
  elsewhere in the map scene produce a mesh with no holes at all. Using
  plain collision-mask parsing would pull in `MapBorder` too, and a border
  parsed as an obstruction can carve out the entire arena. Use
  `Groups With Children` + the `nav_obstacle` group on the obstacle/structure
  containers only; `MapBorder` stays out of the group, and the walkable
  outline is drawn by hand instead.
- **A TileSet with a Navigation Layer silently adds a second navmesh.** Any
  `TileMapLayer` whose tiles carry navigation polygons registers its own
  navigation regions on the same map, overlapping the baked one and ignoring
  its holes. The Greek tileset has no navigation layer by design; keep it
  that way for every new tileset (or turn off the layer's
  `Navigation → Enabled`).
- **Copying a `NavigationRegion2D` between maps copies the baked polygons
  too.** The `NavigationPolygon` sub-resource stores the bake result
  (`vertices`/`polygons`), not just the settings — duplicating it into another
  map scene gives that map the *other* map's holes until you set the
  `nav_obstacle` groups on the new map and press **Bake NavigationPolygon**
  there. Always rebake per map.
- **Every mover archetype scene must carry `NavAgent`.** `player.gd`,
  `hero_dummy.gd` and `unit.gd` resolve it with `@onready var nav_agent =
  $NavAgent`; a scene sharing one of those scripts without the node crashes
  on spawn. Two unit scenes share `unit.gd` — both need it, and so will any
  future sibling archetype scene.
- **Never set `NavigationAgent2D.target_position` every frame.** Each
  assignment triggers a new path query. `_nav_direction_to()` only re-sends
  it when the goal moved more than 16 px (`NAV_REPATH_DIST_SQ`); a chase of a
  moving target would otherwise repath every physics frame per agent.
- **`has_navigation()` is false on the first physics frame after a map
  loads** (`NavigationServer2D.map_get_iteration_id() == 0` until the server
  syncs). Anything querying the navmesh during spawn must tolerate the
  fallback (direct steering / unsnapped point) rather than assume a path
  exists.
---
 
## 7. Networking posture (design-time only)
 
No transport exists. The prepared seams:
 
- Spawn messages will be `{card_id/hero_id, position, team}` — the receiving side
  calls the same `spawn_unit`/`spawn_hero` that local play uses.
- Card database version must match between clients (balance patches → DB version
  check at matchmaking).
- Server-owned state candidates already isolated in BattleManager: match timer,
  death counters, respawn timing, structure status, match result. `EnergySystem`
  is the second such module: a server would run its regen, modifier, and
  `try_spend(card_id)` logic verbatim (spend validation is the first thing a cheat
  client fakes), which is why it carries no scene or UI dependency.
  `HealingSystem` is the third: pod cooldown state and per-team HoT state are
  both pure data with no scene or UI dependency, so a server would run
  `trigger_heal()` / `consume_pod()` / `cancel_heal()` verbatim, same as
  EnergySystem's spend path.
- Authority model (dedicated server vs. relay/P2P) is an open decision with real
  cost implications — treat as its own project phase.
- `HeroAI` is the fourth such module: per-team hp-threshold hysteresis is
  pure data (a bool + two constants), so a server would run
  `get_hp_state()` verbatim. The *decision* of what to do about a LOW_HP
  state (which structure, which pod, which spawn point) stays in the hero
  script/controller layer, not in `HeroAI` — keeping the autoload itself
  trivially portable regardless of how targeting logic evolves.
- Spell casts fit the existing spawn-message shape: `{card_id, position, team}`
  → the receiving side calls the same `cast_spell()` local play uses. Unlike
  `EnergySystem`/`HealingSystem`/`HeroAI`, the spell layer is **not** a
  scene-free pure-state module — `SpellZone` is a scene node and applies
  effects to live nodes directly. `get_targets_in_radius()` is the clean
  seam: a server-authoritative version would run the zone's tick schedule
  and that query, and send resulting damage/status to clients rather than
  letting each client resolve its own. The cast delay is also a genuine
  gameplay window (not just a visual), so it must be server-timed, not
  client-timed, once authority exists.
- Map selection will need the same treatment: `MatchConfig.map_id` is
  currently a client-local TEMP random pick (§2/§3) with no server
  involved — real matchmaking will need to agree on a map id before either
  client instantiates `MapDB.get_map(id).map_scene`, the same way card
  database version needs to match today.
- **Movement commands carry goals, never paths.** A tap-to-move message will
  be `{target_position}` (already navmesh-snapped by the sender or re-snapped
  by the receiver); each simulation computes its own path from the map's
  baked navmesh. That makes the navmesh bake part of the map "version" both
  sides must agree on, the same as the card database. Under a
  server-authoritative model the server runs the agents and clients only
  render positions.

---

## 8. Main menu / UI shell

`scenes/menu/MainMenu.tscn` (`scripts/ui/main_menu.gd`) — the hub screen
reached on launch and returned to after a match. Pure UI chrome, no match
state — everything here is display/navigation only. Node structure, all
under `Background` (a full-screen `Panel`, the last declared child of the
menu root so it draws over the overlay instances declared above it, see the
draw-order pitfall in §6):

- `NavRail` (`VBoxContainer`, left edge, anchored full-height) —
  `DeckButton`/`HeroesButton`/`ShopButton`/`RewardsButton` (plain `Button`s,
  each with its own flat-color `StyleBoxFlat` override on `styles/normal`
  only — the theme's default hover/pressed styles still apply, no art
  assets exist for these yet), a `Control` spacer (`size_flags_vertical =
  3`), then `ExitButton` (`TextureButton`). All placeholder buttons route to
  `_show_coming_soon(feature_name)` (below).
- `TopBar` (`HBoxContainer`, top edge) — `CurrencyGroup` (a `ColorRect` +
  static `"0"` `Label`, placeholder), `MailButton`/`GiftButton` (same
  flat-color placeholder pattern as the nav rail), `SettingsButton`
  (`TextureButton`, opens `SettingOverlay`).
- `MainContent` (`HBoxContainer`, fills the space between the nav rail and
  the screen edge) — `HeroShowcase` (`Control`, `size_flags_horizontal = 3`
  to take remaining width) containing a single `AnimatedSprite2D` child
  (`ZeusIdle`) that plays a hero's existing `SpriteFrames` idle animation
  directly (currently `frames_zeus.tres`'s `"iddle_left"`, `autoplay =
  true`) — reuses match art as-is, no separate menu-only asset; and
  `BattleCard` (`Button`, `custom_minimum_size` fixed, `size_flags_vertical
  = 4` to center within the row), the sole entry point into
  `PreMatchFlow.tscn` (§4).
- `ComingSoonToast` (`PanelContainer`, hidden by default) — generic "<X> —
  coming soon" toast for any unimplemented nav-rail/top-bar button, shown
  via `main_menu.gd::_show_coming_soon(feature_name: String)`. Debounced
  with a `_toast_token: int` counter: each call increments the token and
  only the matching deferred hide (`get_tree().create_timer(...).timeout`)
  actually hides the toast, so rapid taps across different placeholder
  buttons extend the visible window instead of an earlier timer hiding it
  mid-read. Reusable pattern for any future auto-hiding transient UI.
- `FooterBar` (`HBoxContainer`, bottom edge) — title, `•`, `VersionLabel`
  (reads `ProjectSettings.get_setting("application/config/version", ...)`
  at `_ready()`, backed by a real `config/version` project setting — never
  hardcoded in two places), `•`, `ServerStatusLabel` (static placeholder
  text, no real server/backend yet).
- `SettingOverlay` / `CreditsOverlay` — fullscreen overlay scene instances,
  siblings of `Background` but declared *before* it in the tree (see the
  draw-order pitfall in §6). Both start `visible = false`; `main_menu.gd`
  calls `move_to_front()` on whichever one it opens, so it draws above
  `Background` without a permanent scene reorder. Opening either one hides
  `NavRail` and `MainContent` (`nav_rail.visible` / `main_content.visible`
  toggled together) so nothing behind the overlay is reachable while it's
  open, on top of the draw-order fix. `SettingOverlay` hosts a
  `CreditsButton` in its own content list (`SettingsContent`, alongside
  the audio slider and lock-camera toggle) that closes Settings and emits
  a `credits_requested` signal, which `main_menu.gd` answers by opening
  `CreditsOverlay` — Credits is reachable through Settings, not its own
  nav-rail entry, so the two fullscreen overlays are never open at once.

Two general Control-layout pitfalls surfaced building this screen — the
draw-order one and the `Node2D`-in-a-`Control` centering one — are filed in
§6 rather than duplicated here, since both are reusable lessons beyond the
main menu specifically.
