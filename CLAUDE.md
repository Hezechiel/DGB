# CLAUDE.md

Technical reference for Claude Code sessions on this project.

---

## Project Identity

**Duel of Gods: Babylon — Arena Mode**

A landscape mobile MOBA built in Godot 4.7 (GDScript) for Android. Inspired by Star Wars: Force Arena. The player controls a hero directly on the battlefield and wins by deploying units and casting spells across two horizontal lanes to destroy the enemy Command Post. Matches are against an AI opponent; multiplayer capability is a future goal and influences architecture decisions now.

**Active development:** MOBA arena (`scenes/arena/`).

The idle god-game World Map phase that was previously postponed has been removed from the project.

---

## Running the Project

No CLI build step. Open in Godot 4.7, press F5 (main scene) or F6 (current scene).
Main scene: `scenes/menu/MainMenu.tscn` → `scenes/arena/arena.tscn`.

Export for Android: Project → Export → Android (Android SDK must be configured in Godot Editor Settings).

No test runner — validate by running in the Godot editor or via Android APK from GitHub Actions CI (push to main, download artifact).

Quick keyboard test shortcuts in arena (`arena.gd _input()`):
- **U** — 2× energy regen boost for the player, 5s (`EnergySystem.add_modifier(..., ModType.REGEN_MULT, 2.0, 5.0, &"debug_boost")`)
- **I** — -1 flat card cost for the player, 5s, "bloodlust" style (`ModType.COST_REDUCE`, tag `debug_bloodlust`)
- **Y** — prints current energy state for both teams: player/enemy energy, player regen rate, resolved cost of `card_05` (read-only, no mutation)
- **P** — calls `EnergySystem.try_spend("player", &"card_05")` and prints whether it succeeded
- **H** — deal 1/3 of `max_hp` to the player hero (debug trigger for death/respawn/card-lock/telegraph testing, since real combat death is slow to set up manually)

---

## Display & Scale Standards

| Setting | Value |
|---|---|
| Viewport | **1170 × 540**, landscape |
| Stretch mode | `canvas_items` |
| Aspect | `expand` |
| Texture filter | Nearest-neighbor (`default_texture_filter=0`) |

Target device: Samsung S25 FE (2340×1080). At 1170×540, Godot renders at 1/2 native → 2× integer upscale. Clean, no blurring.

**Sprite size standard:**

| Node type | Source sprite size | Scene scale |
|---|---|---|
| Hero / units | Varies per animation sheet (e.g. Zeus: attack 400×400, idle/walk 325×350, death 350×350, spawn 412×412 px/frame) | `Vector2(0.1, 0.1)` on the `AnimatedSprite2D` |
| Turrets | 64 × 64 px per frame | `Vector2(1, 1)` |
| Command Post (base) | 128 × 128 px per frame | `Vector2(0.6, 0.6)` on the `AnimatedSprite2D` |
| Map tiles | 16 × 16 px | — |

Turrets are the one entry that matches a clean round source size at native scale — the earlier "150×150 @ 0.4 legacy" turret art has been fully replaced (64×64 sheet, `assets/sprites/turrets/turret1.png`, scale left at the AnimatedSprite2D default of `(1,1)`). Hero and Command Post sprites are not drawn 1:1 at their documented "standard" size — both are large source art scaled down in the scene instead. Treat the table above as "what's actually on disk today," not a target to redraw toward, unless art gets reworked.

**Map world size:** 4–5 viewports wide × 2–3 viewports tall (see moba_design.md). At 1170×540 viewport: approximately 4680–5850 px wide, 1080–1620 px tall. In practice, current maps (`greek_plateau.tres`, `nord_plains.tres`) use `bounds = Rect2(-460, -305, 920, 610)` — 920×610 px, on the smaller end of that range.

---

## Collision Layers

| Bit | Layer name | Who uses it |
|---|---|---|
| 1 | `player_body` | Player CharacterBody2D |
| 2 | `unit_body` | Ally/enemy unit CharacterBody2D (both teams, shared) |
| 3 | `structures` | Turrets, Command Post (StaticBody2D) |
| 4 | `player_hurtbox` | Player's Hurtbox Area2D |
| 5 | `enemy_hurtbox` | Enemy units' Hurtbox Area2D; enemy turret hurtboxes |
| 6 | `projectiles` | LightningBolt Area2D |
| 7 | `melee_range` | Attack range Area2D on human enemy |
| 8 | `aggro_range` | Wider pre-contact detection Area2D on units (`AggroRange`) — triggers chase before melee/attack range is reached |

LightningBolt: `collision_layer=32` (bit 6), `collision_mask=24` (bits 4+5 — hits both hurtbox layers).

Turret hurtboxes: PlayerTurret layer=8 (player_hurtbox), EnemyTurret layer=16 (enemy_hurtbox).

Combat units (`scripts/arena/unit.gd`) compute their `Hurtbox`/`AttackRange`/`AggroRange` layers/masks at runtime from `team`, since `melee_unit.tscn`/`ranged_unit.tscn` are shared archetypes for both sides — see "Combat unit" below.

---

## Current Codebase — What Exists

### Implemented and working

**Player hero** — `scenes/arena/player.tscn` / `scripts/arena/player.gd`
- `CharacterBody2D`, tap-to-move via `InputR` — no camera child; the camera is a standalone node (`ArenaCamera`, see below)
- Targeting: `primary_target` (explicit tap-on-enemy, sticky until moved/retargeted) takes priority; falls back to `auto_target` (passive nearest-enemy-in-range via `find_nearest_enemy()`), which only engages while the player has no active move command, so tap-to-move always takes precedence over auto-attack. There is no separate "nearest hero" priority tier — `find_nearest_enemy()` treats every valid in-range hurtbox owner (unit, hero, structure) identically by distance; see "Auto-attack priority" below for the corrected description
- Attacks use a cast-point system (`_perform_attack()`): plays `attack_left`, locks movement for the animation's own duration (`frame_count / speed`, read live) unless `can_move_while_attacking`, then applies the hit — `fire_bolt()` for `AttackType.RANGED`, direct `take_damage()` for `AttackType.MELEE` (re-checks range/liveness on landing)
- `take_damage(amount)` with invulnerability window (`invuln_time`), sprite flash feedback
- Stats come from `HeroData` via `configure()`: `max_hp`, `speed`, `attack_range`, `recovery_time` (post-cast-point cooldown remainder — cast-point itself is derived live from the `attack_left` animation, so retuning its fps/frame count never requires touching cooldown data), `projectile_damage`, `attack_type`, `can_move_while_attacking`, `attack_sound`
- Spawn/death animations (`spawn_left`, `death_left`) freeze movement for their duration
- Mirrored by `scripts/arena/hero_dummy.gd` (`scenes/arena/hero_dummy.tscn`) for AI-controlled enemy heroes — same cast-point/attack logic, own march/retreat/heal-seek movement. The underlying "am I in trouble" decision (when to retreat/seek healing) is delegated to a separate autoload, `scripts/HeroAI.gd` — pure HP-hysteresis state logic with no scene/node/position awareness (same "no scenes, no nodes" rule as `EnergySystem`/`HealingSystem`); `hero_dummy.gd` owns the actual movement/targeting once `HeroAI` says which state it's in

**Combat unit** — `scenes/arena/units/melee_unit.tscn`, `scenes/arena/units/ranged_unit.tscn` / `scripts/arena/unit.gd`
- Shared archetype for both teams (`CharacterBody2D`); `team` export drives which hurtbox/attack-range/aggro-range physics layers and groups it joins at `_ready()`, since the scenes carry no team-specific static layer values
- Configured entirely from `UnitData` via `configure(data, team)` — `max_hp`, `damage`, `attack_cooldown`, `speed`, `attack_type` (MELEE/RANGED), `attack_range`, `projectile_scene`, `damage_point_ratio`, `target_filter` (`ALL` / `UNITS_ONLY` / `STRUCTURES_ONLY` — e.g. a battering-ram unit ignores units and only closes on turrets/bases)
- 3-state march/chase/engage state machine (`MarchState`): `MARCHING` (seeks `structure_target`, refreshed periodically via `BattleManager.get_nearest_structure()` rather than any fixed waypoint path — see "Lane system" below), `CHASING` (spotted an enemy unit in the wider `AggroRange`, pursues indefinitely — no leash yet), `ENGAGING` (enemy hurtbox in melee/attack `AttackRange` — stops, winds up, fires/hits on a damage-point timer derived from the live "attack" animation, same cast-point pattern as the hero scripts)
- Seek + separation steering (`compute_separation()`) shared between marching and chasing
- Status effects: `apply_stun()`, `apply_root()`, `apply_slow()` — each independently timed, re-applying takes the longer of current/new duration (never shortens an active effect)
- Spawn invulnerability window on every deploy (`invuln_time`, not just first spawn — units get no "safe first spawn" the way heroes do since every deployment can land mid-fight)
- `take_damage(amount)` → cosmetic death (`die()`): disables collision/hurtbox immediately, plays "death" animation if present, then `queue_free()`
- Tap-to-target only for enemy-side units (`_on_hurtbox_input_event` sets the player's `primary_target`)

**Turrets** — `scenes/arena/turrets/PlayerTurret.tscn`, `scenes/arena/turrets/EnemyTurret.tscn` / `scripts/arena/turret.gd`
- `StaticBody2D`, shared script, `owner_team` and `target_group` exports
- Full MOBA variables: `armor`, `stun_timer`, `restore_hp_per_sec`, `regen_buffer`
- 4-stage damage visuals via `AnimatedSprite2D` frame control (no `queue_free()` — turrets become wrecks)
- `_on_destroyed()` disables CollisionShape2D and DetectionRange deferred
- Owns an exported `protection_zone: Rect2` that blocks enemy unit deployment while the turret is alive — registered into `BattleManager` on `_ready()`, unregistered on `_on_destroyed()`; see "Spawn protection zones" below for the mechanism

**Health bars** — `scenes/ui/HealthBar.tscn` / `scripts/ui/health_bar.gd`
- Reusable `Control` + `ProgressBar` scene
- `init(max_hp: int, team_name: String)` — call once in parent's `_ready()`
- `set_health(new_hp: int)` — call after every HP change; tweens bar value (0.12s)
- Team colors: `"player"` → green, `"enemy"` → red, `"coop"` → blue (reserved)
- `always_visible: bool` export — `true` for hero characters and Command Posts/bases; `false` for units and turrets

**Projectile** — `scenes/arena/projectiles/LightningBolt.tscn` / `scripts/arena/projectiles/lightning_bolt.gd`
- `Area2D`, 8-directional animated sprite
- `setup(start_pos, dir)` called deferred after `add_child`
- `_try_damage(target)`: checks `is_in_group(hit_group)` and `has_method("take_damage")`
- `hit_group` set by shooter (`"team_enemy"` or `"team_player"`)

**Move marker** — `scenes/arena/MoveMarker.tscn` / `scripts/arena/move_marker.gd`
- `show_at(pos)` pattern: moves to world position, plays animation, auto-hides on `animation_finished`

**BattleManager** — autoload, `scripts/BattleManager.gd`
- `register(unit, team)` — adds to `team_player`/`team_enemy`, connects `tree_exited` for cleanup
- `is_team_alive(team)` — foundation for win/lose
- Hero death/respawn: `on_hero_died(hero, team)` starts the respawn countdown (`_respawn_left: Dictionary`, team → seconds left), `respawn_seconds = clampi(3 + death_count - 1, 3, 10)`; `_process()` ticks it down and calls `_respawn_hero(team)` (teleports hero to `hero_spawn_positions[team]`, calls `hero.revive()`) when it hits 0
- `is_hero_dead(team: String) -> bool` — single source of truth for "is this team's hero currently dead" (`_respawn_left.has(team)`); any system that needs to know should call this rather than tracking its own copy
- Signals: `hero_died(team, respawn_seconds)`, `hero_respawn_tick(team, seconds_left)`, `hero_respawned(team)` — multiple independent UI pieces self-subscribe to these directly in their own `_ready()` (see Key Conventions)
- `get_nearest_structure(defending_team, from_pos) -> Node2D` — returns the nearest *alive* turret or base belonging to `defending_team`, no lane priority; this is what drives all unit/hero march targeting (see "Lane system" below)
- Deploy/protection: `configure_map(map_data)` sets `deploy_bounds`; `register_protection_zone()`/`unregister_protection_zone()` and `is_deploy_position_valid()`/`is_card_target_valid()` — see "Spawn protection zones" below
- Win/lose: `match_ended(winner_team: String)` signal, `last_winner`, 180s match timer — see "Win / lose" below

**EnergySystem** — autoload, `scripts/EnergySystem.gd`
- Per-team resource pool — always called "energy," never "mana," throughout the codebase
- `MAX_ENERGY = 10.0`, `START_ENERGY = 7.0`, `BASE_REGEN_PER_SEC = 0.25` (1 energy / 4s)
- Modifier layer: `add_modifier(team, type: ModType, value, duration, tag)` / `remove_modifier(team, tag)` / `has_modifier(team, tag)`. `ModType.REGEN_MULT` modifiers multiply and stack (e.g. a temporary regen boost); `ModType.COST_REDUCE` modifiers sum and stack, clamped so resolved cost never drops below 0 (e.g. a temporary "bloodlust" cost reduction). `duration = INFINITE_DURATION (-1.0)` marks a modifier that only ends via explicit `remove_modifier()`
- Atomic spend: `try_spend(team, card_id) -> bool` — checks `can_afford()` then deducts in one call; per its own header comment, callers must never decrement energy themselves. Also exposes `can_afford()`, `resolve_cost()`, `add_energy()`, `drain_energy()`, `start()`/`stop()`/`is_running()`
- Deliberately holds no scene/node references — pure state + math, kept server-authoritative-ready for future multiplayer; its only dependency is `CardDB`

**HealingSystem** — autoload, `scripts/HealingSystem.gd`, plus `scenes/arena/HealingPod.tscn` / `scripts/arena/healing_pod.gd`
- Static map pickups usable by **heroes of both teams** — no team lock, and units can never use them (SWFA-style design). A pod's `owning_side` (derived from node name) is only an AI seek-preference tiebreaker, not a usage gate
- `HealingSystem.trigger_heal(team, instant_amount, hot_total, hot_duration)` — fires an instant heal plus a heal-over-time that ticks independently in `_process()`; HoT is cancelled on death (`cancel_heal()`, called from `player.gd`/`hero_dummy.gd`'s `die()`) rather than continuing through a respawn
- Per-pod cooldown lifecycle: `register_pod(pod_id, initial_delay, respawn_cooldown)`, `consume_pod(pod_id)` (resets to cooldown), `pod_ready` signal when a pod becomes available again
- Pod exports (`healing_pod.gd`): `initial_delay`, `respawn_cooldown`, `instant_heal_amount`, `hot_total_amount`, `hot_duration`, and a `single_use` flag reserved for a future portable/summoned pod (`BattleManager.spawn_healing_pod()` exists today only as a documented no-op stub)

**MapDB / MapData** — autoload `scripts/MapDB.gd`, resource class `scripts/arena/map_data.gd`
- `MapDB` scans `data/maps/*.tres` at startup and indexes every `MapData` resource by its `id` field. Two maps exist today: `greek_plateau.tres` (release-ready) and `nord_plains.tres` (`release_ready = false`, still WIP)
- `MapData` exports: `bounds: Rect2` (the single source of truth — feeds both `BattleManager.deploy_bounds` and `ArenaCamera`'s pan bounds, so the two can never drift apart), `camera_edge_margin`, `camera_edge_pan_speed_max`, `hero_spawn_player`/`hero_spawn_enemy`, `map_scene: PackedScene`. Structures (turrets, bases, healing pods) are **not** part of `MapData` — they stay hand-placed inside each map's own scene
- `arena.gd::_ready()` resolves `MapDB.get_map(MatchConfig.map_id)` and instantiates `map_data.map_scene` synchronously into the empty `MapRoot` node before calling `BattleManager.configure_map()` / `arena_camera.configure_map()`, so map-scene structures can self-register before hero spawn

**ArenaCamera** — `scripts/arena/arena_camera.gd` (`Camera2D`, standalone node in `arena.tscn`, not a child of Player)
- Drag-to-pan via `_unhandled_input` (8px drag threshold), clamped every frame to `bounds_min`/`bounds_max` — populated per-map by `configure_map(map_data: MapData)`. Native `Camera2D` limits are explicitly disabled (`±10,000,000`) so only this custom clamp applies
- Optional follow mode (`Settings.lock_camera`): lerps toward the player using `follow_smoothing`; a manual drag pauses follow for a grace period (`return_delay`) before ramping back (`return_ramp_time`)
- Screen-edge pan during card drag-to-deploy: `CardHand`'s `deploy_preview_started/updated/ended` signals are relayed by `arena.gd` into `begin_deploy_pan()`/`update_deploy_pan()`/`end_deploy_pan()`; edge-pan runs ahead of the lock-camera check every physics frame, so it overrides follow mode while a card drag is active
- `recenter_on_player(duration := 0.4)` tweens back to the player (`EASE_OUT`/`TRANS_QUART`), wired to HUD's `PlayerCharacter` button
- **No zoom** — the camera is fixed-zoom; there is no pinch/scroll handling anywhere in this script

**Card hand & drag-to-deploy** — `scenes/arena/ui/CardHand.tscn` / `scripts/arena/ui/card_hand.gd` + `scripts/arena/ui/card.gd`
- 3 playable slots (`Card1`/`Card2`/`Card3`, each wrapped in its own `AspectRatioContainer`) plus a `NextCardPreview` slot — not 4 playable slots
- 12-card deck shuffled into a cyclic queue at `_ready()`; Clash-Royale style refill — a played card goes to the back of the queue, the vacated slot is refilled from the front, `NextCardPreview` always mirrors the queue's front
- Drag starts in `Card._gui_input()` (press) → `CardHand.begin_drag(slot_index, touch_index)`, which emits `deploy_preview_started`. `CardHand._input()` (runs ahead of GUI) then tracks the matching `InputEventScreenDrag`, converts screen→world, flips the card to its back while dragged outside the hand's rect, and emits `deploy_preview_updated(world_pos, is_valid, screen_pos)` every frame using `BattleManager.is_card_target_valid(card, world_pos, team) -> bool`
- On release (`_finish_drag`): releasing over the hand cancels; releasing over an invalid map position cancels (card stays in the slot); only a valid map position calls `play_card()`, which re-checks `is_hero_dead()`, atomically spends via `EnergySystem.try_spend()`, then calls `BattleManager.spawn_unit()` or `BattleManager.cast_spell()` depending on the card
- Card affordability greying (`set_affordable()`) refreshes on every energy change and after every play

**Map obstacles** — `scenes/arena/obstacles/{Obstacle,Rock,Tree,Wall}.tscn` / `scripts/arena/obstacle.gd`
- One generic `@tool` script (`Obstacle.tscn`, `StaticBody2D`) drives every variant via exports: `texture`, `sprite_offset`, `shape_type` (RECTANGLE/CIRCLE/CAPSULE/CUSTOM), `collision_size`/`collision_radius`/`collision_height`, `blocks_movement`. `Rock`/`Tree`/`Wall` are just instances of `Obstacle.tscn` with different export values
- Placed per-map as children inside each map scene's `Obstacles` node (`scenes/arena/maps/GreekPlateauMap.tscn`, `scenes/arena/maps/NordPlainsMap.tscn`), not inside `scenes/arena/obstacles/` itself — that folder holds only the reusable prefabs
- Individual obstacles are plain `StaticBody2D`s, not `NavigationObstacle2D` — each map scene instead has exactly one standalone `NavigationObstacle2D` node at the map root

**EnemyCardAI** — `scripts/arena/enemy_card_ai.gd` (plain `Node`, instantiated directly in `arena.gd::_ready()`, not an autoload or a `.tscn`)
- Ticks every `decision_interval` (1.75s default) in `_process()`, gated on `EnergySystem.is_running()` and the enemy hero being alive
- Mirrors `CardHand`'s 3-slot mechanic with its own hardcoded deck-id list (deliberately duplicated, not shared with `CardHand.tscn`'s deck — must be kept in sync by hand) and no preview slot
- Each tick, plays *every* slot that is simultaneously affordable and has a resolvable, valid position (not just one card per tick): checks `EnergySystem.can_afford()`, resolves a jittered deploy position (`_resolve_play_position()` — unit cards jitter around its own hero, spell cards jitter around the nearest player-owned structure via `get_nearest_structure()` and are skipped if none is found), validates through the same `BattleManager.is_card_target_valid()` the human player uses, then atomically spends via `try_spend()`

**Win / lose** — `scenes/menu/MatchEndScreen.tscn` / `scripts/ui/match_end_screen.gd`
- `BattleManager` emits `match_ended(winner_team: String)` from `on_base_destroyed()` (a Command Post reaches 0 HP) or when its 180s match timer expires (`"draw"` — marked TODO to become a progress-based tiebreak later)
- `arena.gd::_on_match_ended()` stops `EnergySystem` and changes scene to `MatchEndScreen.tscn`, which reads `BattleManager.last_winner` in its own `_ready()` (not the signal argument, since it's a fresh scene) and offers a button back to `MainMenu.tscn`

**Hero death gating & telegraph** — reacts to `BattleManager`'s hero-death signals above, no shared state duplicated beyond `is_hero_dead()`
- `scripts/arena/ui/card_hand.gd` / `scripts/arena/enemy_card_ai.gd` — card plays are locked while `BattleManager.is_hero_dead(team)` is true: `CardHand._refresh_affordability()` force-greys all 3 hand slots regardless of energy, `CardHand.play_card()` gates the same way (covers double-tap/future network calls that bypass the drag UI), and `EnemyCardAI._process()` skips its decision tick entirely — `EnergySystem` regen keeps running unaffected the whole time
- `scripts/arena/desaturate_overlay.gd` (`ColorRect`, direct child of `Arena` root in `arena.tscn`, **not** in a `CanvasLayer`) — desaturates the battlefield to greyscale while the player hero is dead via a `canvas_item` shader (`scenes/arena/ui/shaders/desaturate.gdshader`) reading `SCREEN_TEXTURE`; tracks its own `_desaturation: float` and tweens it via `create_tween().tween_method()` on `hero_died`/`hero_respawned`. Deliberately lives in the same canvas as the map/units/heroes (not HUD's `CanvasLayer`) with `z_index = 100` so it always paints after everything else, including units added later via `BattleManager.arena_root.add_child()` — see Key Conventions for why a separate `CanvasLayer` doesn't work here
- `scripts/arena/ui/death_telegraph.gd` (`scenes/arena/ui/DeathTelegraph.tscn`, instanced in `scenes/hud/HUD.tscn` at `layer = 5`, between the world and HUD's `layer = 10`) — shows/hides a top-center "GOD DEAD" + countdown label (red/white, transparent background) on the same three signals; purely cosmetic, HUD-scoped, no shader involved
- `scripts/arena/ui/match_info_bar.gd` — the small `PlayerRespawnCounter`/`EnemyRespawnCounter` in the top bar are a third, independent consumer of the same three signals (pre-existing, unaffected by the two additions above)

**HUD** — `scenes/hud/HUD.tscn` / `scripts/hud/HUD.gd`
- `CanvasLayer` → `Root` (`Control`) with children: `PauseButton` (TouchScreenButton), `PlayerCharacter` (TouchScreenButton — despite the name, this is the recenter-camera button, wired to `HUD.recenter_camera_requested` → `arena.gd` → `arena_camera.recenter_on_player()`), `CardHand`, `EnergyBar`, `MatchInfoBar`, `DeathTelegraph`, `SettingOverlay` (initially hidden)
- No minimap exists anywhere under `scenes/hud` — that's still genuinely not implemented, not a placeholder like the others used to be
- `HUD.gd` also exposes an `@export var mobile_controls: CanvasLayer` wired externally from `arena.tscn`'s Inspector, not part of `HUD.tscn` itself

**Arena root** — `scenes/arena/arena.tscn` / `scripts/arena/arena.gd`
- `_unhandled_input` handles tap-to-move; free-drag camera panning is handled by `ArenaCamera` itself (see above), not here
- Connects `HUD.exit_requested` → MainMenu, `HUD.recenter_camera_requested` → `arena_camera.recenter_on_player()`, `BattleManager.match_ended` → `_on_match_ended()`
- Loads the active map via `MapDB`/`MapData` into `MapRoot` at `_ready()` — see "MapDB / MapData" above

### Not yet implemented

- Lane system (top lane, bottom lane, fixed waypoints, unit marching along a path) — units and hero AI currently march straight at `BattleManager.get_nearest_structure()`, the nearest *alive* structure regardless of lane, refreshed periodically; see "Lane system" under Architecture below
- Minimap with hero position indicators

---

## Architecture — Direction

### MOBA match structure

`arena.tscn`'s actual direct children today (map-agnostic shell — no map content is a static child of this scene anymore):

```
Arena (Node2D, arena.gd)
├── MapRoot              (empty Node2D — the active map's scene is instantiated here at runtime)
├── DesaturateRect        (ColorRect, death-telegraph shader overlay)
├── MoveMarker
├── DenialZoneOverlay
├── DeployGhost
├── ArenaCamera           (Camera2D)
└── HUD                   (CanvasLayer)
```

Map-specific content (tilemap, obstacles, Command Posts, turrets, healing pods) lives inside the per-map scene that gets instantiated into `MapRoot` (see "MapDB / MapData" above) — not hardcoded into `arena.tscn`. Units and heroes are spawned at runtime directly under `Arena` by `BattleManager`, not placed as static scene nodes either. This replaces the previous plan of a single fixed map baked directly into `arena.tscn` with `TileMapLayer`/`Obstacles`/`TopLane`/`BotLane`/`PlayerBase`/`EnemyBase`/per-lane turrets/`UnitContainer` as direct children — that structure no longer exists.

### Camera system

Implemented — see "ArenaCamera" under "Implemented and working" above for the terse API summary. Default behaviour: drag anywhere on the battlefield pans the camera freely, clamped to the active map's bounds. Optional setting (`Settings.lock_camera`): soft-follow the player hero, with a grace period after a manual drag before it ramps back to following. Dragging from a scroll in the HUD triggers screen-edge pan instead of free pan — the camera nudges toward whichever edge the dragged finger approaches, overriding follow mode for the duration of the drag, so the player can always reach any map position while deploying. There is no zoom.

### Auto-attack priority

Player's `_physics_process` attack logic, in priority order:
1. If `primary_target` is set and valid (explicit tap-on-enemy) → attack it if in range; if out of range, chase it (overrides tap-to-move)
2. Else, `find_nearest_enemy()` picks the nearest valid enemy hurtbox currently in attack range (unit, hero, or structure — no separate priority tier between them) and fires **only** if the player has no active tap-to-move command that frame — auto-attack never interrupts movement, and never chases on its own

`primary_target` is set by `set_primary_target()` (tapping an enemy directly) and cleared when the target dies or `_clear_primary_target()`/`_on_primary_target_removed()` fires.

### Lane system

Not yet implemented. `BattleManager.get_nearest_structure(defending_team, from_pos) -> Node2D` returns the nearest *alive* turret or base belonging to the defending team, with zero lane-priority logic (turrets are still bucketed by `"top"`/`"bot"` internally for lane-clear/vulnerability bookkeeping, but the nearest-structure query itself ignores that entirely). Both `unit.gd` (`_update_structure_target()`) and `hero_dummy.gd` refresh this target periodically and steer straight at it — there is no fixed waypoint path anywhere in the codebase. This is intentional: units can now be deployed anywhere on the map via drag-to-deploy, so a fixed lane path wouldn't make sense until deploy zones are lane-constrained again (if ever).

### Card drag-to-deploy system

Implemented — see "Card hand & drag-to-deploy" under "Implemented and working" above for the full flow (drag start, live validation, drop handling, hand refill).

### Spawn protection zones

Implemented, but not via Area2D/CircleShape2D. Each turret and base exports a `protection_zone: Rect2` (`scripts/arena/turret.gd`, `scripts/arena/base.gd`), registered into `BattleManager._protection_zones: Dictionary` (`team -> Array[Rect2]`) on `_ready()` via `register_protection_zone()`, and unregistered on `_on_destroyed()`. `BattleManager.is_deploy_position_valid(pos, team) -> bool` checks the map's `deploy_bounds` and then rejects any point inside an *enemy*-team zone rect; `is_card_target_valid(card, pos, team)` wraps it and lets spell cards skip the zone check entirely (bounds-only, since spells are playable anywhere on the map). Zones are large per-lane/flank rectangles covering roughly a structure's defended area (e.g. `Rect2(-460, -305, 50, 610)` for a base), not small radii around the structure itself — as turrets fall, the protected frontier shrinks, and "own half" is now purely an emergent effect of how a given map's zone rectangles happen to be laid out, not a separate hardcoded center-line rule. New maps only need different structure placement/zone rects; this function itself never changes per-map.

### Energy system

Implemented — see "EnergySystem" under "Implemented and working" above for the full API (`add_modifier`/`ModType.REGEN_MULT`/`ModType.COST_REDUCE`, `try_spend`, `can_afford`, `resolve_cost`). Always "energy," never "mana," in code, comments, and this document.

### Respawn system

Implemented in `BattleManager.gd` (see "Hero death gating & telegraph" above) — `on_hero_died()`/`_respawn_hero()`/`is_hero_dead()`, with `hero_died`/`hero_respawn_tick`/`hero_respawned` as the shared broadcast. Respawn duration: `clampi(3 + death_count - 1, 3, 10)` seconds (`death_count` persists for the whole match, never resets). Three independent consumers react to these signals today: `match_info_bar.gd`'s small `RespawnCounter`, the card-play lock (`card_hand.gd` / `enemy_card_ai.gd`), and the full-screen death telegraph (`desaturate_overlay.gd` + `death_telegraph.gd`). Adding a fourth reaction to hero death should follow the same pattern — self-subscribe in `_ready()`, don't route through an existing consumer.

### Win / lose

Implemented — see "Win / lose" under "Implemented and working" above.

### Enemy AI (EnemyCardAI)

Implemented — see "EnemyCardAI" under "Implemented and working" above. Mirrors player mechanics closely (same `EnergySystem`, same `BattleManager.is_card_target_valid()`/`spawn_unit()`/`cast_spell()` calls) but is a deliberately separate, minimal-policy script rather than sharing code with `card_hand.gd` — no scoring/utility AI, just an affordability+validity pass over its hand every tick. Replacing it with a network player later requires only swapping the input source; the validation/spend/spawn calls it goes through are already identical to the human path.

---

## Key Conventions

- **`call_deferred`** when `add_child` and `setup()` happen in the same frame
- **`take_damage(amount: int)`** — universal damage interface; all damageable nodes implement it
- **`distance_squared_to()`** everywhere for range checks (avoids sqrt)
- **Code-based signal connections** in `_ready()` — no Inspector wiring
- **`TouchScreenButton`** for in-game tappable UI on Android
- **Health bar:** `health_bar.init(max_hp, team_name)` in `_ready()`; `health_bar.set_health(hp)` after every HP change; `health_bar.visible = false` on death
- **Turrets do not `queue_free()`** — `_on_destroyed()` disables physics, detection, and protection zone; leaves wreck visual
- **Animation names:** 4-dir: `"up" "down" "left" "right"`. 8-dir adds `"up_left" "up_right" "down_left" "down_right"`
- **Slovak/English mixed** in comments and variable names — preserve the developer's style
- **`always_visible = true`** on HealthBar for heroes and Command Posts/bases; `false` for units and turrets
- **Groups:** `"team_player"`, `"team_enemy"`, `"heroes"`, `"turrets"` — add heroes to both `"team_*"` and `"heroes"` for attack priority logic
- **Self-subscribing UI:** small, independent UI reactions to a `BattleManager` signal (respawn counters, card-lock, death telegraph) connect to it directly in their own `_ready()` rather than being wired/relayed through `arena.gd` or another consumer — keeps each piece a drop-in addition/removal with zero coupling to sibling UI
- **`canvas_item` screen-reading shaders (Godot 4.7):** `SCREEN_TEXTURE` is **not** a bare built-in in this Godot version — it was removed. Declare it yourself: `uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;` (see `scenes/arena/ui/shaders/desaturate.gdshader`). Omitting the uniform declaration is a hard compile error, not a silent fallback
- **Screen-reading `canvas_item` shaders: keep them in the same canvas as their content.** `desaturate_overlay.gd`'s `ColorRect` lives directly under `Arena` (layer 0, with `z_index` forcing it to draw last) rather than inside a separate `CanvasLayer` alongside the HUD-style telegraph label, on the theory that `SCREEN_TEXTURE` reads don't reliably cross a `CanvasLayer` boundary. This was fixed at the same time as the missing `hint_screen_texture` uniform declaration above, so the two fixes were never isolated from each other — treat "same canvas as the content" as the safe default for any future screen-reading shader, not as a confirmed, isolated Godot behavior
- **No scenes/nodes/positions in "pure logic" autoloads** — `EnergySystem`, `HealingSystem`, and `HeroAI` all deliberately hold zero scene-tree references, kept as pure state + math so they stay server-authoritative-ready for future multiplayer and easy to unit-reason about. Systems that need scene/position awareness (movement, spawning) stay in the node scripts that call into these autoloads, not inside them
