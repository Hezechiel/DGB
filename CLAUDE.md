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
Main scene: `scenes/menu/MainMenu.tscn` → (Battle) `scenes/ui/PreMatchFlow.tscn` → `scenes/arena/arena.tscn`. `PreMatchFlow` fills `MatchConfig` (heroes, decks, levels, map) from `PlayerProfile`; opening `arena.tscn` directly with F6 leaves those empty (known limitation — null-guarded, not a crash).

Export for Android: Project → Export → Android (Android SDK must be configured in Godot Editor Settings).

No test runner — validate by running in the Godot editor or via Android APK from GitHub Actions CI (push to main, download artifact).

Quick keyboard test shortcuts in arena (`arena.gd _input()`) — **debug builds only** (`OS.is_debug_build()` gate at the top of `_input()`; dead in release/Android export builds):
- **U** — 2× energy regen boost for the player, 5s (`EnergySystem.add_modifier(..., ModType.REGEN_MULT, 2.0, 5.0, &"debug_boost")`)
- **I** — -1 flat card cost for the player, 5s, "bloodlust" style (`ModType.COST_REDUCE`, tag `debug_bloodlust`)
- **Y** — prints current energy state for both teams: player/enemy energy, player regen rate, resolved cost of `card_greek_hoplite` (read-only, no mutation)
- **P** — calls `EnergySystem.try_spend("player", &"card_greek_hoplite")` and prints whether it succeeded
- **H** — deal 1/3 of `max_hp` to the player hero (debug trigger for death/respawn/card-lock/telegraph testing, since real combat death is slow to set up manually)
- **J** — plays `sword_hit` 10× in one frame at the player (audio `max_instances`/`min_interval` throttling test)

Profile debug keys in the main menu (`main_menu.gd _unhandled_key_input()`) — also **debug builds only**, and only through `PlayerProfile`'s public mutation API:
- **F9** — `PlayerProfile.reset_profile()` (back to the starter god + 7 starter cards at level 1)
- **F10** — `PlayerProfile.grant_cards()` with +1 copy of every obtainable card (`obtain_source != 0`) and every god
- **F11** — toggles `DebugLog.enabled` (the `[pack]` / `[profile]` / `[synergy]` / `[spawn]` diagnostics, off by default — see "Pure helpers" below)

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

The table is "what's actually on disk today," not a target to redraw toward (history: `docs/arch/battle_scene.md`).

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

Combat units (`scripts/arena/unit.gd`) compute their `Hurtbox`/`AttackRange`/`AggroRange` layers/masks at runtime from `team`, since `melee_unit.tscn`/`ranged_unit.tscn` are shared archetypes for both sides — see `docs/arch/combat_movement.md`.

---

## Not yet implemented

- Lane system — units and hero AI march straight at `BattleManager.get_nearest_structure()`, no waypoint paths (see `docs/arch/battle_scene.md`)
- Minimap tap-to-navigate (the minimap itself exists)

---

## Where to find details

System-by-system documentation lives in `docs/architecture.md` (principles, autoloads, index) and `docs/arch/*.md`; design intent lives in `docs/game_design.md`. **Read only the arch file relevant to the task, not all of them.**

- [docs/arch/data_layer.md](docs/arch/data_layer.md) — `.tres` layout, card/god/skill/map resources, collection fields, pure helpers, match manifest & synergy, `PlayerProfile`
- [docs/arch/battle_scene.md](docs/arch/battle_scene.md) — arena shell, map scenes, HUD, `BattleManager`/`EnergySystem`/`HealingSystem`, camera, card hand, enemy AI, respawn, win/lose
- [docs/arch/combat_movement.md](docs/arch/combat_movement.md) — unit/hero state machines, targeting, cast-point attacks, navigation, status effects, knockback, god skills, spells
- [docs/arch/conventions_pitfalls.md](docs/arch/conventions_pitfalls.md) — hard-won Godot pitfalls and project conventions
- [docs/arch/networking.md](docs/arch/networking.md) — networking posture and server seams
- [docs/arch/menu_ui.md](docs/arch/menu_ui.md) — main menu, tab pages, Deck screen, framed overlays, UI Theme, Card Detail
- [docs/arch/audio.md](docs/arch/audio.md) — `AudioManager`, buses, `SoundData`, SFX pool, end-of-match sequence

---

## Key Conventions

- **`call_deferred`** when `add_child` and `setup()` happen in the same frame
- **`take_damage(amount: int)`** — universal damage interface; all damageable nodes implement it
- **`distance_squared_to()`** everywhere for range checks (avoids sqrt)
- **Code-based signal connections** in `_ready()` — no Inspector wiring
- **`TextureButton` / `Button`** for in-game tappable HUD UI — GUI controls consume the touch, so a tap on them never falls through to `arena.gd`'s `_unhandled_input` tap-to-move
- **Health bar:** `health_bar.init(max_hp, team_name)` in `_ready()`; `health_bar.set_health(hp)` after every HP change; `health_bar.visible = false` on death
- **Turrets do not `queue_free()`** — `_on_destroyed()` disables physics, detection, and protection zone; leaves wreck visual
- **Animation names:** 4-dir: `"up" "down" "left" "right"`. 8-dir adds `"up_left" "up_right" "down_left" "down_right"`
- **Slovak/English mixed** in comments and variable names — preserve the developer's style
- **`always_visible = true`** on HealthBar for heroes and Command Posts/bases; `false` for units and turrets
- **Groups:** `"team_player"`, `"team_enemy"`, `"heroes"`, `"turrets"` — add heroes to both `"team_*"` and `"heroes"` for attack priority logic
- **Self-subscribing UI:** small, independent UI reactions to a `BattleManager` signal (respawn counters, card-lock, death telegraph) connect to it directly in their own `_ready()` rather than being wired/relayed through `arena.gd` or another consumer — keeps each piece a drop-in addition/removal with zero coupling to sibling UI
- **Screen-reading `canvas_item` shaders:** declare `SCREEN_TEXTURE` yourself (`hint_screen_texture`) and keep the shader in the same canvas as its content — details in `docs/arch/conventions_pitfalls.md`
- **No scenes/nodes/positions in "pure logic" autoloads** — `EnergySystem`, `HealingSystem`, `HeroAI` and `PlayerProfile` all deliberately hold zero scene-tree references, kept as pure state + math so they stay server-authoritative-ready for future multiplayer and easy to unit-reason about. Systems that need scene/position awareness (movement, spawning) stay in the node scripts that call into these autoloads, not inside them. The static helpers (`LevelCurve`, `PackRoller`, `DeckRules`, `DebugLog`) go one step further: no nodes **and** no autoload calls — everything comes in as arguments
- **Spawn messages stay `{card_id, position, team}`** — levels and synergy are looked up from the per-team match manifest in `BattleManager`, never passed per spawn (keeps the future network message minimal and cheat-resistant)
- **The player collection changes only through `PlayerProfile`'s mutation API** (`grant_cards`, `set_deck`, `upgrade_card`, `reset_profile`) — no UI or debug tool edits profile data directly; these become server calls later
- **Match-state UI gets a `configure()` from `arena.gd`** (`hud.minimap.configure_map()`, `hud.synergy_icon.configure()`); signal-driven pieces still self-subscribe
- **Diagnostics go through `DebugLog.info(tag, text)`**, not bare `print()` — off by default so the console stays clean. Plain `print` is reserved for direct answers to a debug key press. `push_warning` / `push_error` are for real problems and are never routed through `DebugLog`
