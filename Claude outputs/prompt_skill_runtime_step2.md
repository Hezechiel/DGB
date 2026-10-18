# Claude Code prompt — God skill runtime, step 2 (knockback + Poseidon Tidal Wave)

**Use Plan Mode.** Read the files listed under CONTEXT, then present a plan
(files, functions, signatures, where each new block goes) and wait for
approval before editing anything.

## Goal

Step 1 (skill cooldown, HUD `SkillButton`, AI cast, `SkillEffects`, Zeus Chain
Lightning) has landed and works. This step adds:
1. A new status effect, **knockback**: a short forced move, stopped by
   obstacles. Added to units and both hero scripts.
2. **Poseidon's Tidal Wave** in `SkillEffects`: a cone in front of Poseidon
   that deals damage, slows, and knocks enemies back.
3. A placeholder cone visual.

When this lands, Poseidon gets a skill button, and the AI Poseidon (today's
TEMP opponent) starts casting it with no extra wiring.

## CONTEXT — read first

- `docs/architecture.md` §5 (status effects, attack windups, navigation),
  §6 (status effects are duplicated by design; a locked windup disables
  `_physics_process`; never set `NavigationAgent2D.target_position` every
  frame).
- `docs/heroes_greek.md` → "God skills — shared rules" and "Skill — Poseidon:
  Tidal Wave".
- `data/heroes/greek/skills/skill_poseidon_tidal_wave.tres` (values:
  `damage_pct` 180, `cone_angle` 90, `wave_range` 100, `knockback` 60,
  `slow_pct` 30, `slow_duration` 2; `cooldown` 22; `cast_range` is not set,
  so it uses the default 100).
- `scripts/arena/skills/skill_effects.gd` (`is_implemented`, `cast`,
  `is_alive`, `skill_damage`, `enemy_team_of`, `_chain_lightning`,
  `_spawn_chain_fx`), `scripts/arena/skills/chain_lightning_fx.gd` (the FX
  pattern to copy).
- `scripts/arena/unit.gd` (`_physics_process` stun early-return ~L204,
  `windup_left`, `_swing_target`, `_resolve_attack_hit()`, `_nav_goal`,
  `apply_stun/root/slow`).
- `scripts/arena/player.gd` and `scripts/arena/hero_dummy.gd`
  (`_physics_process` stun early-return, `_cancel_attack_windup()`,
  `apply_stun()`, `_nav_goal`, `is_dead`, `update_idle_animation()`).

## Design decisions (already made — implement exactly)

### Knockback status (duplicated in `unit.gd`, `player.gd`, `hero_dummy.gd`)

Same deliberate duplication as stun/root/slow; place it right next to them.

- State: `var knockback_left: float = 0.0`, `var knockback_velocity: Vector2`.
- `func apply_knockback(direction: Vector2, distance: float, duration: float) -> void`
  - Return if `is_dead`, or if `distance <= 0`.
  - `duration = maxf(duration, 0.05)`;
    `knockback_velocity = direction.normalized() * (distance / duration)`;
    `knockback_left = duration`. A new knockback **replaces** a running one.
  - `_nav_goal = Vector2.INF` (the old path is stale after a push).
  - **Heroes:** call `_cancel_attack_windup()` first. That's required, not
    cosmetic: a locked windup disables `_physics_process`, so without the
    cancel the push would never run.
  - **Units:** cancel a pending windup with no hit: `windup_left = 0.0`,
    `_swing_target = null`. `_resolve_attack_hit()` doesn't re-check range,
    so a pushed melee unit would otherwise land its hit from 60 px away.
    Leave `attack_left` (cooldown) unchanged.
- In `_physics_process`: after the existing timer decrements and **before**
  the stun early-return, add a knockback branch:
  - `knockback_left -= delta`, `velocity = knockback_velocity`,
    `move_and_slide()`, `update_idle_animation()`, then `return`.
  - When it reaches 0, set `velocity = Vector2.ZERO`.
  - Knockback ignores root and slow (it's a forced move) and still moves a
    stunned target. Obstacles, structures and the map border stop it via the
    existing `collision_mask = 4`.
- Accepted edge case: a hero pushed during its spawn animation
  (`_physics_process` is off) gets the remaining push once the spawn
  finishes. Don't add code for it.
- Turrets and bases get **no** knockback (no method → skipped by
  `has_method`). Don't touch `turret.gd` or `base.gd`.

### Tidal Wave (`SkillEffects`)

- Add `const TIDAL_WAVE := &"skill_poseidon_tidal_wave"`.
  `is_implemented()` returns true for both ids. `cast()` dispatches to
  `_tidal_wave(...)` with the same `if/elif` style.
- Cast target: the step 1 target pick is unchanged (`pick_cast_target`
  within `cast_range`). The target only sets the **cone direction**:
  `dir = (target.global_position - caster.global_position).normalized()`,
  falling back to `Vector2.RIGHT` if the length is ~0.
- Hits: every enemy from `BattleManager.get_targets_in_radius(caster_pos,
  wave_range, enemy_team)` that `is_alive()` and lies inside the cone:
  `dir.dot(to.normalized()) >= cos(deg_to_rad(cone_angle / 2.0))`, where
  `to = n.global_position - caster_pos`. A candidate with `to` ~0 always
  counts. Center-to-center, deterministic, no RNG.
- Per hit, in this order:
  1. `take_damage(skill_damage(attack_power, damage_pct))` — flat, no falloff.
  2. If still alive: `apply_slow(1.0 - slow_pct / 100.0, slow_duration)` if
     it has the method.
  3. If still alive: `apply_knockback(push_dir, knockback, knockback_time)`
     if it has the method. `push_dir` is radial from Poseidon
     (`to.normalized()`, or `dir` when `to` ~0).
- `knockback_time` is read as `skill.get_value(&"knockback_time", 0.2)`.
  Don't add the key to the `.tres`; the default is the first-pass value.
- Returns `true` even if only the primary target was hit. Always spawns the
  FX.
- `DebugLog.info("skill", ...)` in the same format as Chain Lightning
  (team, id, hits, damage).

### Placeholder FX — `scripts/arena/skills/tidal_wave_fx.gd`

`class_name TidalWaveFx`, `extends Node2D`, built in code like
`ChainLightningFx`:
- `setup(origin: Vector2, dir: Vector2, radius: float, angle_deg: float)`.
- `_draw()` fills the cone (sector polygon, ~16 arc points) in translucent
  sea blue `Color(0.3, 0.6, 1.0, 0.35)`, with a brighter arc edge
  `Color(0.7, 0.9, 1.0, 0.9)` about 2 px wide.
- Same `z_index = 50` and fade-then-`queue_free()` tween as
  `ChainLightningFx`, ~0.35 s.
- Spawned through a `_spawn_tidal_fx(...)` helper next to
  `_spawn_chain_fx`, under `BattleManager.arena_root` with
  `add_child.call_deferred`.

Code comments in the project's mixed Slovak/English style.

## Files

New:
- `scripts/arena/skills/tidal_wave_fx.gd`

Modified:
- `scripts/arena/skills/skill_effects.gd` — const, `is_implemented`,
  dispatch, `_tidal_wave`, `_spawn_tidal_fx`.
- `scripts/arena/unit.gd` — knockback state, `apply_knockback()`,
  `_physics_process` branch.
- `scripts/arena/player.gd` — same.
- `scripts/arena/hero_dummy.gd` — same.

## DO NOT TOUCH

- `_chain_lightning()`, `ChainLightningFx`, `pick_cast_target()`,
  `find_nearest_target()`, and the step 1 cooldown/cast code in both hero
  scripts (`can_cast_skill`, `try_cast_skill`, `_reset_skill_cooldown`, the
  `_process` tick).
- `scripts/arena/ui/skill_button.gd`, `HUD.gd`, `HUD.tscn`, `arena.gd`. The
  button already appears once `is_implemented()` is true.
- `turret.gd`, `base.gd`, `spell_zone.gd`, `BattleManager.gd`, `CardDB.gd`,
  every autoload.
- `skill_data.gd`, `hero_data.gd`, every `.tres` under `data/`.
- The existing `apply_stun/root/slow` bodies, the attack pipeline, and the
  navigation helpers (`_nav_direction_to`, `_steer_towards`) apart from
  resetting `_nav_goal`.
- `docs/*`, `CLAUDE.md`, `AGENTS.md`, `project.godot`.

## OUT OF SCOPE (do not build)

- A wave that travels over time (it resolves instantly, in one frame).
- Knockback from any other source (spells, units), knockback immunity, or
  diminishing returns.
- A Poseidon cast animation, sound, or art for the cone.
- Smarter AI aiming (e.g. aiming the cone at the biggest cluster). The AI
  keeps the step 1 rule.
- Off-navmesh correction after a push. The physical border and obstacles are
  the only guard; report if you see units stuck.
- Any other god's skill.

## VERIFY

Static checks (report results):
1. `grep -n "func apply_knockback" scripts/arena/*.gd` → exactly `unit.gd`,
   `player.gd`, `hero_dummy.gd`.
2. `grep -n "knockback_left > 0" scripts/arena/unit.gd scripts/arena/player.gd scripts/arena/hero_dummy.gd`
   → each sits **above** that file's `if stun_left > 0.0:` early-return in
   `_physics_process` (show line numbers).
3. `grep -n "_cancel_attack_windup" scripts/arena/player.gd scripts/arena/hero_dummy.gd`
   → also called from `apply_knockback`.
4. `grep -n "_swing_target = null\|windup_left = 0.0" scripts/arena/unit.gd`
   → present in `apply_knockback`.
5. `grep -n "TIDAL_WAVE\|CHAIN_LIGHTNING" scripts/arena/skills/skill_effects.gd`
   → both in `is_implemented()` and `cast()`.
6. `grep -rn "knockback_time" data/` → no matches (default stays in code).
7. `git diff --stat` → only the 4 modified files + 1 new file (and its `.uid`).

Runtime tests (I run these; list them in your summary):
1. Deck with **Poseidon** → Battle: skill button visible, grey, counting
   down from 22.
2. In front of a Phalanx squad: tap → blue cone appears; units in the cone
   take damage (F11 `[skill]` log), slide ~60 px away from Poseidon over
   ~0.2 s, then walk slowly (30 % slow) for 2 s. Units behind Poseidon are
   untouched.
3. A unit pushed into a rock/patch or the map border stops at it and
   doesn't pass through. After the push, units repath and resume marching
   (none stuck walking into a wall).
4. A melee unit pushed mid-swing doesn't land that hit (watch the
   Poseidon/god HP bar).
5. Enemy god in the cone mid-swing → swing cancelled, pushed, slowed.
6. A turret in the cone takes damage but doesn't move.
7. Opponent stays the TEMP **AI Poseidon**: it casts on its own once its
   cooldown ends with the player or units within 100 px, and the player
   hero gets pushed and slowed (`[skill] team=enemy`).
8. Zeus still works exactly as in step 1 (chain, stuns, cooldown 24).
9. Play a full match to the end → no errors when it ends mid-push or with
   the cone FX on screen.
