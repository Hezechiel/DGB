# Battle scene structure — DGB architecture

> Part of docs/architecture.md — see the index there.

## Battle scene structure

- `scenes/arena/arena.tscn` — the generic match shell, not map content:
  HUD, `MatchResultBanner`, `ArenaCamera`, `MoveMarker`, `DenialZoneOverlay`,
  `DeployGhost`, and an empty `MapRoot` mount node. Also owns the
  base-destroyed **end sequence** (`audio.md` "End-of-match sequence"). Resolves and instantiates its map at
  runtime (`data_layer.md`) — holds no lanes, structures, or terrain of its own.
  `_unhandled_input` tap-to-move snaps the tapped world position onto the
  navmesh (`BattleManager.snap_to_navigation()`) before handing it to
  `InputR.set_move_target()` and `MoveMarker.show_at()`, so the marker
  always shows the point the hero will actually reach (`combat_movement.md` Navigation).
- `scenes/arena/maps/<Name>Map.tscn` (e.g. `GreekPlateauMap.tscn`,
  `NordPlainsMap.tscn`) — one per map, instantiated into `arena.tscn`'s
  `MapRoot` at runtime. Holds that map's two horizontal lanes; per team:
  Base + 3 turrets (Top, Bot, Base). Structures self-register with
  BattleManager (combat registries **and** their `protection_zone` Rect2,
  `data_layer.md`); destroyed structures become wrecks (**no `queue_free()`**), which
  also unregisters their protection zone, permanently opening that slice
  of the map (`game_design.md` §3.7). See `map_authoring_guide.md` for the
  full checklist to add a new one.
  **Tile-built structure (`GreekPlateauMap.tscn`; `NordPlainsMap.tscn`
  mid-migration — see the note in `data_layer.md` and `map_authoring_guide.md` §0):**
  ground is a `Terrain/TileMapLayer` (no background `Sprite2D`), obstacles
  split into a visual `Obstacles/TileMapLayer` plus collision-only
  `Patches/*` instances (`LargePatch.tscn`/`SmallPatch.tscn`, both
  inheriting a script-free base scene, `ObstaclePatch.tscn` —
  `StaticBody2D`, `collision_layer=4`/`collision_mask=0`, one
  `CollisionPolygon2D` in `Solids` build mode seeded with a small
  placeholder square so it's never an invalid empty polygon), a
  `MapBorder` node (`scenes/arena/maps/MapBorder.tscn` /
  `scripts/arena/map_border.gd`) giving the map an actual outer physical
  boundary, and one `NavigationRegion2D` (`combat_movement.md` Navigation). `Patches`,
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
  (`UnitData.attack_type`), not a script fork — see `combat_movement.md` and
  `unit_authoring_guide.md`. Siege archetypes, if they diverge in movement/
  targeting rather than just attack resolution, would be a genuine new
  sibling script; a third *attack type* would not. **Both scenes must carry
  the `NavAgent` child** — `unit.gd` resolves it with `@onready`, so a scene
  missing it crashes on spawn (`conventions_pitfalls.md`). `ranged_unit.tscn`'s root node is still
  named `MeleeUnit` (duplication leftover, harmless, rename when convenient).
- `scenes/arena/player.tscn` — locally-controlled hero. Carries a `NavAgent`
  (`NavigationAgent2D`) child (`combat_movement.md` Navigation).
- `scenes/arena/hero_dummy.tscn` (`hero_dummy.gd`) — AI-controlled enemy hero
  avatar. Movement/targeting/combat logic ported from `player.gd` (same
  fields, `find_nearest_enemy()`/`_try_fire()`/`fire_bolt()`, same
  animation helpers), driven instead by `HeroAI`'s hp-state output:
  `NORMAL` → march toward nearest enemy structure (`BattleManager.
  get_nearest_structure()`, interval-refreshed same as `unit.gd`); `LOW_HP`
  → seek nearest ready healing pod (`BattleManager.
  get_nearest_ready_healing_pod()`), falling back to retreat toward own
  spawn if no pod anywhere is ready (retreat point snapped onto the navmesh,
  `combat_movement.md`). Walking onto a pod triggers the heal automatically via the pod's
  existing `area_entered` handler — no explicit "use pod" call from the AI.
  All three destinations go through the single `_steer_towards()`, which
  follows the navmesh via its own `NavAgent` child. Card-play AI lives in
  `enemy_card_ai.gd`. Now also wires `target_marker` (see `conventions_pitfalls.md`).
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
- `scenes/arena/ui/SynergyIcon.tscn` (`synergy_icon.gd`, `class_name
  SynergyIcon`) — a `Button` in the HUD beside the energy bar, left of the
  hand. Shows the player's synergy count; grey when the deck threshold is not
  met, gold and pulsing when it is; a tap toggles a tooltip (auto-hides) with
  the `DeckRules.describe_synergy()` text. Being a `Button`, it consumes the
  tap so it never reaches tap-to-move. Configured once by
  `arena.gd` (`hud.synergy_icon.configure("player")`) after the manifests are
  set — the state cannot change during a match. Placeholder look, no art.
- `scenes/arena/ui/SkillButton.tscn` (`skill_button.gd`, `class_name
  SkillButton`, Oct 2026) — the local god's skill button: a round placeholder
  `Button` above the energy bar (bottom-right, clear of `CardHand`). Grey with
  the remaining seconds while on cooldown, gold with the skill name when
  ready, disabled while the god is dead, hidden when the god has no skill or
  `SkillEffects.is_implemented()` is false. `configure(hero)` is called once by
  `arena.gd` right after `spawn_hero(... "player" ...)`; `_process()` polls
  `hero.get_skill_cooldown_left()`; `pressed` → `hero.try_cast_skill()`.
  `process_mode = PAUSABLE` (`conventions_pitfalls.md` HUD child pitfall). A `Button`, so the tap
  never reaches tap-to-move.
- Skill FX — `ChainLightningFx` / `TidalWaveFx`
  (`scripts/arena/skills/chain_lightning_fx.gd`, `tidal_wave_fx.gd`) —
  code-built `Node2D`s added under `BattleManager.arena_root`, drawn in
  `_draw()` (zigzag polyline / translucent cone), `z_index = 50`, fade out in
  ~0.25–0.35 s and `queue_free()`. Placeholder visuals; scene-owned, so no
  reset code.
- `scenes/hud/HUD.tscn` (CanvasLayer) — TouchScreenButtons (pause, recenter),
  `CardHand` (hand + draw cycle in `card_hand.gd`; `play_card(slot_index, world_pos)`
  is the single card-play entry point — drag-to-deploy calls it today, future
  double-tap and the network handler call the same function — which now also
  spends energy via `EnergySystem.try_spend()` and refuses unaffordable plays; emits
  `deploy_preview_started` (once, at drag start, carrying the `CardData`) /
  `deploy_preview_updated` / `deploy_preview_ended` for `arena.gd` to drive the
  DeployGhost), `EnergyBar`, `SynergyIcon`, `Minimap`, `MatchInfoBar` (timer label,
  tower icons, two `RespawnCounter`s driven by BattleManager signals). The hand's
  deck comes from `MatchConfig` (`data_layer.md`), not from `CardHand.tscn`. The HUD also
  instances `SettingOverlay` as the pause screen (`menu_ui.md` "Framed overlays").
  `play_card()` branches on card type: `unit_data` → `BattleManager.spawn_unit()`,
  `spell_data` → `BattleManager.cast_spell()`. Both the live drag preview and
  the release check call `BattleManager.is_card_target_valid(card, pos, team)`.
- `scenes/ui/PreMatchFlow.tscn` (`prematch_flow.gd`) — placeholder pre-match
  flow: a "searching for battle" panel then a versus panel, each ~1s, then
  `change_scene_to_file(arena.tscn)`. Reached from the main-menu Battle card
  (`menu_ui.md`). Also resolves this match's map: calls `MapDB.get_random_map_id()` into
  `MatchConfig.map_id` once, and shows the resolved `MapData.display_name`
  on the finding screen (`data_layer.md`). Faction/avatar are ColorRect placeholders
  pending assets.
- `scenes/arena/audio/AmbientEmitter.tscn` (`ambient_emitter.gd`,
  `class_name AmbientEmitter`) — map ambient sound, hand-placed in each map
  scene under an `Ambient` `Node2D` (same authoring style as turrets/pods).
  `LOOP` mode = bed on its own `AudioStreamPlayer` (fade-in, never through
  the SFX pool); `RANDOM` mode = one-shot via `AudioManager.play_sfx()` every
  `min_interval`–`max_interval` s after a random `first_delay`. Lives with
  the map scene, so match end / scene change clean it up — no reset code
  (`audio.md`, `map_authoring_guide.md` §2.11).
- `MatchAnnouncer` (`scripts/arena/match_announcer.gd`, plain `Node`,
  added by `arena.gd::_ready()` via `add_child(MatchAnnouncer.new())`, same
  as `EnemyCardAI`) — self-subscribes to `BattleManager.hero_died` and calls
  `AudioManager.play_announcer()`; today only "first blood" (first hero
  death of the match, either side). Per-match state lives on the node and
  resets with the arena. `arena.gd::_exit_tree()` calls
  `AudioManager.stop_announcer()` so no line or music duck leaks into the menu.
- `scenes/arena/ui/MatchResultBanner.tscn` (`match_result_banner.gd`,
  `class_name MatchResultBanner`) — the VICTORY/DEFEAT banner of the end
  sequence. Its own `CanvasLayer` (`layer = 20`), a sibling of `HUD` in
  `arena.tscn` — **not** inside the HUD, because the HUD is hidden for the
  whole sequence. Nodes: `Band` (dark full-width strip), `Band/Title`,
  `Band/Subtitle`, `Fade` (full-screen black for the final fade). Everything
  is `mouse_filter = IGNORE`. One entry point, `show_result(winner,
  total_duration)`, called by `arena.gd`; it knows nothing about
  `BattleManager` and connects no signals. Code/fonts only, no textures —
  node names are kept stable so art can be swapped in without script changes.
  Its title style (CinzelDecorative-Black, gold, black outline) is also the
  title style of the framed menu screens (`menu_ui.md`).

### Key BattleManager signals

`match_ended(winner)`, `match_time_tick(seconds_left)`,
`hero_died(team, respawn_seconds)`, `hero_respawn_tick(team, seconds_left)`,
`hero_respawned(team)`.

---

## Moved from CLAUDE.md (Oct 2026)

Facts from the old CLAUDE.md catalogue and its "Architecture — Direction"
section that the sections above did not already cover.

### MOBA match structure (from CLAUDE.md)

`arena.tscn`'s actual direct children today (map-agnostic shell — no map content is a static child of this scene anymore):

```
Arena (Node2D, arena.gd)
├── MapRoot              (empty Node2D — the active map's scene is instantiated here at runtime)
├── DesaturateRect        (ColorRect, death-telegraph shader overlay)
├── MoveMarker
├── DenialZoneOverlay
├── DeployGhost
├── ArenaCamera           (Camera2D)
├── HUD                   (CanvasLayer)
└── MatchResultBanner     (CanvasLayer, end-of-match VICTORY/DEFEAT banner)
```

Map-specific content (tilemap, obstacles, Command Posts, turrets, healing pods) lives inside the per-map scene that gets instantiated into `MapRoot` — not hardcoded into `arena.tscn`. Units and heroes are spawned at runtime directly under `Arena` by `BattleManager`, not placed as static scene nodes either. This replaces the previous plan of a single fixed map baked directly into `arena.tscn` with `TileMapLayer`/`Obstacles`/`TopLane`/`BotLane`/`PlayerBase`/`EnemyBase`/per-lane turrets/`UnitContainer` as direct children — that structure no longer exists.

### Arena root (from CLAUDE.md)

`scenes/arena/arena.tscn` / `scripts/arena/arena.gd`
- Free-drag camera panning is handled by `ArenaCamera` itself, not by `arena.gd`
- Connects `HUD.exit_requested` → MainMenu, `HUD.recenter_camera_requested` → `arena_camera.recenter_on_player()`, `BattleManager.match_ended` → `_on_match_ended()`
- `_ready()` order: load the active map via `MapDB`/`MapData` into `MapRoot` → `BattleManager.set_team_manifest()` for both teams from `MatchConfig` → synergy `energy_regen` modifiers → `hud.synergy_icon.configure("player")` → spawn both heroes via `BattleManager.spawn_hero(MatchConfig.local_hero_id / opponent_hero_id, ...)` (no hardcoded hero constants) → `hud.skill_button.configure(player_hero)` → `hud.minimap.configure_map()` → `EnemyCardAI` + `MatchAnnouncer` → `BattleManager.start_match_timer()`
- Opening `arena.tscn` directly with F6 leaves `MatchConfig` empty (known limitation — null-guarded, not a crash)

### Lane system (from CLAUDE.md)

Not yet implemented. `BattleManager.get_nearest_structure(defending_team, from_pos) -> Node2D` returns the nearest *alive* turret or base belonging to the defending team, with zero lane-priority logic (turrets are still bucketed by `"top"`/`"bot"` internally for lane-clear/vulnerability bookkeeping, but the nearest-structure query itself ignores that entirely). Both `unit.gd` (`_update_structure_target()`) and `hero_dummy.gd` refresh this target periodically and steer straight at it — there is no fixed waypoint path anywhere in the codebase. This is intentional: units can now be deployed anywhere on the map via drag-to-deploy, so a fixed lane path wouldn't make sense until deploy zones are lane-constrained again (if ever).

### Spawn protection zones (from CLAUDE.md)

Implemented, but not via Area2D/CircleShape2D. Each turret and base exports a `protection_zone: Rect2` (`scripts/arena/turret.gd`, `scripts/arena/base.gd`), registered into `BattleManager._protection_zones: Dictionary` (`team -> Array[Rect2]`) on `_ready()` via `register_protection_zone()`, and unregistered on `_on_destroyed()`. `BattleManager.is_deploy_position_valid(pos, team) -> bool` checks the map's `deploy_bounds` and then rejects any point inside an *enemy*-team zone rect; `is_card_target_valid(card, pos, team)` wraps it and lets spell cards skip the zone check entirely (bounds-only, since spells are playable anywhere on the map). Zones are large per-lane/flank rectangles covering roughly a structure's defended area (e.g. `Rect2(-460, -305, 50, 610)` for a base), not small radii around the structure itself — as turrets fall, the protected frontier shrinks, and "own half" is now purely an emergent effect of how a given map's zone rectangles happen to be laid out, not a separate hardcoded center-line rule. New maps only need different structure placement/zone rects; this function itself never changes per-map.

### BattleManager (from CLAUDE.md)

- `register(unit, team)` — adds to `team_player`/`team_enemy`, connects `tree_exited` for cleanup
- `is_team_alive(team)` — foundation for win/lose
- Win/lose state: `last_winner`, 180s match timer
- Deploy: `configure_map(map_data)` sets `deploy_bounds`

### Respawn system (from CLAUDE.md)

Implemented in `BattleManager.gd`: `on_hero_died(hero, team)` starts the respawn countdown (`_respawn_left: Dictionary`, team → seconds left); `_process()` ticks it down and calls `_respawn_hero(team)` (teleports hero to `hero_spawn_positions[team]`, calls `hero.revive()`) when it hits 0. Respawn duration: `clampi(3 + death_count - 1, 3, 10)` seconds (`death_count` persists for the whole match, never resets). `is_hero_dead(team: String) -> bool` is the single source of truth for "is this team's hero currently dead" (`_respawn_left.has(team)`); any system that needs to know should call this rather than tracking its own copy. `hero_died`/`hero_respawn_tick`/`hero_respawned` are the shared broadcast. Three independent consumers react to these signals today: `match_info_bar.gd`'s small `RespawnCounter`, the card-play lock (`card_hand.gd` / `enemy_card_ai.gd`), and the full-screen death telegraph (`desaturate_overlay.gd` + `death_telegraph.gd`). Adding a fourth reaction to hero death should follow the same pattern — self-subscribe in `_ready()`, don't route through an existing consumer.

### Hero death gating & telegraph (from CLAUDE.md)

- Card plays are locked while `BattleManager.is_hero_dead(team)` is true: `CardHand._refresh_affordability()` force-greys all 3 hand slots regardless of energy, `CardHand.play_card()` gates the same way (covers double-tap/future network calls that bypass the drag UI), and `EnemyCardAI._process()` skips its decision tick entirely — `EnergySystem` regen keeps running unaffected the whole time
- `scripts/arena/desaturate_overlay.gd` (`ColorRect`, direct child of `Arena` root in `arena.tscn`, **not** in a `CanvasLayer`) — desaturates the battlefield to greyscale while the player hero is dead via a `canvas_item` shader (`scenes/arena/ui/shaders/desaturate.gdshader`) reading `SCREEN_TEXTURE`; tracks its own `_desaturation: float` and tweens it via `create_tween().tween_method()` on `hero_died`/`hero_respawned`. Deliberately lives in the same canvas as the map/units/heroes (not HUD's `CanvasLayer`) with `z_index = 100` so it always paints after everything else, including units added later via `BattleManager.arena_root.add_child()`
- `scripts/arena/ui/death_telegraph.gd` (`scenes/arena/ui/DeathTelegraph.tscn`, instanced in `scenes/hud/HUD.tscn` at `layer = 5`, between the world and HUD's `layer = 10`) — shows/hides a top-center "GOD DEAD" + countdown label (red/white, transparent background) on the same three signals; purely cosmetic, HUD-scoped, no shader involved
- `scripts/arena/ui/match_info_bar.gd` — the small `PlayerRespawnCounter`/`EnemyRespawnCounter` in the top bar are a third, independent consumer of the same three signals

### Win / lose (from CLAUDE.md)

`scenes/menu/MatchEndScreen.tscn` / `scripts/ui/match_end_screen.gd`
- `BattleManager` emits `match_ended(winner_team: String)` from `on_base_destroyed()` (a Command Post reaches 0 HP) or when its 180s match timer expires (`"draw"` — marked TODO to become a progress-based tiebreak later)
- `MatchEndScreen` reads `BattleManager.last_winner` in its own `_ready()` (not the signal argument, since it's a fresh scene) and offers a button back to `MainMenu.tscn`

### EnergySystem (from CLAUDE.md)

`scripts/EnergySystem.gd` — always called "energy," never "mana," in code, comments and docs.
- `MAX_ENERGY = 10.0`, `START_ENERGY = 7.0`, `BASE_REGEN_PER_SEC = 0.25` (1 energy / 4s)
- Modifier layer: `add_modifier(team, type: ModType, value, duration, tag)` / `remove_modifier(team, tag)` / `has_modifier(team, tag)`. `ModType.REGEN_MULT` modifiers multiply and stack (e.g. a temporary regen boost); `ModType.COST_REDUCE` modifiers sum and stack, clamped so resolved cost never drops below 0 (e.g. a temporary "bloodlust" cost reduction). `duration = INFINITE_DURATION (-1.0)` marks a modifier that only ends via explicit `remove_modifier()` (or `reset_match_state()`). The synergy `energy_regen` bonus is exactly this: `arena.gd::_ready()` adds an infinite `REGEN_MULT` tagged `&"synergy"` per team when the bonus isn't 1.0
- Atomic spend: `try_spend(team, card_id) -> bool` — checks `can_afford()` then deducts in one call; callers must never decrement energy themselves. Also exposes `can_afford()`, `resolve_cost()`, `add_energy()`, `drain_energy()`, `start()`/`stop()`/`is_running()`

### HealingSystem (from CLAUDE.md)

- Static map pickups usable by **heroes of both teams** — no team lock, and units can never use them (SWFA-style design)
- `HealingSystem.trigger_heal(team, instant_amount, hot_total, hot_duration)` — fires an instant heal plus a heal-over-time that ticks independently in `_process()`; HoT is cancelled on death rather than continuing through a respawn
- Per-pod cooldown lifecycle: `register_pod(pod_id, initial_delay, respawn_cooldown)`, `consume_pod(pod_id)` (resets to cooldown), `pod_ready` signal when a pod becomes available again
- Pod exports (`healing_pod.gd`): `initial_delay`, `respawn_cooldown`, `instant_heal_amount`, `hot_total_amount`, `hot_duration`, and a `single_use` flag reserved for a future portable/summoned pod (`BattleManager.spawn_healing_pod()` exists today only as a documented no-op stub)

### ArenaCamera (from CLAUDE.md)

`scripts/arena/arena_camera.gd` (`Camera2D`, standalone node in `arena.tscn`, not a child of Player)
- Drag-to-pan via `_unhandled_input` (8px drag threshold), clamped every frame to `bounds_min`/`bounds_max` — populated per-map by `configure_map(map_data: MapData)`
- Optional follow mode (`Settings.lock_camera`): lerps toward the player using `follow_smoothing`; a manual drag pauses follow for a grace period (`return_delay`) before ramping back (`return_ramp_time`)
- Screen-edge pan during card drag-to-deploy overrides follow mode while a card drag is active, so the player can always reach any map position while deploying
- `recenter_on_player(duration := 0.4)` tweens back to the player (`EASE_OUT`/`TRANS_QUART`), wired to HUD's `PlayerCharacter` button
- **No zoom** — the camera is fixed-zoom; there is no pinch/scroll handling anywhere in this script

### Card hand & drag-to-deploy (from CLAUDE.md)

`scenes/arena/ui/CardHand.tscn` / `scripts/arena/ui/card_hand.gd` + `scripts/arena/ui/card.gd`
- 3 playable slots (`Card1`/`Card2`/`Card3`, each wrapped in its own `AspectRatioContainer`) plus a `NextCardPreview` slot — not 4 playable slots
- The deck is the player's active 7-card deck from `MatchConfig.local_deck_card_ids`. Shuffled into a cyclic queue at `_ready()`; a short/empty deck (e.g. F6) leaves slots empty rather than crashing. Clash-Royale style refill — a played card goes to the back of the queue, the vacated slot is refilled from the front, `NextCardPreview` always mirrors the queue's front
- `CardHand._input()` converts screen→world, flips the card to its back while dragged outside the hand's rect, and emits `deploy_preview_updated(world_pos, is_valid, screen_pos)` every frame
- On release (`_finish_drag`): releasing over the hand cancels; releasing over an invalid map position cancels (card stays in the slot); only a valid map position calls `play_card()`, which re-checks `is_hero_dead()`, atomically spends via `EnergySystem.try_spend()`, then spawns/casts
- Card affordability greying (`set_affordable()`) refreshes on every energy change and after every play

### EnemyCardAI (from CLAUDE.md)

`scripts/arena/enemy_card_ai.gd` (plain `Node`, instantiated directly in `arena.gd::_ready()`, not an autoload or a `.tscn`)
- Ticks every `decision_interval` (1.75s default) in `_process()`, gated on `EnergySystem.is_running()` and the enemy hero being alive
- Mirrors `CardHand`'s 3-slot mechanic (no preview slot); its deck comes from `MatchConfig.opponent_deck_card_ids`. Today `PreMatchFlow` fills it with a copy of the player's deck (and mirrors the player's levels), with Poseidon as a temporary hardcoded opponent god
- Each tick, plays *every* slot that is simultaneously affordable and has a resolvable, valid position (not just one card per tick): checks `EnergySystem.can_afford()`, resolves a jittered deploy position (`_resolve_play_position()` — unit cards jitter around its own hero, spell cards jitter around the nearest player-owned structure via `get_nearest_structure()` and are skipped if none is found), validates through the same `BattleManager.is_card_target_valid()` the human player uses, then atomically spends via `try_spend()`
- Deliberately a separate, minimal-policy script rather than sharing code with `card_hand.gd` — no scoring/utility AI. Replacing it with a network player later requires only swapping the input source; the validation/spend/spawn calls it goes through are already identical to the human path

### HUD (from CLAUDE.md)

`scenes/hud/HUD.tscn` / `scripts/hud/HUD.gd`
- `Root` (`Control`) holds `PauseButton` (TextureButton) and `PlayerCharacter` (TextureButton — despite the name, this is the recenter-camera button, wired to `HUD.recenter_camera_requested` → `arena.gd` → `arena_camera.recenter_on_player()`, hidden while `Settings.lock_camera` is on); direct siblings of `Root`: `CardHand`, `EnergyBar`, `SynergyIcon`, `Minimap`, `MatchInfoBar`, `DeathTelegraph`, `SettingOverlay` (initially hidden)
- `Minimap` (`scenes/arena/ui/Minimap.tscn` / `scripts/arena/ui/minimap.gd`) — top-left panel sized from `MapData.bounds` aspect ratio in `configure_map(map_data)` (called by `arena.gd` after hero spawn); structures and heroes as team-coloured dots, full visibility (no fog of war). Tap-to-navigate is not built yet
- `SynergyIcon` — placeholder 56 px round button; tooltip shows count + `DeckRules.describe_synergy()`, 4 s auto-hide
- `HUD.gd` also exposes an `@export var mobile_controls: CanvasLayer` wired externally from `arena.tscn`'s Inspector, not part of `HUD.tscn` itself

### Map obstacles (from CLAUDE.md)

`scenes/arena/obstacles/{Obstacle,Rock,Tree,Wall}.tscn` / `scripts/arena/obstacle.gd`
- One generic `@tool` script (`Obstacle.tscn`, `StaticBody2D`) drives every variant via exports: `texture`, `sprite_offset`, `shape_type` (RECTANGLE/CIRCLE/CAPSULE/CUSTOM), `collision_size`/`collision_radius`/`collision_height`, `blocks_movement`. `Rock`/`Tree`/`Wall` are just instances of `Obstacle.tscn` with different export values
- Placed per-map as children inside each map scene's `Obstacles` node, not inside `scenes/arena/obstacles/` itself — that folder holds only the reusable prefabs

### Health bars (from CLAUDE.md)

`scenes/ui/HealthBar.tscn` / `scripts/ui/health_bar.gd`
- Reusable `Control` + `ProgressBar` scene
- `init(max_hp: int, team_name: String)` — call once in parent's `_ready()`
- `set_health(new_hp: int)` — call after every HP change; tweens bar value (0.12s)
- Team colors: `"player"` → green, `"enemy"` → red, `"coop"` → blue (reserved)
- `always_visible: bool` export — `true` for hero characters and Command Posts/bases; `false` for units and turrets

### Move marker (from CLAUDE.md)

`scenes/arena/MoveMarker.tscn` / `scripts/arena/move_marker.gd` — `show_at(pos)` pattern: moves to world position, plays animation, auto-hides on `animation_finished`.

### Sprite sizes (from CLAUDE.md Display & Scale Standards)

Turrets are the one entry that matches a clean round source size at native scale — the earlier "150×150 @ 0.4 legacy" turret art has been fully replaced (64×64 sheet, `assets/sprites/turrets/turret1.png`, scale left at the AnimatedSprite2D default of `(1,1)`). Hero and Command Post sprites are not drawn 1:1 at their documented "standard" size — both are large source art scaled down in the scene instead. Treat the table above as "what's actually on disk today," not a target to redraw toward, unless art gets reworked.
