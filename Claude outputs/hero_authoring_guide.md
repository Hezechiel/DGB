# Divine Gestures: Babylon — Hero Authoring Guide

> Companion to `architecture.md` and to `map_authoring_guide.md` (same
> project, sibling pipeline). Read `architecture.md`'s data-layer section
> first if you haven't touched the hero pipeline before — this doc is the
> step-by-step checklist for adding a new playable hero, not the
> explanation of why it's built this way. Update this file whenever the
> hero pipeline itself changes, the same as architecture.md.

---

## 1. What a hero actually is — and why it's *not* the map pattern

Maps get a brand-new `.tscn` every time (`map_authoring_guide.md` §1).
**Heroes don't.** There are exactly two hero scenes in the whole project,
and every hero — present and future — shares them:

- **`scenes/arena/player.tscn`** — the player-controlled hero avatar.
  Used whenever `BattleManager.spawn_hero(id, team, controlled: true)` is
  called.
- **`scenes/arena/hero_dummy.tscn`** — the AI-controlled hero avatar
  (movement/targeting via `HeroAI.gd`/`enemy_card_ai.gd`). Used when
  `controlled: false`.

A hero's actual identity — stats, projectile, look, and sounds — lives
entirely in a third kind of file:

- **`data/heroes/<id>.tres`** — a `HeroData` resource (`id`,
  `display_name`, combat stats, `projectile_scene`, `sprite_frames`,
  sound ids).

At boot, `CardDB` scans `data/heroes/*.tres` into an id-keyed dictionary
— the exact same pattern `MapDB` uses for maps. At spawn time,
`BattleManager.spawn_hero(hero_id, team, controlled)` (scripts/BattleManager.gd
~L390) resolves the `HeroData` via `CardDB.get_hero(hero_id)`, instances
whichever of the two generic scenes applies, and calls `hero.configure(data,
team)` — which copies every stat from `HeroData` onto the node and
**overwrites** `$AnimatedSprite2D.sprite_frames` with `data.sprite_frames`.
That overwrite happens synchronously, before the node even enters the
tree.

**This means adding a hero never means adding a new scene.** It means
adding a new `HeroData` .tres (and the `SpriteFrames` .tres it points
at). The scan picks it up automatically — zero script changes, same
promise as the map pipeline.

### The footgun this causes

`player.tscn` and `hero_dummy.tscn` each have their *own*
`AnimatedSprite2D.sprite_frames` value too, set directly in the
Inspector. That value is **only** a design-time/editor-preview default
and the crash-prevention fallback used before `configure()` runs. It has
**no effect on which hero you actually see in a match** — `configure()`
always overwrites it from the spawned hero's `HeroData`. Two consequences:

- Editing a hero's *look* in the Inspector on `player.tscn`/
  `hero_dummy.tscn` does nothing for gameplay. The only place that
  matters is `sprite_frames` on the hero's own `data/heroes/<id>.tres`.
- The scene-level value must still always point at a **fully existing**
  `SpriteFrames` resource — never at a not-yet-created one, and never
  left empty. If it's missing or the `animation`/`autoplay` name doesn't
  exist in whatever frames *are* assigned, `scene.instantiate()` itself
  crashes at spawn time, before `configure()` ever gets a chance to fix
  it up (`"There is no animation with name ''"` from
  `AnimatedSprite2D.set_animation()` — hit this exact bug in September
  2026 wiring up Poseidon). Keep both scenes pointed at *some* real,
  complete hero's frames at all times, even mid-refactor.

---

## 2. Checklist

### 2.1 Sprite art & the frames resource

Sprite sheets live at `assets/sprites/gods/<pantheon>/<name>/<name>_<clip>.png`
(existing convention: `zeus_iddle.png`, `zeus_death.png`, `zeus_spawn.png`,
`poseidon_idle.png`, ...) — one or more PNGs sliced into equal-size cells
via `AtlasTexture` regions, assembled into a single `SpriteFrames` resource
at `data/heroes/frames/frames_<name>.tres`. Easiest path: duplicate an
existing frames `.tres` (`frames_zeus.tres` is the reference
implementation) in the Godot editor rather than hand-writing the resource
text — it keeps the `AtlasTexture` region math correct.

Cell size is per-hero and per-clip (Zeus's idle/attack/death sheets are
325×350, his spawn sheet is 412×412; Poseidon's idle/walk are 350×350,
his death/spawn are 400×400) — `AnimatedSprite2D.scale = Vector2(0.09,
0.09)` on both hero scenes absorbs the difference, so match your source
art's own proportions rather than an existing hero's pixel dimensions.

**Direction convention:** every animation is authored facing **left**,
full stop — there is no separate right/up/down art anywhere in the
pipeline. Each hero script mirrors the left-facing clip via `flip_h`
(see `update_idle_animation()` / `update_animation()` /
`update_attack_animation()` / `die()` in `player.gd` and `hero_dummy.gd`
for the exact direction→`flip_h` mapping) to cover the other three
facings. A new hero's frames only ever need the left-facing pose per
animation.

**Required animation names** — the hero scripts call these by exact
name, so a new hero's `SpriteFrames` must define all five (note the
`iddle` typo on the idle clip — preserve it, don't "fix" it, or
`autoplay` on `player.tscn` breaks):

| Name | Used for | Notes |
|---|---|---|
| `iddle_left` | Standing still — `autoplay` default, and resumed automatically whenever any locked state (attack, spawn, stun) ends | Loop on. |
| `walk_left` | Movement, any direction | One clip, mirrored via `flip_h` for all four directions — don't author separate facings. Loop on. |
| `attack_left` | Plays during the attack's cast-point | **Its length directly drives how long the hero is locked mid-swing — read §2.2 before picking an fps for this clip.** Loop flag doesn't matter (timing is derived from frame_count/speed, not the loop flag or `animation_finished`). |
| `spawn_left` | Plays on first spawn and after every death→respawn cycle; hero is frozen for its duration | Loop can be either — same duration-derived timing as attack_left. |
| `death_left` | Plays on death; hero waits for it to finish before going invisible | **Must be loop = off** — this is the one clip still timed via `animation_finished` rather than a duration timer, so a looping death clip would make the hero wait forever. |

### 2.2 The attack cast-point system — read this before tuning a new attack clip

Every hero's attack (ranged or melee, player or AI) runs through the same
`_perform_attack()` logic, duplicated deliberately between `player.gd` and
`hero_dummy.gd` (no shared base class — `architecture.md` principle).
When an attack starts: the hero plays `attack_left`, and — unless
`can_move_while_attacking` is set — movement locks. The live-derived
cast-point (`frame_count / speed` off whatever `SpriteFrames` is currently
assigned, never hardcoded) now splits into two phases at
`HeroData.damage_point_ratio` (0.0-1.0, default `0.7`, added Sept 2026):

- **Before the damage point:** the hero hasn't committed yet. A genuinely
  new command — a new tap-to-move, or an explicit tap on a *different*
  target — cancels the swing for free: no damage lands, the `attack_left`
  animation snaps immediately back to idle/walk, movement unlocks that
  same instant, and the attack cooldown resets to zero (the hero can
  immediately start a brand-new attack or just move — canceling costs
  nothing beyond the time already spent winding up). Re-issuing the exact
  same target mid-swing is a no-op, not a cancel — the swing completes
  untouched. **A canceled swing makes no sound** — see §2.7.
- **At the damage point:** the hit commits. Ranged fires `projectile_scene`
  right then; melee does a direct, range-and-liveness-rechecked
  `take_damage()` (so a melee swing can still whiff if the target escaped
  mid-windup) right then. `attack_sfx` plays at this same moment (§2.7).
  Movement unlocks immediately in both cases, regardless of whatever's
  left of the `attack_left` clip — the remaining frames are purely
  cosmetic backswing, nothing is still locked. `recovery_time` (see below)
  starts counting from **this** point, not from the animation's end.

**Total time between attacks = damage-point (cast-point × `damage_point_ratio`,
from the animation, live) + `recovery_time` (authored per hero).** This is
still why retuning `attack_left`'s fps or frame count for feel never
requires touching `recovery_time` — the cooldown math re-derives the
cast-point half every time from whatever's actually loaded, same promise
as before. (An earlier version of this system stored an absolute
`fire_cooldown` number that had to be manually kept above the animation's
own length — that broke the moment an animation got re-timed and caused a
hard "can't move" freeze. Don't reintroduce that pattern; always derive
cast-point from the animation, never author it as a flat number.)

`damage_point_ratio` is also the main per-hero *feel* knob: low values
(~0.3-0.5) make a hero quick and easy to cancel out of — a kiting/skirmish
archetype like Artemis; high values (~0.8-1.0) make a hero slow and
committed once a swing starts — a heavy-hitter archetype like Hephaestus,
whose attacks are hard to interrupt once thrown. Tune this per hero
alongside `attack_left`'s own length, not instead of it.

**A stun landing mid-swing cancels the attack outright, it does not pause
it.** `apply_stun()` calls the same cancel path (`_cancel_attack_windup()`)
directly (see `architecture.md` §6) because a locked windup disables
`_physics_process` entirely, so the usual freeze-and-resume status-timer
behavior (used everywhere else, including for a hero's own *cooldown*
between attacks) simply never gets a chance to run mid-swing. This is
intentionally different from `unit.gd` minions, which have no cast-point
system to interrupt at all.

Two more things every new hero inherits automatically, with no per-hero
config beyond §2.3's table:

- **Ranged vs. melee** — `HeroData.attack_type` (`RANGED` / `MELEE`), same
  as always, just triggered at the damage point instead of the old
  animation-end.
- **Auto-attack respects player intent (player.gd only)** — the hero's
  passive "nearest enemy in range" auto-attack only *starts* a new attack
  while the player has no active move command; an explicit tap-on-enemy
  order (`primary_target`) is a sticky commanded order and keeps firing
  every cycle regardless, until the player moves or retargets (either of
  which now also cancels an in-progress swing, see above). Nothing to
  configure per-hero here — it's shared targeting code, not hero data.
  `hero_dummy.gd`'s AI has its own, narrower interrupt trigger — see §2.6.

Optional per-hero fields, all on `HeroData`, all safe to leave at their
defaults:

| Field | Default | Guidance |
|---|---|---|
| `attack_type` | `RANGED` | Set `MELEE` for a swing-based hero — check `heroes_greek.md`/`heroes_norse.md` for which gods are which, and lower `attack_range` to a melee-appropriate value (Poseidon uses `20.0`) when you do. |
| `can_move_while_attacking` | `false` | Only for a deliberately-designed "kiter" hero archetype — most heroes should leave this off; setting it removes the movement lock entirely during cast-point. |
| `attack_sfx` / `death_sfx` / `spawn_voice` | `&""` (silent) | `SoundData` ids — see §2.7. |
| `recovery_time` | `0.4` | Post-damage-point cooldown remainder (see above). Override only if this hero should feel noticeably faster/slower to re-engage than the roster default — not to compensate for a slow/fast attack animation, which is handled automatically. |
| `damage_point_ratio` | `0.7` | The cancelable-vs-committed knob — see the cast-point section above. Lower for quick/kiting heroes (Artemis), higher for slow/heavy ones (Hephaestus). |

### 2.3 Create `data/heroes/<id>.tres`

Easiest path: duplicate an existing hero `.tres` (`hero_zeus.tres` is the
reference implementation) rather than building from scratch. `HeroData`
fields (`scripts/arena/hero_data.gd`):

| Field | Guidance |
|---|---|
| `id` | `&"hero_<name>"` — must be globally unique; `CardDB` push_errors on a duplicate, same guard as map ids. |
| `display_name` | Player-facing name. |
| `max_hp` / `speed` / `attack_range` / `projectile_damage` | Optional — omit to fall back to `HeroData`'s own `@export` defaults (`500` / `70.0` / `80.0` / `25`), same as every hero today. Set explicitly only if this hero is meant to be statistically different. |
| `attack_type` / `can_move_while_attacking` / `recovery_time` / `damage_point_ratio` | See §2.2's table — all optional, all combat-feel fields. |
| `attack_sfx` / `death_sfx` / `spawn_voice` | Sound ids — see §2.7. |
| `projectile_scene` | Reuse `scenes/arena/projectiles/projectile.tscn` unless this hero has a bespoke bolt — a hero-specific special (Zeus's Chain Lightning, Poseidon's Tidal Slam per `heroes_greek.md`) is separate, unscoped design work, not part of this checklist. |
| `sprite_frames` | Points at the `.tres` from §2.1. |

### 2.4 Point a scene's runtime hero id at it

There's no hero-select flow (see §3), so the only way to actually see a
new hero in a match is `scripts/arena/arena.gd`'s hardcoded consts:

```gdscript
const PLAYER_HERO_ID := &"hero_<name>"
const ENEMY_HERO_ID := &"hero_<name>"
```

Both must point at a **fully authored** hero — `HeroData` *and* its
`SpriteFrames` both existing on disk — or `spawn_hero()` push_errors
(`"unknown hero id"`, if `CardDB` never registered it) or crashes at
`scene.instantiate()` (if the frames file is missing — see §1's footgun).
A hero can exist in `data/heroes/` without being wired here at all — it
just won't appear in any match yet, harmlessly.

### 2.5 Keep both generic scenes' own defaults valid

After adding a hero (especially if it's about to become the new
`PLAYER_HERO_ID`/`ENEMY_HERO_ID`), double-check `player.tscn`'s and
`hero_dummy.tscn`'s own `AnimatedSprite2D.sprite_frames` /
`animation` / `autoplay` values still point at *some* real, fully-frames'd
hero — doesn't have to be the new one, just has to exist. Nothing to
change here in the common case (you're not required to point the scene
defaults at every new hero), but never leave them pointed at a
not-yet-existing frames file, even temporarily — see §1.

### 2.6 AI behavior — one interrupt trigger wired up, otherwise generic

`hero_dummy.gd`'s movement/targeting (march to nearest enemy structure,
retreat to a healing pod under `HeroAI`'s HP-hysteresis state machine) is
entirely generic — it reads the same `HeroData` stats every hero gets
from §2.3, and shares §2.2's exact cast-point/damage-point attack logic
with `player.gd` (same lock/commit/recovery math, just triggered by AI
targeting instead of player taps). A new hero behaves identically to
every other hero, AI-wise, until per-hero kits exist (§3).

One AI-specific interrupt is wired up (Sept 2026): when `HeroAI`'s
NORMAL⇄LOW_HP hysteresis flips while the hero is mid-swing, `take_damage()`
cancels the attack via the same `_cancel_attack_windup()` player commands
use — so a hero dropping into LOW_HP starts retreating/heal-seeking
immediately instead of finishing its current swing first. This is hooked
in `take_damage()`, not `_physics_process`, for the same reason described
in §2.2/`architecture.md` §6 (physics processing is itself suspended
during a locked windup). This is meant to be the first of several future
AI interrupt triggers (e.g. spotting a higher-priority target) — none of
the others are implemented yet.

### 2.7 Sounds (Sept 2026)

A hero's sounds are three `StringName` ids on `HeroData`, each pointing
at a `SoundData` in `data/sounds/` (how to create one:
`audio_authoring_guide.md`). An empty id is silent — no error, no
placeholder. The old `attack_sound: AudioStream` field and the
per-scene `$AttackSfx` node no longer exist.

| Field | When it plays | Where | Guidance |
|---|---|---|---|
| `attack_sfx` | At the **damage point** (§2.2): melee = the moment the hit lands, ranged = the moment the projectile is released. Never at swing start, so a canceled swing is silent. | `player.gd` + `hero_dummy.gd` `_perform_attack()`, positional | Use a hero-specific id with **HIGH** priority so unit noise can't steal it (`zeus_bolt`, `hero_melee_hit`). Can reuse a unit's files under a separate id — priority belongs to the id, not the file. |
| `death_sfx` | In `die()`, both heroes | positional | Shared per pantheon is fine (`hero_death_greek`), CRITICAL. |
| `spawn_voice` | `player.gd::play_spawn_animation()` — first spawn and every respawn, **only for the locally controlled hero** (`hero_dummy.gd` never calls it) | Voice bus, no position, one line at a time | A `SoundData` on bus `Voice` with 2+ lines in `streams` (3+ feels random; 2 just alternate), jitter 0. Files in `assets/audio/voice/heroes/<name>/<name>_spawn_NN.ogg`. |

Current wiring: Zeus = `zeus_bolt` / `hero_death_greek` / `zeus_spawn`;
Poseidon = `hero_melee_hit` (borrowed sword files, a trident sound is
still missing) / `hero_death_greek` / no spawn voice yet.

---

## 3. Known gaps

- **No hero-select/network flow.** `PLAYER_HERO_ID`/`ENEMY_HERO_ID` are
  TEMP hardcoded consts in `arena.gd` (comment marks them explicitly, same
  status as `MapDB.get_random_map_id()`'s TEMP picker) — there is no
  in-match hero picker, no per-match hero variety, and no `release_ready`-
  style flag for heroes at all. Every match today runs whichever two
  heroes those consts name, full stop.
- **No sidekick support.** `heroes_greek.md` designs every god with a
  paired sidekick unit; `HeroData` has no sidekick field and nothing
  spawns one. Out of scope for this checklist.
- **No hero-specific abilities.** Every hero attacks via the same generic
  cast-point system (§2.2) — there is no cooldown-skill or
  special-ability system yet (`game_design.md` §6 lists this as an open
  question). Giving Zeus his Chain Lightning or Poseidon his Tidal Slam
  is new systems work, not a data-resource checklist item (and so are
  their sounds).
- **Only two hero scenes, ever (by design).** Unlike maps, don't create
  `scenes/arena/<Name>Hero.tscn` for a new hero — that's not how this
  pipeline works, and doing so would just get ignored by
  `BattleManager.spawn_hero()`, which only ever instances `player.tscn`
  or `hero_dummy.tscn`.
- **AI heroes still don't gate new attacks by movement intent the way the
  player does.** §2.2's "auto-attack respects player intent" *starting*
  gate only applies to `player.gd` — `hero_dummy.gd`'s AI can still start
  a self-defense swing while mid-retreat (see `hero_dummy.gd`'s
  `SELF_DEFENSE_RANGE_RATIO`), by design. What Sept 2026 *did* fix: a
  swing already in progress now gets canceled the instant the AI's HP
  state flips into LOW_HP (§2.6), so retreat itself is never held hostage
  by a swing that already started — only the decision to start a *fresh*
  self-defense swing while already retreating remains ungated. Flagged as
  a possible follow-up, not yet decided or scoped.
- **No hero-hurt sound and no projectile-impact sound yet** — both are
  on the missing-audio list (`Claude outputs/audio_tree.txt`) and need a
  hook as well as an asset.

---

## 4. Verification checklist for a newly authored hero

1. `CardDB` boots without a `push_error` (duplicate id, missing/failed
   resource) — check the console on first run after adding the hero.
2. If wired into `arena.gd`'s `PLAYER_HERO_ID`/`ENEMY_HERO_ID`: start a
   match and confirm no `"unknown hero id"` error and no crash at
   `scene.instantiate()`.
3. Player-side hero (if applicable): spawns with the correct sprite;
   standing still shows `iddle_left`; moving in any direction plays
   `walk_left`, mirrored correctly for the direction via `flip_h`.
4. Attack timing (both sides, if applicable): movement stays locked only
   until `damage_point_ratio` of `attack_left`'s own length, not the full
   clip and not some other fixed duration; the hit lands right at that
   point (projectile fired for ranged, direct damage for melee, only
   while still in range) and movement is free again immediately after,
   with the remaining animation frames purely cosmetic. The hero can
   attack again roughly `recovery_time` seconds after the damage point,
   regardless of whatever fps/frame count the clip uses.
5. Cancellation (both sides, if applicable): start a swing, then issue a
   genuinely new command before the damage point (player: tap elsewhere or
   tap a different enemy; AI: take enough damage to flip into LOW_HP) —
   the swing should cut immediately with no damage dealt **and no attack
   sound**, and the new command should execute without delay. Re-issuing
   the *same* order mid-swing (player re-tapping the identical target)
   should NOT interrupt it. A stun landing mid-swing should cancel it the
   same way.
6. Player-side only: hold a move command through an enemy's attack range
   — confirm the hero walks through without auto-engaging, and only
   starts auto-attacking once idle near an enemy. Tap an enemy directly
   and confirm the attack repeats every cycle without re-tapping.
7. AI-side hero (if applicable): confirm it marches toward the enemy
   structure, fires/swings on nearest target in range, and seeks a
   healing pod at low HP without script errors.
8. Reduce the hero to 0 HP: `death_left` plays (correctly mirrored for
   the hero's last facing direction), `death_sfx` plays once, and the hero
   waits for the clip to finish before hiding.
9. Kill and let the hero respawn: `spawn_left` plays and the hero is
   frozen for its duration before regaining control. As the local hero,
   a `spawn_voice` line plays on first spawn and every respawn, never the
   same line twice in a row; as the AI hero, it stays silent.
10. **Sound:** the attack sound is audible in a crowded fight (unit hits
    don't drown it) and follows the hero left/right when you pan the
    camera. No `neznamy sfx id` / `chyba asset` warning in the console for
    this hero's ids.
11. Play a full match to completion with the new hero on at least one
    side without errors.
