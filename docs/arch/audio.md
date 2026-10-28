# Audio — DGB architecture

> Part of docs/architecture.md — see the index there.

## Audio

All sound goes through the `AudioManager` autoload (`architecture.md` §2). Built in three
phases (Sept 2026): music/UI/voice/volumes → positional SFX pool +
`SoundData` → ambient, announcer, stingers.

### Bus layout (`default_bus_layout.tres`)

```
Master (+ AudioEffectHardLimiter)
├── Music          ← music A/B players, stingers           (Music slider)
├── SFX            ←                                        (Effects slider)
│   ├── Combat     ← play_sfx() combat sounds
│   ├── UI         ← play_ui() taps (ALWAYS — plays while paused)
│   └── Environment← ambient (AmbientEmitter)
└── Voice          ← hero voice lines, announcer             (Voice slider)
```

Order matters: a bus can only send to a lower-index bus. Volumes are
linear 0–1 in `Settings`; `AudioManager._apply_volumes()` converts with
`linear_to_db()`, mutes at 0, and adds the announcer duck offset on Music
only. `audio_control.gd` is one generic slider script
(`audio_bus_name` = `"Music"`/`"SFX"`/`"Voice"`), three instances in
`setting_overlay.tscn`.

### Public API

| Call | Used for | Notes |
|---|---|---|
| `play_music(id, fade)` | menu / battle music | TEMP `MUSIC_TRACKS` table in code; several paths per id → random track; same id already playing = no-op; crossfades two players; stops a running stinger |
| `stop_music(fade)` | — | |
| `play_stinger(id, then_music)` | victory/defeat on `MatchEndScreen` | fades music out, plays once, then `play_music(then_music)`; missing asset → straight to `then_music` |
| `play_ui(id)` | button taps | TEMP `UI_SOUNDS` table; auto-wired to every `BaseButton`/`TouchScreenButton` via `node_added` (+ one walk of the boot scene, `conventions_pitfalls.md`). Groups: `ui_sfx_close` → close sound, `ui_sfx_none` → silent |
| `play_sfx(id, pos := INF)` | all gameplay sounds | positional if `SoundData.positional` and `pos` given; empty id = silent (callers never guard) |
| `play_voice(id)` | hero spawn line (local hero only) | one at a time, new cuts old; no jitter |
| `play_announcer(id)` | announcer | own player, queue of max 2, never cuts itself or hero voice; ducks music −8 dB while speaking |
| `stop_announcer()` | `arena.gd::_exit_tree()` | clears queue + duck |
| `get_sound(id)` | nodes that play sound themselves (ambient bed) | warns once on unknown id |
| `set_*_volume()`, `set_volume(bus, v)`, `get_volume(bus)` | settings sliders | forward to `Settings` |

### `SoundData` (`scripts/sound_data.gd`, `data/sounds/<id>.tres`)

One resource per sound **event**, not per file: `streams` holds the
variants (random pick, never the same twice in a row). `priority` is the
enum `SoundData.Priority { LOW, NORMAL, HIGH, CRITICAL }` — on the
`class_name` resource, not on the autoload (`conventions_pitfalls.md` autoload-enum pitfall).
`bus` is `Combat`/`Environment`/`Voice`/`Music`; Voice/Music ids use
`volume_db` + variants but ignore jitter, `positional` and the pool.
Priority belongs to the event, so the same files can back two ids
(`sword_hit` LOW for hoplites, `hero_melee_hit` HIGH for Poseidon).
Empty `streams` = asset not made yet → one warning, then silent.

### SFX pool and priorities

16 `AudioStreamPlayer2D` (positional) + 4 `AudioStreamPlayer` (flat),
children of the autoload, `PAUSABLE` (combat freezes with the game). Per
`play_sfx()`: `min_interval` gate → skip if farther than `max_distance`
from the camera's screen center (don't waste a voice) → acquire a voice:
(1) at `max_instances` for this id → steal its own oldest instance,
(2) a free voice, (3) steal the lowest-priority/oldest voice whose
priority ≤ the new one, else drop the new sound. The 2D listener is the
active `Camera2D`; `max_distance` is in world px.

### Who calls what

- Heroes (`player.gd` + `hero_dummy.gd`): `attack_sfx` at the damage point
  (`conventions_pitfalls.md`), `death_sfx` in `die()`. `player.gd::play_spawn_animation()` plays
  `spawn_voice` → only the **local** hero speaks.
- Units (`unit.gd`): `attack_sfx` in `_resolve_attack_hit()`, `death_sfx`
  in `die()`.
- Turrets: `destroyed_sfx` export (default `&"turret_destroyed"`) in
  `_on_destroyed()`, positional.
- Base: `destroyed_sfx` export (default `&"base_destroyed"`) as the first
  line of `base.gd::_on_destroyed()` — **non-positional** (`positional =
  false` in the `SoundData`), because the camera may still be far away when
  the base falls and a positional sound would be culled by `max_distance`
  before the end-sequence camera arrives.
- Maps: `AmbientEmitter` nodes (`battle_scene.md`).
- `MatchAnnouncer` (`battle_scene.md`), `MatchEndScreen` (stingers), `main_menu.gd` /
  `arena.gd` / `match_end_screen.gd` (music).
- Debug key **J** in `arena.gd` = 10× `sword_hit` in one frame (limit test).

### End-of-match sequence (base destroyed)

`arena.gd::_on_match_ended(winner)` → `"draw"` goes straight to
`MatchEndScreen` (no building fell, nothing to show); otherwise
`_play_end_sequence(winner)` runs for `END_SEQUENCE_SECONDS = 3.5`
(≈ the length of `base_destroyed_01.wav`):

| t (s) | What happens | Owner |
|---|---|---|
| 0.0 | Base falls → `base_destroyed` plays (non-positional); `match_ended` emitted | `base.gd`, `BattleManager` |
| 0.0 | `EnergySystem.stop()`, card drag cancelled, `hud.visible = false`, `DesaturateRect` hidden (no grey ending if the hero is dead), announcer stopped, music fades out (1 s) | `arena.gd` |
| 0.0–0.8 | Camera pans + zooms ×1.35 onto the fallen base, edge-clamped using the *target* zoom; drag/follow/edge-pan disabled (`_cinematic`) | `ArenaCamera.play_focus()` |
| 0.6 | Band opens from the center (0.25 s, `TRANS_BACK`) | `MatchResultBanner` |
| ~0.85 | "VICTORY" (gold) / "DEFEAT" (red) slams 1.6× → 1.0× | `MatchResultBanner` |
| ~1.2 | Subtitle "The enemy / Your Command Post has fallen" fades in | `MatchResultBanner` |
| 3.15–3.5 | Full-screen fade to black | `MatchResultBanner` |
| 3.5 | `change_scene_to_file(MatchEndScreen)` → stinger + menu music | `arena.gd`, `match_end_screen.gd` |

Input is locked for the whole sequence: `arena.gd` ignores tap-to-move
(`_match_over`), the camera ignores drag (`_cinematic`), the HUD (pause,
cards) is hidden, and `card_hand.play_card()` refuses via
`BattleManager.is_match_over()`. Units and heroes keep acting — the result
is already decided. Banner timing is derived from the `total_duration`
passed in, so changing `END_SEQUENCE_SECONDS` keeps the fade aligned.
Not built: slow motion (`Engine.time_scale` affects every timer/tween —
separate step), a banner impact sound, a sequence for turret kills or draws.

### Pause behaviour

Music, stinger and UI players are `ALWAYS`; voice, announcer, SFX pool and
map ambient are `PAUSABLE`.

### Known gaps (Sept 2026)

- `MUSIC_TRACKS` / `UI_SOUNDS` are still hardcoded tables in
  `AudioManager.gd` (TEMP) — candidates to move into `SoundData`.
- The banner slam of the end sequence is silent (no impact SFX yet); the
  stinger still plays only on `MatchEndScreen`.
- Many base sounds have no asset or hook yet (deploy, impacts, hero hurt,
  turret fire, spells, pickups) — tracked in `Claude outputs/audio_tree.txt`.
- 2D panning/attenuation at camera zoom 3 hasn't been formally tuned;
  `max_distance = 500` world px is a starting value.
- No music ducking for anything except the announcer; no stereo/mono
  setting; no master volume slider.
