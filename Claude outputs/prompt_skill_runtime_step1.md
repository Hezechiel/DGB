# Claude Code prompt — God skill runtime, step 1 (framework + Zeus Chain Lightning)

**Use Plan Mode.** Read the files listed under CONTEXT, then present a plan
(files, functions, signatures, scene changes) and wait for approval before
editing anything.

## Goal

Make god skills castable in a match, for the first time:
1. A skill cooldown on both hero scripts (local player and AI hero).
2. A HUD skill button for the local player (tap-to-fire).
3. The AI hero casts its skill too.
4. One shared place for skill effects, with **Zeus's Chain Lightning** as the
   only implemented effect in this step. Other gods' skills are recognised as
   "not implemented" and simply unavailable (no button, AI never casts).

Poseidon's Tidal Wave (knockback) is **step 2**, a separate prompt.

## CONTEXT — read first

- `docs/architecture.md` §1 (principles), §5 (combat, status effects, attack
  windup), §6 (pitfalls: locked windup disables `_physics_process`; HUD is
  ready before the manifest; HUD child `process_mode`; status effects are
  duplicated by design), §7 (networking).
- `docs/heroes_greek.md` → "God skills — shared rules" and "Skill — Zeus:
  Chain Lightning".
- `scripts/arena/skill_data.gd` (`SkillData`: `cooldown`, `cast_range`,
  `values`, `get_value()`), `scripts/arena/hero_data.gd` (`skill` field).
- `data/heroes/greek/skills/skill_zeus_chain_lightning.tres` (values:
  `damage_pct` 220, `falloff_pct` 20, `jump_range` 60, `jumps` 5, `stun` 0.4;
  `cooldown` 24, `cast_range` 120).
- `scripts/arena/player.gd`, `scripts/arena/hero_dummy.gd` (attack pipeline,
  `_cancel_attack_windup()`, `apply_stun()`, `die()`, `revive()`,
  `primary_target` / `auto_target`, `find_nearest_enemy()`).
- `scripts/arena/turret.gd` (`fire_left`, `fire_cooldown`, `apply_stun()`).
- `scripts/BattleManager.gd` (`get_targets_in_radius()`, `arena_root`,
  `is_match_over()`).
- `scripts/hud/HUD.gd`, `scenes/hud/HUD.tscn`, `scripts/arena/ui/synergy_icon.gd`
  (pattern for a placeholder HUD `Button` configured from `arena.gd`),
  `scripts/arena/arena.gd` (`_ready()` hero spawn + `hud.synergy_icon.configure()`).

## Design decisions (already made — implement exactly)

- **Skills start on cooldown.** At spawn and on every `revive()` the cooldown
  is set to the full `skill.cooldown`.
- **Cooldown ticks in `_process`, not `_physics_process`** — `_physics_process`
  is disabled during a locked attack windup and the spawn animation, and the
  skill cooldown must not pause for those. It does not tick while `is_dead`.
  It keeps ticking while stunned.
- **Cast is instant** (no skill windup, no skill animation in this step).
  Casting cancels a pending auto-attack windup via `_cancel_attack_windup()`
  first, then sets `last_direction` toward the target and updates the idle
  animation facing.
- **Cannot cast** when: no skill / skill not implemented, cooldown > 0,
  `is_dead`, `stun_left > 0`, `BattleManager.is_match_over()`, or no valid
  target within `cast_range`. A refused cast does **not** start the cooldown.
- **Target selection (tap-to-fire):**
  - Player: `primary_target` if alive and within `cast_range`; otherwise the
    nearest alive enemy within `cast_range`.
  - AI: the nearest alive enemy within `cast_range`.
  - "Within cast_range" = center-to-center `distance_squared_to()`.
  - Candidates come from `BattleManager.get_targets_in_radius(global_position,
    skill.cast_range, enemy_team)` (units, the enemy god, turrets; bases are
    not in that registry, so they're immune automatically).
  - "Alive" = `is_instance_valid(n)` and not (`"is_dead" in n and n.is_dead`)
    and not (`"hp" in n and n.hp <= 0`). Turret wrecks stay registered with
    `hp = 0`, so the hp check is required.
- **Attack Power** = the caster node's `projectile_damage` (already level-scaled
  in `configure()`). Skill damage = `maxi(1, roundi(AP * pct / 100.0))`.
- **Chain Lightning resolution** (all in one frame, deterministic, no RNG):
  1. Hit the chosen target.
  2. Then up to `jumps` more targets: each time pick the nearest alive enemy
     (same team filter) **not yet hit** within `jump_range` of the **last hit
     target's position**; stop early if none.
  3. Damage falls off **multiplicatively**: hit `i` (0-based) deals
     `AP * damage_pct/100 * (1 - falloff_pct/100)^i`, rounded, min 1.
     (220 % → 176 % → 141 % → …)
  4. Every target hit: `take_damage(dmg)`, then `apply_stun(stun)` if it has
     the method. Turrets additionally get their shot timer restarted through a
     **new** turret method `interrupt_shot()` (`fire_left = fire_cooldown`),
     called only by this skill — do not change `turret.apply_stun()` (the Stun
     spell must keep its current behaviour).
  5. Units' 0.4 s stun only pauses their windup (existing behaviour) — leave
     `unit.gd` alone.
- **Effects live in one shared place**, not duplicated per hero script:
  new `scripts/arena/skills/skill_effects.gd`, `class_name SkillEffects`,
  static functions only (no state, no nodes held — same spirit as `DeckRules`):
  - `static func is_implemented(skill: SkillData) -> bool`
  - `static func cast(skill: SkillData, caster: Node2D, caster_team: String,
    target: Node2D, attack_power: int) -> bool` — dispatches on `skill.id`
    with `if/elif` (`&"skill_zeus_chain_lightning"` → `_chain_lightning(...)`).
    Unknown id → `push_warning` once per id, return `false`.
  - Reads tuning only through `skill.get_value(&"…")`; never writes to the
    resource.
  - Shared alive-check / target-pick helpers live here too, and the hero
    scripts call them (so the target rules are written once).
- **Cooldown state and `try_cast_skill()` are duplicated** in `player.gd` and
  `hero_dummy.gd` (thin: a few vars + 2–3 functions), same deliberate
  duplication as the status effects — each script has its own insertion
  points. Suggested API on both:
  - `var skill: SkillData`, `var skill_cd_left: float`
  - `func get_skill_cooldown_left() -> float`, `func can_cast_skill() -> bool`
    (all conditions above, including a target existing)
  - `func try_cast_skill() -> bool` — picks the target, calls
    `SkillEffects.cast(...)`, starts the cooldown only on `true`.
  - `skill` is assigned in `configure()` from `data.skill`.
- **Placeholder visual:** new `scripts/arena/skills/chain_lightning_fx.gd`
  (`Node2D`, built in code, no scene file needed): `setup(points:
  PackedVector2Array)`, draws a jagged/straight polyline through caster →
  hit targets in `_draw()` (light blue/white, width ~2), fades over ~0.25 s,
  then `queue_free()`. Added under `BattleManager.arena_root` with
  `add_child.call_deferred`. Scene-owned, so no reset code.
- **HUD button:** new `scenes/arena/ui/SkillButton.tscn` +
  `scripts/arena/ui/skill_button.gd` (`class_name SkillButton`, `extends
  Button`), placeholder look built like `SynergyIcon` (round `StyleBoxFlat`,
  a centered `Label` child for name/seconds; no textures).
  - `configure(hero: Node)` called once from `arena.gd::_ready()` after
    `spawn_hero(... "player" ...)`, next to `hud.synergy_icon.configure()`.
    If the hero has no skill or `SkillEffects.is_implemented()` is false →
    `visible = false`.
  - `_process()` polls the hero: cooldown > 0 → grey, label shows
    `ceili(seconds)`; ready → gold, label shows the skill's `display_name`
    (or a short "READY"). `disabled = true` while the hero is dead.
    Guard with `is_instance_valid(hero)`.
  - `pressed` → `hero.try_cast_skill()`. It's a `Button`, so it consumes the
    tap and never reaches tap-to-move.
  - **`process_mode = PAUSABLE` (1)** — the HUD root is `WHEN_PAUSED`; a
    polling child that inherits it would freeze during play (§6 pitfall,
    same as `EnergyBar`).
  - Placement in `HUD.tscn`: anchored bottom-right, roughly
    `offset_left = -88, offset_top = -260, offset_right = -12,
    offset_bottom = -184` (above the energy bar, clear of `CardHand`, which
    covers anchors x 0.667–1.0, y 0.75–1.0). Report the final offsets; I'll
    fine-tune in the editor.
  - `HUD.gd`: add `@onready var skill_button: SkillButton = $SkillButton`.
- **AI rule (first pass, deliberately simple):** in `hero_dummy.gd`'s
  `_physics_process`, after the existing fire step: if `can_cast_skill()`,
  call `try_cast_skill()`. Applies in NORMAL and LOW_HP states. No cluster
  scoring, no reaction delay.
- **Debug:** `DebugLog.info("skill", ...)` on every successful cast (team,
  skill id, number of targets hit, damage list). No new debug keys.

## Files

New:
- `scripts/arena/skills/skill_effects.gd`
- `scripts/arena/skills/chain_lightning_fx.gd`
- `scripts/arena/ui/skill_button.gd`
- `scenes/arena/ui/SkillButton.tscn` (reference scripts by `path=` only —
  never invent a `uid`)

Modified:
- `scripts/arena/player.gd` — skill vars, `configure()` assigns `skill`,
  `_process` cooldown tick, `can_cast_skill()` / `try_cast_skill()` /
  `get_skill_cooldown_left()`, cooldown reset in `_ready()` path and `revive()`.
- `scripts/arena/hero_dummy.gd` — same, plus the AI cast call.
- `scripts/arena/turret.gd` — add `interrupt_shot()` only.
- `scripts/hud/HUD.gd`, `scenes/hud/HUD.tscn` — instance + onready.
- `scripts/arena/arena.gd` — one `hud.skill_button.configure(player_hero)` line.

Code comments in the project's mixed Slovak/English style (short Slovak
explanation, English where it helps).

## DO NOT TOUCH

- `scripts/arena/skill_data.gd`, `scripts/arena/hero_data.gd`, all `.tres`
  files under `data/` (no tuning changes, no new fields).
- `scripts/arena/unit.gd`, `scripts/arena/spell_zone.gd`, `scripts/CardDB.gd`,
  `scripts/EnergySystem.gd`, `scripts/HealingSystem.gd`, `scripts/HeroAI.gd`.
- `BattleManager.gd` — no new state, no new functions (it already has the
  query you need). If you believe it needs a change, stop and explain in the
  plan.
- `turret.apply_stun()`, the existing attack pipeline (`_perform_attack`,
  `_try_fire`, damage-point logic) beyond calling `_cancel_attack_windup()`.
- `scenes/menu/*`, `scripts/ui/*` (Card Detail already shows skills).
- `CLAUDE.md`, `AGENTS.md`, `docs/*` — I update docs myself.
- No new autoload, no edits to `project.godot`.

## OUT OF SCOPE (do not build)

- Poseidon's Tidal Wave, knockback, or any other god's effect.
- Skill windup / cast animation / skill sounds / art for the button.
- Cooldown reduction, level scaling of cooldowns, skill upgrades.
- Smarter AI (cluster scoring, saving the skill, retreat logic).
- Aiming by drag, range indicator, target highlight while the button is held.
- Networking messages (keep the `try_cast_skill()` → `SkillEffects.cast()`
  split so a future network handler can call the cast with a given target).

## VERIFY

Static checks (report results):
1. `grep -rn "SkillEffects" scripts/` → used in `player.gd`, `hero_dummy.gd`,
   `skill_button.gd`, defined only in `skills/skill_effects.gd`.
2. `grep -n "interrupt_shot" scripts/arena/turret.gd scripts/arena/skills/skill_effects.gd`
   → defined in turret, called only from skill_effects.
3. `grep -n "func apply_stun" -A4 scripts/arena/turret.gd` → unchanged.
4. `grep -rn "values\[\|values\.\(set\|erase\)\|\.cooldown *=" scripts/arena/skills/`
   → no writes to `SkillData`.
5. `grep -n "process_mode" scenes/hud/HUD.tscn` → `SkillButton` has
   `process_mode = 1`.
6. `grep -rn "uid=\"uid://" scenes/arena/ui/SkillButton.tscn` → only uids
   copied from existing `.uid` files, none invented (path-only is fine).
7. No changes under `data/`, `docs/`, `scripts/ui/`, `unit.gd`,
   `spell_zone.gd`, `BattleManager.gd` (`git status` / diff list).

Runtime tests (I run these; list them in your summary):
1. Main menu → deck with **Zeus** as active god → Battle. Skill button
   visible, grey, counting down from 24; it does **not** start ready.
2. Pause during the countdown → the number stops; resume → continues.
3. When ready (gold) with no enemy within 120 px → tap does nothing, no
   cooldown starts, no tap-to-move happens behind the button.
4. Near a squad (Phalanx): tap → a line arcs through up to 6 targets, damage
   drops per jump (check `[skill]` log with F11 DebugLog on), units visibly
   freeze for ~0.4 s, button goes grey from 24.
5. Cast on the enemy god mid-swing → its swing is cancelled (no damage
   lands from that swing).
6. Cast with a turret as `primary_target` within range → turret takes damage
   and its next shot is delayed by a full `fire_cooldown`. A destroyed
   turret (wreck) is never hit or chained to.
7. Die and respawn as Zeus → cooldown restarts at 24 after revive.
8. Deck with **Poseidon** as active god → no skill button, no errors (one
   "not implemented" warning at most).
9. AI: temporarily set `MatchConfig.opponent_hero_id = &"hero_zeus"` in
   `prematch_flow.gd` (I revert it) → enemy Zeus casts on its own after
   ~24 s when the player or units are within 120 px; `[skill] team=enemy` log.
10. Play a full match to the end sequence → no errors when the match ends
    while the skill is ready or a chain fx is on screen.
