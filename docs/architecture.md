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
  wave spawner, future AI, and future network handlers are all just callers.
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
| `MatchConfig` | Placeholder holder for pre-match display data (rank, map, both players' name/faction). Populated by `setup_placeholder_match()` today; matchmaking later. Display-only, never networked. |
| `InputR` | Input routing (tap-to-move targets, gesture state). |
| `Settings` | Persistent user settings. |
| `Music` | Audio. |

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
```

Resolution chain for a played card:
`card_id → CardDB.get_card() → CardData.unit_data → archetype_scene.instantiate()
→ configure(data, team) → add to arena`.

A card with `unit_count > 1` summons a squad: `BattleManager.spawn_unit()` returns
`Array[Node]` and places each unit with a **deterministic** ring offset
(`_formation_offset()`, no RNG) so both clients derive an identical formation from
the same `{card_id, position, team}` message. Squad size lives on `CardData`, not
`UnitData`: one unit archetype can back both a single-unit and a squad card.

---

## 4. Battle scene structure

- `scenes/arena/arena.tscn` — battlefield root; two horizontal lanes; per team:
  Base + 3 turrets (Top, Bot, Base). Structures self-register with BattleManager;
  destroyed structures become wrecks (**no `queue_free()`**).
- `scenes/arena/units/melee_unit.tscn` — the one melee archetype
  (CharacterBody2D + Hurtbox + AttackRange + AggroRange + AnimatedSprite2D +
  HealthBar + TargetMarker). Ranged/siege archetypes will be siblings.
- `scenes/arena/player.tscn` — locally-controlled hero.
  `scenes/arena/hero_dummy.tscn` — uncontrolled avatar placeholder (future AI).
  Both expose `configure(data, team)`, `die()`, `revive()`.
- `scenes/arena/spawner.tscn` — temporary wave "bot": plays test cards on a timer
  through `BattleManager.spawn_unit()`. Will become/get replaced by the AI opponent.
- `scenes/arena/DeployGhost.tscn` (`deploy_ghost.gd`) — world-space drag-to-deploy
  preview: a translucent circle at the drop position, green = legal, red = not.
  Drawn in `_draw()` (no assets). Sibling of `MoveMarker`, driven by `arena.gd`
  from `CardHand` signals (CardHand is in a CanvasLayer; the ghost is world-space).
- `scenes/arena/ui/EnergyBar.tscn` (`energy_bar.gd`) — player energy bar in the
  HUD. Polls `EnergySystem.get_energy("player")` each frame for the fill; updates
  the count label from `energy_int_changed`. Placeholder geometry (ProgressBar +
  ColorRect) pending art; `bar` is typed `Range` so a `TextureProgressBar` swap
  needs no script change.
- `scenes/hud/HUD.tscn` (CanvasLayer) — TouchScreenButtons (pause, recenter),
  `CardHand` (hand + draw cycle in `card_hand.gd`; `play_card(slot_index, world_pos)`
  is the single card-play entry point — drag-to-deploy calls it today, future
  double-tap and the network handler call the same function; emits
  `deploy_preview_updated` / `deploy_preview_ended` for `arena.gd` to drive the
  DeployGhost), `EnergyBar`, `MatchInfoBar` (timer label, tower icons, two
  `RespawnCounter`s driven by BattleManager signals).
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
- Authority model (dedicated server vs. relay/P2P) is an open decision with real
  cost implications — treat as its own project phase.
