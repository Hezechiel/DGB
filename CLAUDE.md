# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Identity

**Divine Gestures: Babylon** — a mobile-first god game built in Godot 4.6 (GDScript) targeting Android. The player never directly controls units; all interaction is indirect and divine (faith, spells, gestures). The existing codebase is an arena prototype that will be kept as a minigame foundation; the active development phase is the **World Map**.

## Running the Project

There is no CLI build step. Open the project in **Godot 4.6** and press F5 (run main scene) or F6 (run current scene). The main scene is `scenes/menu/MainMenu.tscn`.

To export for Android: Project → Export → Android (requires Android SDK configured in Godot Editor Settings).

There is no test runner — validation is done by running the game in the editor.

## Architecture

### Autoloads (globals available everywhere)
- `Music` (`scenes/music.tscn`) — background music player
- `InputR` (`scripts/InputRouter.gd`, class `InputRouter`) — shared state for mobile joystick vectors: `move_vector: Vector2`, `aim_vector: Vector2`, `attack_pressed: bool`. Joystick controls write here; `player.gd` reads here. All mobile input flows through this singleton.

### Scene Flow
`MainMenu.tscn` → `arena.tscn` (the arena minigame). The next phase adds `scenes/world/WorldMap.tscn` as the true main scene.

### Arena Prototype (current playable state)
- `scenes/arena.tscn` — root scene: TileMap, player, enemy spawner, mobile controls, pause/settings UI. `scripts/game.gd` coordinates pause and scene transitions.
- `scenes/player.tscn` / `scripts/player.gd` — Zeus `CharacterBody2D`. Movement and aiming are **hybrid**: keyboard/gamepad via Godot Input Map, or mobile via `InputR`. Fires `LightningBolt` projectiles toward the aim direction.
- `scenes/enemies/human.tscn` / `scripts/human.gd` — enemy using seek + separation steering. Holds a reference to `enemy_manager` (the spawner) to iterate nearby enemies for separation. Receives damage via `take_damage(amount)`.
- `scripts/enemy_spawner.gd` — wave-based spawner. Spawns enemies on the arena edge, respects min distance from player and between enemies. Maintains `enemies: Array[Node2D]` used by `human.gd` for separation.
- `scenes/projectiles/LightningBolt.tscn` / `scripts/lightning_bolt.gd` — `Area2D` projectile. Initialized via `setup(start_pos, dir)` called deferred after `add_child`.

### Mobile Controls
- `scenes/MobileControls.tscn` — two `Joystick` controls (MOVE and AIM type) plus a pause button.
- `scripts/joystick.gd` — reads touch/drag events, clamps to radius, writes normalized vector to `InputR.move_vector` or `InputR.aim_vector` depending on `joystick_type` export.

### UI Overlay Pattern
`SettingsOverlay` and `CreditsOverlay` are reusable `Control` nodes with `open()` / `close()` methods and a `close_requested` signal. They're embedded in both `MainMenu.tscn` and `arena.tscn`. The parent scene hides/shows other UI elements and manages pause state in response to the signal.

### World Map Phase (next — not yet implemented)
Planned structure under `scenes/world/` and `scripts/world/`. Key design decisions:
- Camera pan is **anchor-drag**: the world point under the finger on touch-down stays under the finger throughout the drag (see `world_camera.gd` pattern in `docs/world_map_dev.md`).
- `GodPresence` node follows the finger with lerp lag — purely visual, no gameplay effect.
- `Village` nodes are self-contained: they hold `faith`, `fear`, `prosperity` floats and receive spells via `receive_spell(spell_type)`.
- `WorldSimulation` autoload calculates offline catch-up ticks on load using a saved timestamp.
- The arena (`arena.tscn`) is **not replaced** — it becomes a minigame triggered by world events.

## Key Conventions

- **`call_deferred`** is used when adding children and calling setup on them in the same frame (see `player.gd:fire_bolt`, `enemy_spawner.gd:spawn_one_enemy`).
- Damage flows through `take_damage(amount: int)` — both `player.gd` and `human.gd` implement this method.
- 4-directional animation names: `"up"`, `"down"`, `"left"`, `"right"`. LightningBolt uses 8-directional: adds `"up_left"`, `"up_right"`, `"down_left"`, `"down_right"`.
- Comments and variable names are mixed Slovak/English (the developer writes in Slovak). Preserve this style.
- Viewport: 1080×640, `canvas_items` stretch, `expand` aspect — designed to scale to mobile screens.
