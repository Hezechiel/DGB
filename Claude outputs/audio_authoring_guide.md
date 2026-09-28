# Divine Gestures: Babylon — Audio Authoring Guide

> Companion to `architecture.md` §9 (how the audio system is built and
> why). This doc is the step-by-step checklist for **adding a sound** —
> a new variant, a new sound event, a hero/unit sound, ambient, a voice
> line or a stinger. Sibling of the hero/unit/map authoring guides; update
> it whenever the audio pipeline changes. The running inventory of what
> exists and what's missing is `Claude outputs/audio_tree.txt` in the repo.

---

## 1. The model in one paragraph

Every sound the game plays is a **sound event id** (`StringName`, e.g.
`&"sword_hit"`). The id resolves to one **`SoundData`** resource in
`data/sounds/<id>.tres`, which holds the audio file(s) and how to play
them (bus, priority, volume, randomization, limits). Code only ever says
`AudioManager.play_sfx(&"sword_hit", global_position)` (or `play_voice` /
`play_announcer` / `play_stinger`); data files only ever hold ids. So:

- **New variant of an existing sound** → drop a file in, add it to that
  `SoundData`'s `streams`. No code.
- **New sound for an existing hook** (a hero's attack, a unit's death,
  turret destroyed, a map ambient) → new `SoundData` + set the id on the
  hero/unit/emitter. No code.
- **New kind of event** (card deploy, projectile impact, hero hurt, spell
  cast…) → asset + `SoundData` + **one hook in code** → that's a Claude
  Code prompt step.

Music (`MUSIC_TRACKS`) and UI taps (`UI_SOUNDS`) are still TEMP tables
inside `AudioManager.gd`, not `SoundData` — adding a menu/battle track or
a UI sound is a one-line code edit there for now.

---

## 2. Files & import settings

Folder layout (full tree with status: `audio_tree.txt`):

```
assets/audio/
├── music/{menu,battle,stingers}/     .ogg
├── ambient/<pantheon>/               .ogg
├── sfx/ui/                           .wav
├── sfx/combat/{melee,ranged,impact,hurt,death,deploy,structures}/  .wav
├── sfx/spells/<spell>/  sfx/status/  sfx/pickups/                   .wav
├── sfx/heroes/{common,<hero>}/       .wav
└── voice/{heroes/<hero>,announcer}/  .ogg
```

Naming: all lowercase (Android paths are case-sensitive), `<event>_NN`
for variants (`sword_hit_01…06`), hero files prefixed with the hero
(`zeus_bolt_travel`, `zeus_spawn_01`), ambient `amb_<pantheon>_…`,
announcer `announcer_<event>_NN`, stingers `stinger_<event>`.

Import (Import dock → set once → Preset → "Set as default"):

| Type | Settings |
|---|---|
| SFX / UI `.wav` | Force Mono ON, Max Rate 44100, Edit → Trim ON, Normalize ON, Compress QOA, Loop OFF |
| Music `.ogg`, ambient **bed** `.ogg` | Loop **ON** |
| Ambient **one-shot**, voice, announcer, stinger `.ogg` | Loop **OFF** — a looping one-shot plays forever (`amb_greek_cymbals` hit this) |

Positional sounds should be mono (Godot pans them itself). Keep variants
in a group at similar loudness — Normalize handles most of it.

---

## 3. Create a `SoundData` — `data/sounds/<id>.tres`

In the FileSystem dock: right-click `data/sounds/` → New Resource →
`SoundData` → name the file exactly like the id. `AudioManager` scans the
folder at startup (duplicate id = `push_error`). Fields
(`scripts/sound_data.gd`):

| Field | Guidance |
|---|---|
| `id` | Must equal the file name, globally unique. |
| `streams` | The file(s). 3–6 variants for anything frequent (hits, shots), 1–2 for rare events. Random pick, never the same twice in a row. Empty = "asset not made yet" → one console warning, then silent. |
| `bus` | `Combat` (gameplay), `Environment` (ambient), `Voice` (hero lines, announcer), `Music` (stingers). UI isn't a `SoundData` bus (TEMP table, §1). |
| `priority` | `LOW` = frequent unit noise (unit hits/shots/deaths, ambient); `NORMAL` = default; `HIGH` = the player must hear it (hero attacks, hero hurt); `CRITICAL` = rare key events (hero death, structure destroyed, voice, stingers). Priority decides who survives when all 16 voices are busy. |
| `volume_db` | LOW sounds ~ −6 dB, ambient −10 to −14 dB, important sounds 0. Mix by ear in a real fight. |
| `volume_jitter_db` | Random −X…0 dB per play. Default 1.0; 0 for voice/stingers/beds. |
| `pitch_jitter` | Random 1±X. Default 0.03; **0 for anything tonal** (harp, music, voice) or it detunes against the music. |
| `max_instances` | Max copies of this id at once; over the limit its own oldest copy is restarted. 2–3 for unit noise, 1 for big events. |
| `min_interval` | Min seconds between two starts of this id (0.05 for hits). Stops 10 units in one frame from stacking. |
| `positional` | `true` = placed on the map (pans + fades with distance from the camera). `false` = centered. Voice, stingers and musical ambient are `false`. |
| `max_distance` | World px from the camera's screen center; farther → not even started. Default 500 (~1.3 screens at zoom 3). |

**Priority belongs to the id, not the file.** If a hero should use a
unit's files but must never be drowned out by them, make a second id with
the same `streams` and a higher priority (`hero_melee_hit` vs
`sword_hit`).

---

## 4. Hook it up

| Sound | Where the id goes | Doc |
|---|---|---|
| Hero attack / death / spawn voice | `HeroData.attack_sfx` / `death_sfx` / `spawn_voice` | `hero_authoring_guide.md` §2.7 |
| Unit attack / death | `UnitData.attack_sfx` / `death_sfx` | `unit_authoring_guide.md` §2.6 |
| Turret destroyed | `turret.gd` export `destroyed_sfx` (default `&"turret_destroyed"`) | — |
| Map ambient | `AmbientEmitter.sound_id` in the map scene | `map_authoring_guide.md` §2.11 |
| Announcer line | `MatchAnnouncer` (`scripts/arena/match_announcer.gd`) — new events need a code hook there | `architecture.md` §4/§9 |
| Victory / defeat stinger | `match_end_screen.gd` (`stinger_victory` / `stinger_defeat`) | `architecture.md` §9 |
| Menu/battle music, UI taps | `MUSIC_TRACKS` / `UI_SOUNDS` in `AudioManager.gd` (TEMP) | `architecture.md` §9 |

Rules for any **new code hook** (write them into the Claude Code prompt):

- Call `AudioManager` only from scene nodes / UI — **never** from
  `BattleManager`, `EnergySystem`, `HealingSystem`, `HeroAI`. React to
  their signals from a node instead (the `MatchAnnouncer` pattern).
- Gameplay sounds fire when the thing actually happens (damage point,
  projectile release, death), not when an animation merely starts.
- Pass `global_position` for anything that happens somewhere on the map.
- Loops never go through `play_sfx()` — they need their own player
  (the `AmbientEmitter` LOOP pattern).
- Empty ids are fine to pass — `play_sfx(&"")` is silent, no guard needed.

---

## 5. Verify

1. No `neznamy sfx id` / `chyba asset` / `duplicate sound id` warning on
   boot or when the sound should play.
2. It plays at the right moment, once — and a canceled action (hero
   windup canceled, unit target fled) makes no sound.
3. In a big fight it doesn't stack (press **J** in the arena for the
   `sword_hit` limit test as a reference) and HIGH/CRITICAL sounds still
   come through.
4. Positional: with headphones, pan the camera — it moves left/right and
   fades; far away it doesn't play.
5. Pause menu: combat/ambient/voice pause, UI and music keep going.
6. The right slider controls it (Effects for SFX/UI/ambient, Voice for
   voice/announcer, Music for music/stingers).
