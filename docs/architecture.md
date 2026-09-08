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
| `BattleManager` | Match state owner: team registries, structures, spawn entry points, hero respawn, match timer, `match_ended`. |
| `CardDB` | Startup scan of `data/cards/`, `data/units/`, `data/heroes/` into id-keyed dictionaries. Handles `.tres.remap` suffixes in Android exports. Duplicate-id guard. |
| `EnergySystem` | Per-team energy: float pools, base regen, and a modifier list (temporary regen multipliers / cost reductions). **Zero scene/UI dependencies by design** — pure state+math so it ports to an authoritative server as-is; its only dependency is `CardDB` (cost lookup). Driven by the caller (`arena.gd` today): `reset_match_state()` / `start()` / `stop()`. Emits `energy_int_changed`. |
| `HealingSystem` | Per-team pod cooldowns + active heal-over-time state. **Zero scene/UI dependencies by design**, same contract as `EnergySystem` — no scene/node/Area2D/Sprite2D references, pure state+math so it ports to an authoritative server as-is. Third autoload with its own `reset_match_state()` (same pattern as `EnergySystem`). Death safeguard lives in the hero scripts: `die()` calls `HealingSystem.cancel_heal(team)`, which clears the active HoT and emits `heal_ended` — the same signal path a normally-completed heal uses to clear the health bar's pending band. Emits `pod_ready`, `heal_instant`, `heal_tick`, `heal_started`, `heal_ended`. |
| `MatchConfig` | Placeholder holder for pre-match display data (rank, map, both players' name/faction). Populated by `setup_placeholder_match()` today; matchmaking later. Display-only, never networked. |
| `InputR` | Input routing (tap-to-move targets, gesture state). |
| `Settings` | Persistent user settings. |
| `Music` | Audio. |
| `HeroAI` | Per-team HP-threshold hysteresis for the AI-controlled hero (`NORMAL` / `LOW_HP`, 20%→50% band). **Zero scene/UI dependencies by design** — pure state+math, same contract as `EnergySystem`/`HealingSystem`. Doesn't know about pods, positions, or targets — that decision-making lives in `hero_dummy.gd`. Own `reset_match_state()`. |

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
                           speed, target_filter, sprite_frames
    frames/ SpriteFrames — extracted animation sets, swappable per unit
  heroes/   HeroData     — id, stats, projectile_scene, sprite_frames
                           (no archetype_scene: control mode picks the scene)
  spells/   SpellData    — id, display_name, spell_type (int: 0=STORM,
                           1=STUN, 2=NET), radius, cast_time,
                           zone_duration, effect_duration, damage,
                           tick_interval, slow_multiplier, sprite_frames
                           (animation names are a contract: "drag", "cast")
  maps/     MapData      — id, display_name, bounds (Rect2), camera_edge_margin,
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
structure per map (no shared formula; see `arena.tscn`'s per-node values).
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

`MapData` is deliberately **excluded** from the `CardDB` scan/lookup pattern
the other four resource types share — it isn't looked up by id at runtime the
way a played card is. `arena.gd` holds its map's `MapData` directly as an
`@export` on the scene root and passes it once, at `_ready()`, to whichever
systems need per-map values: `BattleManager.configure_map(map_data)` (sets the
mutable `deploy_bounds`) and `arena_camera.configure_map(map_data)` (sets
`bounds_min`/`bounds_max`/`edge_margin`/`edge_pan_speed_max`). This is what
unifies the two previously-independent hardcoded bounds systems (§6) into one
per-map resource; adding a new map is authoring a new `.tres` and pointing a
new arena scene's `map_data` export at it, no script changes. Structures
(turrets/bases) are **not** part of `MapData` — their positions and
`protection_zone` rects live on the structure nodes themselves in each map's
`.tscn`, hand-tuned per map (see the protection-zone paragraph above and
`game_design.md` §3.7).
---
 
## 4. Battle scene structure
 
- `scenes/arena/arena.tscn` — battlefield root; two horizontal lanes; per team:
  Base + 3 turrets (Top, Bot, Base). Structures self-register with BattleManager
  (combat registries **and** their `protection_zone` Rect2, §3); destroyed
  structures become wrecks (**no `queue_free()`**), which also unregisters
  their protection zone, permanently opening that slice of the map
  (`game_design.md` §3.7).
- `scenes/arena/units/melee_unit.tscn` — the one melee archetype
  (CharacterBody2D + Hurtbox + AttackRange + AggroRange + AnimatedSprite2D +
  HealthBar + TargetMarker). Ranged/siege archetypes will be siblings.
- `scenes/arena/player.tscn` — locally-controlled hero.
- `scenes/arena/hero_dummy.tscn` (`hero_dummy.gd`) — AI-controlled enemy hero
  avatar. Movement/targeting/combat logic ported from `player.gd` (same
  fields, `find_nearest_enemy()`/`_try_fire()`/`fire_bolt()`, same
  animation helpers), driven instead by `HeroAI`'s hp-state output:
  `NORMAL` → march toward nearest enemy structure (`BattleManager.
  get_nearest_structure()`, interval-refreshed same as `unit.gd`); `LOW_HP`
  → seek nearest ready healing pod (`BattleManager.
  get_nearest_ready_healing_pod()`), falling back to retreat toward own
  spawn if no pod anywhere is ready. Walking onto a pod triggers the heal
  automatically via the pod's existing `area_entered` handler — no
  explicit "use pod" call from the AI. Card-play AI is not yet implemented
  (separate future step). Now also wires `target_marker` (see §6).
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
  is sensor + visual only. 4 static placements in `arena.tscn`, one per lane
  per side (`HealingPodPlayerTop/Bot`, `HealingPodEnemyTop/Bot`).
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
  `change_scene_to_file(arena.tscn)`. Reached from the main-menu Arena button.
  Faction/avatar are ColorRect placeholders pending assets.
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
  not per frame. Separation steering with cached interval updates.
- Hero: manual primary target (tap) with chase, auto-target fallback without chase,
  projectile attack.
- Hero death: hide + disable (collision & hurtbox zeroed deferred → attackers get
  `area_exited` and disengage), unregister, respawn via BattleManager countdown.
- Range checks use `distance_squared_to()`.
- **Deploy zone:** `BattleManager.is_deploy_position_valid(pos, team)` is the single
  source of truth — the live drag preview (circle colour) and the spawn on release
  both call it, so they cannot disagree. Today: inside `DEPLOY_BOUNDS` and on the
  team's own half (midline `x = 0`). It is **positional only** (takes no `card_id`);
  energy affordability is a *separate* check and is deliberately NOT folded in here,
  so the red circle never conflates "bad spot" with "can't afford". Future zone
  rules (expansion on turret kill, obstacles) go inside this function.
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
  the velocity magnitude.
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
  the `Camera2D` node in any given map's `.tscn` (easy to inherit by
  duplicating a scene, since it's a separate Inspector section from the
  script's own exported vars).
- **Resolved:** the two independently-hardcoded bounds systems referenced
  above (native `Camera2D` limits vs. the script's own `bounds_min`/
  `bounds_max`) are now both driven from one place — `MapData.bounds`,
  applied via `arena_camera.configure_map(map_data)` — and
  `BattleManager.deploy_bounds` (formerly a `const DEPLOY_BOUNDS`, now
  mutable) is set from the same resource via
  `BattleManager.configure_map(map_data)`, both called once from
  `arena.gd._ready()`. One `MapData.tres` per map now fully describes bounds,
  camera pan tuning, and hero spawn points (§3).
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
  `apply_root`/`apply_slow` are byte-identical in three files. Resist the
  refactor into a shared parent or component: the three scripts have
  genuinely different movement pipelines (`unit.gd` steers with separation,
  `player.gd` blends tap-to-move with chase, `hero_dummy.gd` is
  single-target steering) and the *insertion points* differ even though the
  timers don't. A shared class would force those pipelines to converge.
- **A stunned unit's `attack_left` also stops ticking.** The stun early-return
  sits *above* the cooldown decrement in `_physics_process`, so a unit
  stunned mid-cooldown resumes with the same cooldown remaining rather than
  attacking instantly on recovery. Intentional; don't "fix" it by moving the
  decrement above the stun check.
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