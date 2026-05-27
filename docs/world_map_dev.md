# Divine Gestures: Babylon
## World Map — Development Reference
> **Purpose:** Technical and design reference for the World Map phase of development.  
> Use this file to restore context in Claude Code or any new AI session.  
> Companion to: `project_brief.md`, `vision.md`, `core_loop.md`, `architecture.md`

---

## 1. CURRENT STATE OF CODEBASE

### What exists (arena prototype — keep as minigame foundation)
- `scenes/arena.tscn` — arena scene with TileMap, enemy spawner, mobile controls, pause/settings UI
- `scenes/player.tscn` — Zeus `CharacterBody2D`, 4-directional animated sprite, lightning bolt projectile
- `scenes/enemies/human.tscn` — enemy with seek + separation steering, attack area
- `scenes/enemy_spawner.gd` — wave-based spawner with edge spawning and anti-stack logic
- `scripts/InputRouter.gd` — autoload, routes joystick vectors (`move_vector`, `aim_vector`)
- `scripts/ui/` — settings overlay, credits overlay, audio slider, scrollable container
- `scenes/menu/MainMenu.tscn` — main menu with overlay system

### What the arena prototype becomes
The arena (`arena.tscn`) is **not the main game**. It will be repurposed later as a **minigame** triggered by in-world events (e.g. a village is under attack → player enters arena to defend). Architecture stays intact.

---

## 2. WORLD MAP — DESIGN DECISIONS

### Camera & Navigation
- **One large scrollable TileMap** — all villages, landmarks, and the Tower of Babylon visible on one map
- Player navigates by **finger drag — the world moves under the hand** (not a joystick or pan button)
- The grabbed world point stays under the finger for the duration of the drag (anchor-based pan)

### God Presence (Visual Layer Only)
- Player is represented by a **God Hand** (default) or **God Eye** depending on chosen deity
- The presence follows the finger with a **slight lag** (lerp smoothing) — feels weighted, divine
- Has idle animation when finger is lifted (float, breathe, subtle movement)
- Has state animations: `idle`, `hover`, `grab`, `cast`
- **No gameplay impact** — purely presentational, adds identity and immersion
- God signature (hand vs eye vs other) determined by god choice at game start
- Implementation: swap `SpriteFrames` resource on the same `GodPresence` node — no script changes needed per god type

### Faith & Distance
- The world is not neutral — villages with high faith are **power nodes**
- Spells cast near faithful villages: lower cost or higher effect
- Spells cast in faithless / distant territory: reduced power
- Visual feedback: faithful territory is warm/bright, faithless territory is desaturated/cold
- The God Presence itself subtly brightens near faith sources (modulate or shader)

### Tower of Babylon
- Visible from the start in the distance — creates immediate tension
- Babylon construction **progresses offline** while the player is away
- Player must spread faith and cast disruption spells to slow or sabotage construction
- Acts as the **main timer / loss condition** for the base map

---

## 3. WORLD MAP — SCENE STRUCTURE

```
scenes/world/
  WorldMap.tscn           ← main scene for this phase
  Village.tscn            ← instanced per village on the map
  GodPresence.tscn        ← the hand / eye visual layer
  BabylonTower.tscn       ← tower with construction progress state

scripts/world/
  world_map.gd            ← camera pan, input routing, scene coordinator
  world_camera.gd         ← anchor-drag camera logic
  god_presence.gd         ← presence follow, state machine, animations
  village.gd              ← faith/fear/prosperity state, spell receiver
  babylon_tower.gd        ← construction progress, disruption logic
  world_simulation.gd     ← autoload or Node, offline tick calculator
```

### WorldMap.tscn node tree
```
WorldMap (Node2D)
├── TileMapLayer              # terrain, landmarks (static)
├── LocationsLayer (Node2D)   # parent for all Village / BabylonTower instances
├── GodPresence               # instance of GodPresence.tscn
├── WorldCamera (Camera2D)    # controlled by world_camera.gd
└── HUD (CanvasLayer)
    ├── FaithCounter
    ├── BabylonProgressBar
    └── GestureCanvas         # touch draw layer for spell gestures
```

---

## 4. KEY SCRIPTS — DESIGN NOTES

### world_camera.gd
Anchor-drag pan. The world point under the finger on touch-down stays under the finger throughout the drag.

```gdscript
var _drag_anchor_world: Vector2

func _input(event):
    if event is InputEventScreenTouch:
        if event.pressed:
            _drag_anchor_world = to_global(event.position)  # world pos at touch
        # touch release: no action needed
    elif event is InputEventScreenDrag:
        var current_world = to_global(event.position)
        position -= current_world - _drag_anchor_world
```

Camera should have map bounds clamped so player cannot scroll beyond the TileMap extents.

### god_presence.gd
Follows finger with lerp lag. Decoupled from camera — operates in screen space.

```gdscript
var target_pos: Vector2
var smoothing: float = 8.0

enum State { IDLE, HOVER, GRAB, CAST }
var state: State = State.IDLE

func _process(delta):
    global_position = global_position.lerp(target_pos, smoothing * delta)
    # state drives AnimationPlayer
```

States are driven externally by `world_map.gd` based on what the finger is over and what gesture is being drawn.

### village.gd
Each village is self-contained. It receives spell events and manages its own state.

```gdscript
@export var village_name: String
var faith: float = 0.0       # 0.0 – 100.0
var fear: float = 0.0
var prosperity: float = 50.0

func receive_spell(spell_type: String) -> void:
    match spell_type:
        "rain":   prosperity += 10.0
        "bless":  faith += 15.0
        "smite":  fear += 20.0
    _clamp_values()
    _update_visuals()

func tick(delta_time: float) -> void:
    # called by WorldSimulation each game tick (online and offline catch-up)
    faith = max(faith - 0.5 * delta_time, 0.0)
```

### world_simulation.gd (Autoload)
Handles offline progress. On game load, calculates how much time passed and runs catch-up ticks.

```gdscript
func calculate_offline_progress(seconds_offline: float) -> void:
    var ticks = int(seconds_offline / TICK_INTERVAL)
    for village in get_all_villages():
        for i in ticks:
            village.tick(TICK_INTERVAL)
    BabylonTower.advance_construction(ticks * BABYLON_RATE)
```

---

## 5. SEASONAL MAPS — ARCHITECTURE NOTE

The main Babylon map is the **persistent base**. Seasonal maps (Underworld, Valhalla, etc.) are:
- Separate scenes: `scenes/seasonal/underworld/UnderworldMap.tscn` etc.
- Loaded via `change_scene_to_file()` — no dynamic loading needed at this scale
- Self-contained progression (collectibles, leaderboard entries) that does **not** affect base save
- Monetization hook: cosmetic collectibles, god skins, gesture trails — tied to seasonal completion
- Season parameters (duration, rewards) delivered via **Firebase Remote Config** (already in architecture.md)
- Base game save and seasonal save stored separately in JSON

---

## 6. DEVELOPMENT ORDER (World Map Phase)

Build in this sequence to always have something runnable:

1. **WorldMap scene skeleton** — TileMap with placeholder art, Camera2D, basic drag pan working
2. **GodPresence** — sprite following finger with lerp lag, idle float animation
3. **One Village** — placed on map, tappable, shows faith value as label
4. **One Spell** — hardcoded "bless" on tap, village faith increases, visual feedback
5. **Faith HUD** — total faith counter on CanvasLayer
6. **Babylon Tower** — placed on map, progress bar visible, ticks up over time
7. **WorldSimulation offline tick** — save timestamp on exit, catch-up on load
8. **Gesture system proof of concept** — draw circle → triggers bless (replaces tap)
9. **Faith/distance modifier** — spell power reduced by distance from nearest faithful village
10. **God Presence states** — grab / hover / cast animations tied to input

---

## 7. HOW TO USE THIS DOCUMENT

Paste the following at the start of a new Claude or Claude Code session to restore full context:

> "I am developing *Divine Gestures: Babylon* in Godot 4 / GDScript for Android.  
> The existing codebase has an arena prototype (arena.tscn) kept for future minigames.  
> I am now building the World Map phase. See attached: world_map_dev.md"

Then attach this file. Claude Code will have full architectural context without re-explaining.

---

*Last updated: World Map phase kickoff*
