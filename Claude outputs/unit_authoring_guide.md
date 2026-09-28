# Divine Gestures: Babylon — Unit Authoring Guide

> Companion to `architecture.md`, `hero_authoring_guide.md`, and
> `map_authoring_guide.md` (same project, sibling pipelines). Read
> `architecture.md`'s data-layer section (§3) and combat model (§5) first
> if you haven't touched the unit pipeline before — this doc is the
> step-by-step checklist for adding a new summonable unit (melee or
> ranged), not the explanation of why it's built this way. Update this
> file whenever the unit pipeline itself changes, the same as
> `hero_authoring_guide.md`.

---

## 1. What a unit actually is — and how it differs from the hero pattern

Like heroes, units split identity from behavior — but the split lands in
a different place. There are two archetype scenes today:

- **`scenes/arena/units/melee_unit.tscn`**
- **`scenes/arena/units/ranged_unit.tscn`** (added Sept 2026)

**Both attach the exact same script, `scripts/arena/unit.gd`.** Unlike
heroes — where `player.tscn`/`hero_dummy.tscn` differ because *control
source* (player input vs. AI) genuinely changes the movement pipeline —
melee and ranged units share identical movement/targeting/state-machine
code. The two scenes exist only because their `AnimatedSprite2D` scale and
collision-shape sizing differ per archetype's art, not because their
combat *behavior* differs at the script level. Combat behavior (melee
contact damage vs. a fired projectile) is a **data branch** inside
`unit.gd`, driven by `UnitData.attack_type` — not a script fork. If you're
tempted to make a third archetype scene for a new attack *type* (siege,
AoE, whatever), stop and check `unit.gd` first: a new `attack_type` enum
value and a branch in `_resolve_attack_hit()` is very likely the right
shape, not a third `.tscn` + a duplicated script. A genuinely new
*movement* pipeline (flying, teleporting, a siege unit that ignores
`AggroRange`) is a different question and might justify a real fork —
same judgment call `architecture.md` §6 already documents for why
`unit.gd`/`player.gd`/`hero_dummy.gd` stay separate scripts.

A unit's actual identity — stats, art, attack type, sounds — lives in:

- **`data/units/<id>.tres`** — a `UnitData` resource
  (`scripts/arena/unit_data.gd`): `id`, `display_name`, `archetype_scene`,
  `max_hp`, `damage`, `attack_cooldown`, `speed`, `target_filter`,
  `sprite_frames`, and (Sept 2026) `attack_type`, `attack_range`,
  `projectile_scene`, `damage_point_ratio`, `attack_sfx`, `death_sfx`.

At boot, `CardDB` scans `data/units/*.tres` into an id-keyed dictionary,
same pattern as `data/heroes/`. A unit is never spawned on its own,
though — it's always reached through a card: `CardData.unit_data` points
at the `UnitData`, and `BattleManager.spawn_unit()` (called from
`play_card()`) instantiates `unit_data.archetype_scene` and calls
`configure(data, team)`, which copies every stat onto the node —
including, same as the hero footgun below, **overwriting**
`$AnimatedSprite2D.sprite_frames` and resizing
`$AttackRange/CollisionShape2D.shape.radius` from the data resource. A
`CardData` with `unit_count > 1` spawns a squad of the identical
`UnitData` at deterministic ring offsets (`architecture.md` §3) — there is
no per-unit-in-squad variance.

### The footgun this causes (same shape as the hero one)

`melee_unit.tscn` and `ranged_unit.tscn` each have their *own*
`AnimatedSprite2D.sprite_frames` and `AttackRange/CollisionShape2D.shape`
radius set directly in the Inspector. Exactly like `player.tscn`/
`hero_dummy.tscn` (`hero_authoring_guide.md` §1), these are **only**
design-time/editor-preview defaults and crash-prevention fallbacks —
`configure()` always overwrites both from the spawned unit's `UnitData`.
Editing a unit's look or reach in the Inspector on either scene does
nothing for gameplay; the only place that matters is the `UnitData` .tres
the card actually points at. The scene-level values must still always
point at *something* valid (a real `SpriteFrames`, a non-zero radius on a
shape marked `resource_local_to_scene = true`) so the editor preview and
`scene.instantiate()` itself don't break before `configure()` gets a
chance to fix them up.

---

## 2. Checklist

### 2.1 Sprite art & the frames resource

`SpriteFrames` resources live at `data/units/frames/frames_<id>.tres`
(e.g. `frames_greek_hoplite.tres`, `frames_greek_toxotes.tres`) — same
`AtlasTexture`-region assembly as hero frames
(`hero_authoring_guide.md` §2.1), easiest authored by duplicating an
existing one in the Godot editor.

**Required animation names** — note these are **plain names, no `_left`
suffix and no per-direction convention** the way heroes work.
`update_idle_animation()`/`update_animation()` in `unit.gd` flip `flip_h`
based on movement direction but always play the *same* clip name
regardless of direction (`"idle"` for both idle and — currently, see the
known-gaps note below — movement too):

| Name | Used for | Notes |
|---|---|---|
| `idle` | Standing still and (today, due to a pre-existing bug — see §3) also movement | No `_left` suffix, unlike heroes' `iddle_left`. |
| `walk` | Authored and present on both existing units' frames, but not actually played by `update_animation()` today | See §3 — not part of the ranged-unit work, flagged for awareness only. |
| `attack` | Plays during the windup (§2.2) | Its length, same as heroes' `attack_left`, directly drives how long the unit is committed to a swing. No `_left` suffix. |
| `death` | Plays on death via `queue_free()` (no respawn — see §3) | No "spawn" clip exists for units at all; unlike heroes, a killed unit is gone for good, not respawned. |

There is no `spawn` animation slot for units — heroes respawn, units
don't (`take_damage()` calls `queue_free()` directly on death, no
`is_dead`/`die()`/`revive()` cycle).

### 2.2 The attack windup system — read this before tuning a new attack clip

Every unit's attack runs through the same `_process_engaging()` /
`_start_attack_windup()` / `_resolve_attack_hit()` logic in `unit.gd`,
shared identically by melee and ranged units (§1) — the only thing that
differs is `UnitData.attack_type`. This deliberately mirrors, but
simplifies, the hero cast-point system in `hero_authoring_guide.md` §2.2:

- On entering `ENGAGING` (already in `AttackRange`, `attack_cooldown`
  timer at 0), the unit starts a windup: it plays `"attack"` and counts
  down `windup_left`, initialized to `damage_point_ratio` (0.0-1.0,
  default `0.7`, same semantics as `HeroData`) times the live-derived
  duration of the `"attack"` clip (`frame_count / speed`, never
  hardcoded — same promise as heroes' cast-point).
- When `windup_left` reaches 0, the hit resolves: `MELEE` does a direct,
  liveness-rechecked `take_damage()` (the target may have died or been
  removed during the windup — re-checked via the existing
  `_is_target_alive()` helper); `RANGED` spawns `projectile_scene` via
  `fire_bolt()`, the same target-homing `projectile.tscn` heroes already
  fire (no group/collision logic in that projectile — it just homes
  in on the specific `Node2D` target it was given and calls
  `take_damage()` on arrival). `attack_sfx` plays right here, once, for
  both types (§2.6) — and not at all if the target already died.
- `attack_cooldown` (unchanged field name) starts counting from **this**
  point, playing exactly the role `HeroData.recovery_time` plays for
  heroes — **not** from the end of the full `"attack"` clip. Whatever's
  left of the animation after the hit is purely cosmetic.

**This is intentionally simpler than the hero system in two ways — don't
"upgrade" it to match heroes without a real reason:**

1. **No cancel-on-new-command.** Heroes can have an in-progress swing
   interrupted by a new tap-to-move, a new tap-target, or (AI heroes) an
   HP-retreat flip — because those are all things a controller (player or
   `HeroAI`) actively decides mid-swing. Units have no controller in that
   sense: their targeting is a first-contact-wins reactive state machine
   (`MARCHING → CHASING → ENGAGING`), not a stream of commands. If a
   target flees `attack_range` mid-windup, the state machine drops out of
   `ENGAGING` into `CHASING` on its own next frame — the pending windup is
   silently abandoned (no hit, no cancel-animation snap). That's a
   side-effect of code that already existed, not a built interrupt
   system, and it's a deliberate choice, not a gap to fill in.
2. **A plain timer, not an `await` coroutine.** `windup_left` just
   decrements inside `_physics_process`, the same way `attack_cooldown`/
   `stun_left`/`root_left` already do in this file. `unit.gd` had no async
   patterns before this and gains none from it. The payoff: a stun landing
   mid-windup is handled entirely by the *pre-existing* freeze-and-resume
   behavior (`architecture.md` §6) — `_physics_process` already
   early-returns above everything when `stun_left > 0.0`, so
   `windup_left` simply stops ticking and resumes correctly with no
   special-case code. Heroes needed a direct `apply_stun()` → cancel hook
   specifically *because* their windup disables `_physics_process`
   entirely during the lock; units' windup does not, so they don't need
   that hook and shouldn't get one added "for consistency."

`damage_point_ratio` is the same per-unit feel knob heroes get: lower
(~0.3-0.5) for a unit that should feel snappy/hard to punish mid-swing,
higher (~0.8-1.0) for one that should feel committed and interruptible-by-
circumstance (fleeing out of its own attack_range) but not by anything
else, since nothing else can interrupt it here anyway.

### 2.3 Create `data/units/<id>.tres`

Easiest path: duplicate an existing unit `.tres`
(`greek_hoplite.tres` for melee, `greek_toxotes.tres` for ranged) rather
than building from scratch. `UnitData` fields
(`scripts/arena/unit_data.gd`):

| Field | Guidance |
|---|---|
| `id` | Must be globally unique and should actually match the unit's identity — `CardDB` push_errors on a duplicate, but does **not** catch a stale/misleading id like the `melee_test_a`/`melee_test_b` leftovers this project had before the Sept 2026 rename. Keep it in sync with `display_name` by hand. |
| `display_name` | Player-facing name. |
| `archetype_scene` | `melee_unit.tscn` or `ranged_unit.tscn` — this is what actually decides which scene spawns; it does NOT need to match `attack_type` by any enforced rule (nothing stops you pointing a MELEE `UnitData` at `ranged_unit.tscn`), so double-check these agree by hand. There is no validation guard for this mismatch today (see §3). |
| `max_hp` / `damage` / `attack_cooldown` / `speed` / `target_filter` | Optional — omit to fall back to `UnitData`'s own `@export` defaults (`50` / `10` / `1.2` / `35.0` / `0` = `TargetFilter.ALL`). `damage` is used for both MELEE's direct hit and RANGED's projectile damage — one stat, dual use, same as heroes' single `projectile_damage` field covering both attack types. |
| `attack_type` | `MELEE` (default) or `RANGED`. See §2.2. |
| `attack_range` | Optional, defaults to `16.0` (melee reach). Set explicitly for a RANGED unit — `90.0` was the Sept 2026 starting value for `greek_toxotes`, tune by feel. This resizes `$AttackRange/CollisionShape2D.shape.radius` at spawn (§1's footgun) — the scene's own baked radius is irrelevant once this is set. |
| `projectile_scene` | Only meaningful when `attack_type = RANGED`. Reuse `scenes/arena/projectiles/projectile.tscn` unless this unit needs a bespoke bolt — same guidance as `HeroData.projectile_scene`. |
| `damage_point_ratio` | Optional, defaults to `0.7`. See §2.2's feel guidance. |
| `attack_sfx` / `death_sfx` | `SoundData` ids, empty = silent. See §2.6. |
| `sprite_frames` | Points at the `.tres` from §2.1. |

### 2.4 Wire it into a card

Units are never spawned directly — always through a `CardData`
(`data/cards/<id>.tres`, `scripts/arena/ui/card_data.gd`) whose
`unit_data` field points at the `UnitData` from §2.3. `unit_count > 1`
summons a squad of that same `UnitData` (`architecture.md` §3) —
`formation_radius` controls spacing, not per-unit variance. There is no
"which archetype scene" decision at the card level at all — that's fully
resolved by `UnitData.archetype_scene` from §2.3, the card only ever sees
`UnitData`.

### 2.5 AI behavior — nothing to configure per-unit

`unit.gd`'s `MARCHING → CHASING → ENGAGING` state machine (march toward
nearest enemy structure, chase an aggroed enemy, engage in range) is
entirely generic and reads the same `UnitData` stats every unit gets —
melee or ranged, any team. A new unit behaves identically to every other
unit, AI-wise, the moment its `UnitData`/`CardData` exist; there's no
per-unit AI hook the way heroes have `HeroAI`'s HP-hysteresis.

### 2.6 Sounds (Sept 2026)

Two `StringName` ids on `UnitData`, each a `SoundData` in `data/sounds/`
(`audio_authoring_guide.md` has the full how-to):

| Field | When | Guidance |
|---|---|---|
| `attack_sfx` | In `_resolve_attack_hit()` — melee: the hit landing; ranged: the projectile release. Positional. | Reuse the shared ids unless the unit really sounds different: `sword_hit` (melee), `arrow_shot` (bow). These are **LOW** priority with `max_instances = 3` and `min_interval = 0.05` — that's what keeps a 10-unit brawl from turning into noise, and lets hero sounds win. A new unit-type sound should follow the same settings. |
| `death_sfx` | In `die()`, positional | `unit_death` (LOW, `max_instances = 2`) for all current units. |

Current wiring: hoplite = `sword_hit` / `unit_death`; toxotes and
gastraphetes = `arrow_shot` / `unit_death` (a crossbow sound for the
gastraphetes is on the missing-audio list). Adding **variants** to a
shared sound (e.g. `unit_death_02.wav`) is just another file in that
`SoundData`'s `streams` — no unit edit needed.

---

## 3. Known gaps

- **No validation that `archetype_scene` and `attack_type` agree.**
  Nothing stops a `UnitData` with `attack_type = RANGED` pointing
  `archetype_scene` at `melee_unit.tscn` (or vice versa) — it would still
  spawn and "work" (the attack-resolution branch in `unit.gd` is driven
  purely by `attack_type`, independent of which scene it's running in),
  it would just look wrong (a melee-sized unit firing projectiles from
  point-blank, or an archer-scaled unit only ever landing melee hits at
  its small default `attack_range`). This is exactly the bug the archer
  cards had before the Sept 2026 fix (`greek_toxotes.tres` pointed at
  `melee_unit.tscn`). Check both fields by eye when authoring a unit —
  no automated guard exists yet.
- **`update_animation()` never actually plays `"walk"`.** All four
  direction branches in `unit.gd`'s `update_animation()` call
  `sprite.play("idle")` — a pre-existing bug, not touched by the Sept 2026
  ranged-unit work despite both existing units' frames already defining a
  real `"walk"` clip. Units currently appear to stand idle while marching.
  Flagged for awareness; fix is a separate, small, explicitly scoped
  future step.
- **No unit-specific status-effect divergence, unlike heroes.**
  `unit.gd`'s `apply_stun()`/`apply_root()`/`apply_slow()` are unchanged
  by the windup work (§2.2) — units get correct stun-pauses-windup
  behavior "for free" from the pre-existing freeze-and-resume pattern, so
  there was no reason to add a hero-style direct-cancel call here. Don't
  add one without a concrete reason — see `architecture.md` §6.
- **No siege/structure-only ranged unit exists yet**, though
  `TargetFilter.STRUCTURES_ONLY` already exists on `UnitData` for exactly
  this — combining it with `attack_type = RANGED` and a large
  `attack_range` should already work mechanically, just untested as of
  this writing.
- **Units never respawn** (`take_damage()` → `queue_free()` directly) —
  unlike heroes, there is no death/respawn cycle to author animations or
  timing for. Don't look for a `spawn` clip slot; there isn't one.
- **No deploy sound and no projectile-impact sound yet** — playing a card
  and an arrow landing are both silent. Needs assets *and* a hook (deploy
  would belong in `BattleManager.spawn_unit()`'s caller side / the unit's
  `_ready()`, never inside the autoload itself — `architecture.md` §9).

---

## 4. Verification checklist for a newly authored unit

1. `CardDB` boots without a `push_error` (duplicate id, missing/failed
   resource) — check the console on first run after adding the unit.
2. Play the card that summons it: confirm it spawns via the correct
   archetype scene (visually — right scale/collision feel for melee vs.
   ranged) and that `attack_type`/`archetype_scene` actually agree (§3).
3. Standing still shows `"idle"`; moving shows... currently also
   `"idle"` (§3's known bug) — don't treat this as a regression you
   introduced.
4. Attack timing: the unit stops and winds up (playing `"attack"`) only
   once `hurtbox_in_range` is set (i.e. at its configured `attack_range`,
   not before); the hit lands at `damage_point_ratio` of the `"attack"`
   clip's live duration — MELEE deals direct damage only if the target is
   still alive/present, RANGED spawns a projectile that homes in and
   applies damage on arrival. The unit can attack again roughly
   `attack_cooldown` seconds after the hit, not after the full animation.
5. Stun mid-windup: stun the unit while `windup_left > 0` — it should
   freeze in place and resume the *same* windup afterward (not restart,
   not skip), consistent with the existing freeze-and-resume stun pattern.
6. Target-flees-mid-windup: let the target escape `attack_range` before
   the windup completes — confirm no damage lands, no sound plays, no
   console errors, and the unit transitions to `CHASING` cleanly.
7. Death: `take_damage()` at 0 HP frees the node — confirm the `"death"`
   clip is at least attempted (guarded the same way as everywhere else in
   this codebase — check `has_animation()` before assuming it plays),
   `death_sfx` plays once, and no error is thrown if a unit's frames
   happen to omit the clip.
8. **Sound in a crowd:** deploy several squads of the new unit into a big
   fight — its attack/death sounds stay limited (no loud stacking, press
   **J** in-arena to compare with the `sword_hit` limit test) and hero
   sounds remain audible over them. No `neznamy sfx id` warning.
9. Play a full match to completion with the new unit's card on at least
   one side without errors.
