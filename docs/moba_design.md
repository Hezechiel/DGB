# Divine Gestures: Babylon — MOBA Arena Design

> Living design document. Update this when decisions change.

---

## Concept

A landscape mobile MOBA where the player is a powerful hero fighting on a two-lane battlefield. The core tension is the constant choice between fighting personally on the field versus spending mana to deploy units and cast spells that advance the lanes. The match ends when one side's Command Post is destroyed.

Inspired by **Star Wars: Force Arena** — direct hero control combined with scroll-based unit deployment, designed for fast 3–5 minute sessions on mobile.

---

## What Makes This Different from Dota / League

In Dota and League, minions spawn automatically on a timer and lanes are fixed paths. Here:

- **Units only exist because a player actively deployed them.** Every unit on the field is a deliberate choice that cost mana. You always know why units are where they are.
- **Deployment position is chosen by the player**, not fixed to a lane entry point. You drop your unit where it makes tactical sense — within the constraints of spawn protection zones.
- **Protected territory shrinks dynamically** as turrets are destroyed. The deployment frontier advances with conquest.

---

## Match Flow

1. Player taps **Quick Play** — match begins immediately, no lobby
2. Both sides start with full mana and empty lanes
3. Players deploy units and spells, hero fights on the field
4. First side to destroy the enemy Command Post wins
5. Win/lose screen → back to main menu

Target match length: **3–5 minutes**.

---

## Battlefield Layout (landscape, 780 × 360 viewport)

Map world size: approximately **3500 × 900 px** (roughly 4–5 viewports wide, 2–3 viewports tall). The viewport shows one full lane height or half of each lane simultaneously depending on camera position.

```
╔══════════╦══════════════════════════════════════════════╦══════════╗
║  PLAYER  ║▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ TOP LANE ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓║  ENEMY   ║
║ COMMAND  ║                                              ║ COMMAND  ║
║   POST   ║          O P E N   F I E L D                ║   POST   ║
║  (base)  ║    (obstacles, maneuver space, retreats)     ║  (base)  ║
║          ║▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ BOT LANE ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓║          ║
╚══════════╩══════════════════════════════════════════════╩══════════╝
  (left)                                                    (right)
```

Units march **left-to-right** (player units) or **right-to-left** (enemy units) along their assigned lane. The hero moves freely across the entire map. Obstacles in the open field create pockets for retreating, flanking, and choke points.

The viewport does not show the whole map at once. The player pans the free camera to see different parts of the battlefield. The minimap provides full situational awareness at all times.

---

## Hero (Player Character)

The player controls Zeus directly via **tap-to-move**. The hero:

- Is the most powerful single unit on the field
- Has significantly more HP than any summoned unit
- Auto-attacks with priority (see Attack Priority below)
- Can move freely across the entire map
- Deploys units and spells by dragging scrolls from the HUD hand

The enemy AI controls its own **Enemy Hero** with mirrored capabilities.

### Attack Priority

The hero's auto-attack follows this priority order at all times:

1. **Selected target** — if the player has tapped an enemy directly, the hero attacks that enemy. If the selected target is out of attack range, the hero moves toward it until in range, then attacks. Cleared when the target dies or the player taps empty ground.
2. **Nearest enemy hero** — if no target is selected, the hero prefers to attack enemy heroes over regular units when one is within attack range.
3. **Nearest enemy unit** — fallback to the closest enemy of any type.

### Respawn

On death the hero enters a respawn timer, then reappears at the player Command Post.

| Death count | Respawn time |
|---|---|
| 1st | 3 seconds |
| Each additional | +N seconds (increment TBD during balancing) |
| Maximum | 10 seconds |

Exact scaling is a balancing decision — the system is built to accept `base_respawn`, `max_respawn`, and `increment` as exported values. While dead the hero is invisible, the timer is shown in the HUD.

---

## Summon System

### Mana

- Both sides have a **mana pool** (float, 0–10 range)
- Regenerates at a constant base rate over time
- Deploying units and casting spells costs mana
- **Event-based regen boosts:** certain battlefield events grant a temporary flat bonus to mana regen. The boost system (`ManaSystem.add_regen_boost(team, amount, duration)`) is built as a general mechanic; specific triggers are designed during gameplay development. Example trigger: killing the enemy hero → temporary regen boost.

Player mana is shown in the HUD. Enemy mana is **not shown** to the player.

### Scroll Hand (card hand)

The player has a **hand of 4 scrolls** displayed in the bottom HUD strip. Each scroll shows the unit or spell icon and its mana cost. Scrolls rotate from a deck after use (Clash Royale style).

### Deployment — Drag to Deploy

Deployment is done by **dragging a scroll from the hand onto the battlefield**, not by tapping to select and then tapping to place.

Drag gesture:
1. Player touches and holds a scroll in the HUD
2. Drags finger onto the battlefield — a placement marker appears under the finger showing the unit spawn point or spell drop area (visual design TBD)
3. Releasing the finger deploys the unit or spell at that position (if valid)
4. If the position is invalid (protected zone), the scroll returns to the hand with rejection feedback

Dragging a scroll **temporarily overrides the follow-cam setting** — even if the player has camera-follow locked onto the hero, the camera unlocks during the drag so they can reach any map position. Camera behaviour resumes after release.

### Spawn Protection Zones

Each turret projects a **spawn protection zone** around itself. Enemy units cannot be deployed inside a friendly turret's protection zone.

As turrets are destroyed, their protection zones are removed — the deployment frontier retreats. A player who destroys a turret gains the ability to deploy units deeper into enemy territory. This creates a natural territorial progression: early game the player can only deploy near their base; late game (after destroying turrets) they can deploy near the enemy Command Post.

The protected zones are represented in-game by a visual ground indicator (design TBD — could be a tinted ground overlay or a boundary ring visible during drag).

---

## Unit Types (planned)

All units are deployed from scrolls, march their assigned lane, and fight enemies in their path.

| Unit | Cost | Role | Notes |
|---|---|---|---|
| Soldier | 2 | Basic melee, marches lane | Default unit; current `human.tscn` evolves into this |
| Heavy | 4 | High HP tank, slow | Absorbs hits in front of ranged units |
| Ranged | 3 | Attacks from distance | Hangs behind melee, shoots over them |
| *(more TBD)* | | | Designed as gameplay develops |

All units: 32×32 sprite, team-colored health bar, `take_damage()` interface, registered with BattleManager.

---

## Spell Scrolls (planned)

Spells are deployed by the same drag gesture as units but have no persistent presence — they fire and disappear.

| Spell | Cost | Effect |
|---|---|---|
| Lightning Strike | 3 | AoE damage at drop position |
| Blessing | 2 | Heals all friendly units in a zone |
| Haste | 2 | Temporarily boosts speed of all friendly lane units |
| *(more TBD)* | | |

---

## Structures

### Command Post (base)

- Highest HP on the map
- Does not attack
- Always-visible prominent health bar
- When destroyed: `BattleManager.base_destroyed(team)` → match ends

### Turrets (lane defense)

- Implemented in `turret.gd` (armor, aggro drop, stun support, repair regen, taunt override)
- 4-stage damage visuals; no `queue_free()` — become wrecks
- Each turret owns a **spawn protection zone** disabled on destruction
- Guards its section of a lane; attacking through the lane requires either destroying the turret or sending the hero ahead to absorb shots

---

## Map & Obstacles

Map world size is 4–5 viewports wide × 2–3 viewports tall (approximately 3120–3900 px × 720–1080 px). The viewport shows roughly one lane height at a time.

The open field between the lanes contains **obstacles** — terrain features that create tactical depth:
- **Safe retreat pockets**: a hero can duck behind an obstacle to break line-of-sight and recover
- **Choke points**: narrow passages that funnel units into kill zones
- **Maneuver traps**: dead-end areas that punish greedy positioning

Obstacle design is deferred until the core loop is working. The TileMapLayer will encode them as physics-blocking tiles.

---

## Camera

The camera is a **free-panning** viewport by default. Dragging anywhere on the battlefield pans the view. The player uses the minimap for global awareness.

**Optional setting (toggle in game settings):** lock camera to follow the hero. When active, the camera always centers on the player character. Dragging a scroll from the hand temporarily overrides this lock during the drag.

Gesture disambiguation:
- Short tap on battlefield → move hero to that position
- Drag on battlefield → pan camera
- Drag starting from a scroll in the HUD → scroll deployment drag (different screen zone, no conflict)

---

## Minimap

A small always-visible overview of the full map, positioned in the top HUD strip. Gods are all-knowing — the minimap is not fogged.

Minimap shows:
- Both Command Posts and their health state (color-coded)
- All turrets (icon; grayed when destroyed)
- All units as colored dots (team color)
- Player hero position
- Enemy hero position — **marker glows** when the enemy hero has their ultimate ability ready

The minimap does **not** show enemy scroll hand or enemy mana — that information is hidden.

---

## HUD Layout (landscape, 780 × 360)

```
┌──────────────────────────────────────────────────────────────────┐
│[Minimap] [Hero HP bar] [Respawn timer]              [⏸ Pause]   │ ← top strip (~30px)
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│                      B A T T L E F I E L D                      │  ← scrollable viewport
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│[Mana ████░░░]  [Scroll 1][Scroll 2][Scroll 3][Scroll 4]         │ ← bottom strip (~50px)
└──────────────────────────────────────────────────────────────────┘
```

Enemy mana and enemy scroll hand are **not shown**. Enemy ultimate status is visible only via the minimap hero marker glow.

---

## Enemy AI (CpuOpponent)

The CPU opponent mirrors player mechanics exactly:
- Same `ManaSystem` pool and regen
- Same `SpawnSystem` protection zone rules
- Same `deploy()` function call

Decision logic (Easy prototype):
1. Accumulate mana
2. When mana ≥ cheapest available scroll → pick a scroll
3. Choose lane: weight toward the lane where the player has fewer active units
4. Pick a valid spawn position within the chosen lane (not in a player protection zone)
5. Call deploy

**Multiplayer readiness:** Replacing `CpuOpponent` with a network player requires only swapping the decision input. All game mechanics are identical.

---

## Roadmap (post health-bar, priority order)

1. **Allied units** — adapt `enemy.gd` for lane waypoint marching; add to `team_player` group
2. **Win / lose conditions** — Command Post structure, `base_destroyed` signal, outcome screen
3. **Lane system** — `LaneManager` autoload, waypoint arrays, `deploy(unit_type, lane, team, position)` 
4. **Mana system** — `ManaSystem` autoload, base regen, `add_regen_boost()`
5. **Spawn protection zones** — Area2D per turret, `SpawnSystem` autoload, `is_valid_position()`
6. **Scroll hand HUD** — 4 scroll slots, drag gesture, placement marker, rejection feedback
7. **Free camera** — standalone Camera2D in arena, drag-to-pan, optional hero follow, scroll-drag override
8. **Minimap** — overview map, unit/hero dots, ultimate glow indicator
9. **Enemy AI hero** — `EnemyHero` scene with AI movement
10. **CpuOpponent** — mana management and deploy decisions
11. **Respawn system** — death counter, scaling timer, HUD timer display
12. **Spell scrolls** — AoE and buff effects
13. **Map design** — two-lane arena with obstacles (deferred until core loop is solid)

---

## What Is Postponed (World Map)

The idle god-game World Map phase — villages, faith system, GodPresence hand, Tower of Babylon — is preserved in `scenes/world/` and documented in `docs/world_map_dev.md`. It remains the long-term meta layer vision but is not active development.
