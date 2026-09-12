# CLAUDE.md

Technical reference for Claude Code sessions on this project.

---

## Project Identity

**Divine Gestures: Babylon — Arena Mode**

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
- **T** — deal 80 damage to the PlayerTurret
- **H** — deal 1/3 of `max_hp` to the player hero (debug trigger for death/respawn/card-lock/telegraph testing, since real combat death is slow to set up manually)

---

## Display & Scale Standards

| Setting | Value |
|---|---|
| Viewport | **780 × 360**, landscape |
| Stretch mode | `canvas_items` |
| Aspect | `expand` |
| Texture filter | Nearest-neighbor (`default_texture_filter=0`) |

Target device: Samsung S25 FE (2340×1080). At 780×360, Godot renders at 1/3 native → 3× integer upscale. Clean, no blurring.

> **Note:** `project.godot` currently shows 1080×640 — this must be updated to 780×360.

**Sprite size standard:**

| Node type | Source sprite size | Scene scale |
|---|---|---|
| Hero / units | 32 × 32 px per frame | `Vector2(1, 1)` |
| Turrets | 64 × 64 px per frame | `Vector2(1, 1)` |
| Command Post (base) | 96 × 96 px | `Vector2(1, 1)` |
| Map tiles | 16 × 16 px | — |

Current turret sprites are 150×150 at scale (0.4, 0.4) — legacy. Redraw at 64×64 when reworking art.

**Map world size:** 4–5 viewports wide × 2–3 viewports tall (see moba_design.md). At 780×360 viewport: approximately 3120–3900 px wide, 720–1080 px tall.

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

LightningBolt: `collision_layer=32` (bit 6), `collision_mask=24` (bits 4+5 — hits both hurtbox layers).

Turret hurtboxes: PlayerTurret layer=8 (player_hurtbox), EnemyTurret layer=16 (enemy_hurtbox).

---

## Current Codebase — What Exists

### Implemented and working

**Player hero** — `scenes/arena/player.tscn` / `scripts/arena/player.gd`
- `CharacterBody2D`, tap-to-move via `InputR`, Camera2D child (currently follows player — camera system will be reworked)
- Targeting: `primary_target` (explicit tap-on-enemy, sticky until moved/retargeted) takes priority; falls back to `auto_target` (passive nearest-enemy-in-range), which only engages while the player has no active move command, so tap-to-move always takes precedence over auto-attack
- Attacks use a cast-point system (`_perform_attack()`): plays `attack_left`, locks movement for the animation's own duration (`frame_count / speed`, read live) unless `can_move_while_attacking`, then applies the hit — `fire_bolt()` for `AttackType.RANGED`, direct `take_damage()` for `AttackType.MELEE` (re-checks range/liveness on landing)
- `take_damage(amount)` with invulnerability window (`invuln_time`), sprite flash feedback
- Stats come from `HeroData` via `configure()`: `max_hp`, `speed`, `attack_range`, `recovery_time` (post-cast-point cooldown remainder — cast-point itself is derived live from the `attack_left` animation, so retuning its fps/frame count never requires touching cooldown data), `projectile_damage`, `attack_type`, `can_move_while_attacking`, `attack_sound`
- Spawn/death animations (`spawn_left`, `death_left`) freeze movement for their duration
- Mirrored by `scripts/arena/hero_dummy.gd` (`scenes/arena/hero_dummy.tscn`) for AI-controlled enemy heroes — same cast-point/attack logic, own march/retreat/heal-seek state machine instead of player input

**Enemy unit** — `scenes/enemies/human.tscn` / `scripts/human.gd`
- `CharacterBody2D`, seek+separation steering toward `target: Node2D`
- Currently targets the player directly — will be replaced with lane waypoint targeting
- `take_damage(amount)` → `queue_free()` on death
- Variables: `max_hp=50`, `hp`, `damage`, `attack_cooldown`

**Turrets** — `scenes/arena/PlayerTurret.tscn`, `scenes/arena/EnemyTurret.tscn` / `scripts/arena/turret.gd`
- `StaticBody2D`, shared script, `owner_team` and `target_group` exports
- Full MOBA variables: `armor`, `stun_timer`, `restore_hp_per_sec`, `regen_buffer`
- 4-stage damage visuals via `AnimatedSprite2D` frame control (no `queue_free()` — turrets become wrecks)
- `_on_destroyed()` disables CollisionShape2D and DetectionRange deferred
- **Planned addition:** each turret owns a `SpawnProtectionZone` (Area2D) that blocks enemy unit deployment; disabled on destruction

**Health bars** — `scenes/ui/HealthBar.tscn` / `scripts/ui/health_bar.gd`
- Reusable `Control` + `ProgressBar` scene
- `init(max_hp: int, team_name: String)` — call once in parent's `_ready()`
- `set_health(new_hp: int)` — call after every HP change; tweens bar value (0.12s)
- Team colors: `"player"` → green, `"enemy"` → red, `"coop"` → blue (reserved)
- `always_visible: bool` export — `true` for hero characters, `false` for units/turrets

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
- **Planned addition:** `base_destroyed(team: String)` signal; `notify_hero_killed(team)` for mana regen events

**Hero death gating & telegraph** — reacts to `BattleManager`'s hero-death signals above, no shared state duplicated beyond `is_hero_dead()`
- `scripts/arena/ui/card_hand.gd` / `scripts/arena/enemy_card_ai.gd` — card plays are locked while `BattleManager.is_hero_dead(team)` is true: `CardHand._refresh_affordability()` force-greys all 3 hand slots regardless of energy, `CardHand.play_card()` gates the same way (covers double-tap/future network calls that bypass the drag UI), and `EnemyCardAI._process()` skips its decision tick entirely — `EnergySystem` regen keeps running unaffected the whole time
- `scripts/arena/desaturate_overlay.gd` (`ColorRect`, direct child of `Arena` root in `arena.tscn`, **not** in a `CanvasLayer`) — desaturates the battlefield to greyscale while the player hero is dead via a `canvas_item` shader (`scenes/arena/ui/shaders/desaturate.gdshader`) reading `SCREEN_TEXTURE`; tracks its own `_desaturation: float` and tweens it via `create_tween().tween_method()` on `hero_died`/`hero_respawned`. Deliberately lives in the same canvas as the map/units/heroes (not HUD's `CanvasLayer`) with `z_index = 100` so it always paints after everything else, including units added later via `BattleManager.arena_root.add_child()` — see Key Conventions for why a separate `CanvasLayer` doesn't work here
- `scripts/arena/ui/death_telegraph.gd` (`scenes/arena/ui/DeathTelegraph.tscn`, instanced in `scenes/hud/HUD.tscn` at `layer = 5`, between the world and HUD's `layer = 10`) — shows/hides a top-center "GOD DEAD" + countdown label (red/white, transparent background) on the same three signals; purely cosmetic, HUD-scoped, no shader involved
- `scripts/arena/ui/match_info_bar.gd` — the small `PlayerRespawnCounter`/`EnemyRespawnCounter` in the top bar are a third, independent consumer of the same three signals (pre-existing, unaffected by the two additions above)

**HUD** — `scenes/hud/HUD.tscn` / `scripts/hud/HUD.gd`
- `CanvasLayer`, pause button, settings overlay, exit signal
- Placeholders for: mana bar, scroll hand (4 cards), minimap, hero HP

**Arena root** — `scenes/arena/arena.tscn` / `scripts/arena/arena.gd`
- `_unhandled_input` handles tap-to-move and will handle camera drag
- Connects `HUD.exit_requested` → MainMenu

### Not yet implemented

- Free-drag camera (replace player-follow Camera2D with standalone panning camera)
- Lane system (top lane, bottom lane, waypoints, unit marching)
- Command Post / base structure and win condition
- Mana / resource system with event-based regen boosts
- Scroll (card) drag-to-deploy system
- Spawn protection zones per turret
- Scroll hand HUD (4 slots, drag gesture)
- Minimap with hero position indicators
- Enemy AI hero
- `CpuOpponent` (AI mana + deploy decisions)
- Win/lose screen
- Map obstacles

---

## Architecture — Direction

### MOBA match structure

```
arena.tscn
├── TileMapLayer              (map tiles — world size ~3500 × 900)
├── Obstacles                 (Node2D — static terrain for retreats/traps)
├── TopLane                   (Node2D — waypoint path, top of map)
├── BotLane                   (Node2D — waypoint path, bottom of map)
├── PlayerBase                (Command Post — left edge)
├── EnemyBase                 (Command Post — right edge)
├── PlayerTurret_Top/Bot      (left-side lane defense)
├── EnemyTurret_Top/Bot       (right-side lane defense)
├── UnitContainer             (all summoned units live here)
├── Player                    (hero — CharacterBody2D, no camera child)
├── EnemyHero                 (AI-controlled hero)
├── Camera2D                  (standalone, drag-to-pan, optional follow mode)
├── HUD                       (CanvasLayer)
│   ├── TopStrip              (minimap, hero HP, pause)
│   └── BottomStrip           (mana bar, 4 scroll slots)
└── MoveMarker
```

### Camera system

The Camera2D is a standalone node in the arena scene (not a child of Player). Default behaviour: drag anywhere on the battlefield pans the camera freely. Optional setting: lock camera to follow the player hero.

Gesture rules:
- **Short tap** on battlefield → move player to that position (`InputR.set_move_target`)
- **Drag** on battlefield → pan camera
- **Drag starting from a scroll in the HUD** → scroll deployment drag; temporarily unlocks follow-cam if it is active so the player can drag to any map position

### Auto-attack priority

Player's `_physics_process` attack logic in priority order:
1. If `selected_target` is set and valid → attack it; if out of range → move toward it until in range
2. Else if any enemy hero in `team_enemy` + `heroes` group is within `attack_range` → attack nearest hero
3. Else → attack nearest enemy unit in `team_enemy` (current behaviour)

`selected_target` is set by tapping an enemy directly. Cleared when target dies or player taps empty ground.

### Scroll (card) deploy system

Scrolls are dragged from the HUD hand to the battlefield. On release:
- `SpawnSystem.is_valid_position(world_pos, team)` checks against all active enemy `SpawnProtectionZone` Areas
- If valid: instantiate unit or trigger spell at `world_pos`; deduct mana; rotate hand
- If invalid: return scroll to hand with visual rejection feedback

`SpawnSystem` (autoload, to be built): maintains a list of active protection zones. Exposes `is_valid_position(pos, team) -> bool` and `register_zone(area, team)` / `unregister_zone(area)`.

### Spawn protection zones

Each turret has a child `SpawnProtectionZone` (Area2D with CircleShape2D). Enemy units cannot be deployed inside a friendly turret's zone. When `_on_destroyed()` fires, the zone is disabled alongside the collision shape. As turrets fall, the protected frontier shrinks — each turret destroyed opens new territory for the enemy to deploy into.

### Mana system

`ManaSystem` (autoload, to be built):
- `player_mana: float`, `enemy_mana: float` — both cap at `max_mana`
- `base_regen: float` — constant per-second regeneration
- `add_regen_boost(team, amount, duration)` — temporary flat regen bonus; stacks additionally; expires after `duration` seconds
- Triggered events (triggers wired during gameplay development, not hardcoded): hero kill, turret destroy, etc.
- Exposes `can_afford(team, cost) -> bool` and `spend(team, cost)`

### Respawn system

Implemented in `BattleManager.gd` (see "Hero death gating & telegraph" above) — `on_hero_died()`/`_respawn_hero()`/`is_hero_dead()`, with `hero_died`/`hero_respawn_tick`/`hero_respawned` as the shared broadcast. Respawn duration: `clampi(3 + death_count - 1, 3, 10)` seconds (`death_count` persists for the whole match, never resets). Three independent consumers react to these signals today: `match_info_bar.gd`'s small `RespawnCounter`, the card-play lock (`card_hand.gd` / `enemy_card_ai.gd`), and the full-screen death telegraph (`desaturate_overlay.gd` + `death_telegraph.gd`). Adding a fourth reaction to hero death should follow the same pattern — self-subscribe in `_ready()`, don't route through an existing consumer.

### Win / lose

`BattleManager` emits `base_destroyed(team: String)` when a Command Post reaches 0 HP. `arena.gd` listens and triggers outcome screen + scene transition.

### Enemy AI (CpuOpponent)

Mirrors player mechanics exactly — same `ManaSystem`, same `SpawnSystem.deploy()` call. Decision loop: accumulate mana → pick scroll → validate position → deploy. Replacing `CpuOpponent` with a network player requires only swapping the input source; all game logic remains identical.

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
- **`always_visible = true`** on HealthBar for heroes; `false` for units and turrets
- **Groups:** `"team_player"`, `"team_enemy"`, `"heroes"`, `"turrets"` — add heroes to both `"team_*"` and `"heroes"` for attack priority logic
- **Self-subscribing UI:** small, independent UI reactions to a `BattleManager` signal (respawn counters, card-lock, death telegraph) connect to it directly in their own `_ready()` rather than being wired/relayed through `arena.gd` or another consumer — keeps each piece a drop-in addition/removal with zero coupling to sibling UI
- **`canvas_item` screen-reading shaders (Godot 4.7):** `SCREEN_TEXTURE` is **not** a bare built-in in this Godot version — it was removed. Declare it yourself: `uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;` (see `scenes/arena/ui/shaders/desaturate.gdshader`). Omitting the uniform declaration is a hard compile error, not a silent fallback
- **Screen-reading `canvas_item` shaders: keep them in the same canvas as their content.** `desaturate_overlay.gd`'s `ColorRect` lives directly under `Arena` (layer 0, with `z_index` forcing it to draw last) rather than inside a separate `CanvasLayer` alongside the HUD-style telegraph label, on the theory that `SCREEN_TEXTURE` reads don't reliably cross a `CanvasLayer` boundary. This was fixed at the same time as the missing `hint_screen_texture` uniform declaration above, so the two fixes were never isolated from each other — treat "same canvas as the content" as the safe default for any future screen-reading shader, not as a confirmed, isolated Godot behavior
