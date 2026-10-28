# Duel of Gods: Babylon — Architecture

> Technical companion to `docs/game_design.md`. Session rules and environment setup
> live in `CLAUDE.md`. Update this file when an architectural decision is made.
> Canonical copy: `docs/architecture.md` + `docs/arch/*.md` in the repo. Merged
> Oct 2026 from the project copy, the older repo copy and
> `Claude outputs/architecture.md` (superseded); split into per-topic files under
> `docs/arch/` the same month — this file keeps the guiding principles, the autoloads and the index.

---

## 1. Guiding principles

- **Behavior in scenes, data in resources.** Archetype scenes (melee unit, hero)
  carry scripts, collision, and state machines; individual units/heroes/cards are
  Inspector-edited `.tres` files — **one file per card or god** (Oct 2026): a
  unit card is a `UnitData`, a spell card a `SpellData` (both extend the shared
  `CardData` base), a god a `HeroData`.
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
  future AI controller, and future network handlers are all just callers.
- **Per-match state is explicitly reset.** `BattleManager.reset_match_state()` is
  called from `arena._enter_tree()` — before children `_ready()` runs, because
  turrets/bases self-register in their own `_ready()`.
- **Levels and synergy never travel per spawn.** Spawn messages stay
  `{card_id, position, team}`. A per-team **match manifest** (god, god level,
  card levels) is set once at match start; `BattleManager` looks multipliers up
  by team at its three entry points.
- **The collection changes through one API.** Owned cards, copies, levels and
  decks are mutated only by `PlayerProfile`'s `grant_cards()`, `upgrade_card()`,
  `set_deck()`, `reset_profile()` — the calls a server will later own. Rules
  and math around them (`LevelCurve`, `PackRoller`, `DeckRules`) are pure
  static code with no nodes and no autoload calls.
- **UI looks live in one Theme, painted art stays text-free.** Panel and button
  styles belong in `assets/UI/dgb_theme.tres` (`menu_ui.md`), not in per-node overrides.
  Plain boxes are drawn by Godot (`StyleBoxFlat`); only pieces with real painted
  detail are textures, used as 9-slice `StyleBoxTexture`s. Words are never
  painted into art — titles and button labels are `Label`/`Button` text.
- **Tuning numbers live in data, display text is generated from them.** A god
  skill's numbers sit in its `SkillData.values`; the Card Detail text is a
  template filled from those values (`data_layer.md`), so a balance change never needs a
  text rewrite. The runtime effect reads the same values (`combat_movement.md`).
---

## 2. Autoloads

| Autoload | Role |
|---|---|
| `BattleManager` | Match state owner: team registries, structures, spawn entry points, the per-team **match manifest** (levels + synergy, `data_layer.md`), hero respawn, match timer, `match_ended` (+ read-only `is_match_over()`, true from the frame the result is decided). Also the navigation query helpers `has_navigation()` / `snap_to_navigation()` (`combat_movement.md` Navigation) — stateless wrappers over `NavigationServer2D`, no per-match state of their own. |
| `CardDB` | Startup scan of `data/cards/`, `data/heroes/`, `data/packs/` (plus the legacy `data/units/` / `data/spells/` roots if they still exist) into id-keyed dictionaries. The scan is **recursive** (content sits in per-pantheon subfolders) and skips folders named `frames` (SpriteFrames) and `skills` (SkillData, reached via `HeroData.skill`). Each resource is routed **by type, not folder** — `UnitData`/`SpellData` → cards, `HeroData` → gods, `PackData` → packs — so the folder layout can change without code changes; a bare `CardData` file (pre-merge format) is rejected with an error. Handles `.tres.remap` suffixes in Android exports. Duplicate-id guard. Also: `has_card()` / `has_hero()` (silent existence checks), sorted `list_card_ids()` / `list_hero_ids()` / `list_pack_ids()`, and `get_pack_pool(faction)` — the drop pool by rarity for `PackRoller`. |
| `PlayerProfile` | The player's collection and decks, saved to `user://profile.json` (`save_version` 2; v1 is migrated on load). Owned cards and gods as `{level, copies}`, **one deck per god** (`_decks`) and the active god. Read API returns copies only. Mutation API: `grant_cards()`, `upgrade_card()`, `set_deck()`, `reset_profile()` — nothing else may change the collection. `get_deck_hero()` / `get_deck_cards()` = what goes into the match; `get_deck_for(god)` = saved deck or a default built by `DeckRules`. A broken save falls back to the starter profile; ids the game no longer knows are dropped. Logs a content error for any god that cannot field 7 allowed cards. No scene or node references; depends only on `CardDB`. Must be listed **after `CardDB`** in `project.godot`. No per-match state. |
| `MapDB` | Same scan pattern as `CardDB`, over `data/maps/` into a single id-keyed `MapData` dictionary. Exposes `get_map(id)`, `list_map_ids()`, and a TEMP `get_random_map_id()` (uniform random, ignores `release_ready` on purpose — see `data_layer.md`) used by `PreMatchFlow` for testing until real map selection exists. |
| `EnergySystem` | Per-team energy: float pools, base regen, and a modifier list (temporary regen multipliers / cost reductions). **Zero scene/UI dependencies by design** — pure state+math so it ports to an authoritative server as-is; its only dependency is `CardDB` (cost lookup). Driven by the caller (`arena.gd` today): `reset_match_state()` / `start()` / `stop()`. Emits `energy_int_changed`. |
| `HealingSystem` | Per-team pod cooldowns + active heal-over-time state. **Zero scene/UI dependencies by design**, same contract as `EnergySystem` — no scene/node/Area2D/Sprite2D references, pure state+math so it ports to an authoritative server as-is. Third autoload with its own `reset_match_state()` (same pattern as `EnergySystem`). Death safeguard lives in the hero scripts: `die()` calls `HealingSystem.cancel_heal(team)`, which clears the active HoT and emits `heal_ended` — the same signal path a normally-completed heal uses to clear the health bar's pending band. Emits `pod_ready`, `heal_instant`, `heal_tick`, `heal_started`, `heal_ended`. |
| `MatchConfig` | Holder for pre-match data. Display fields (rank, both players' name/faction label) are placeholders and never networked. It also carries the **deck manifest inputs**: `local_hero_id`, `local_deck_card_ids`, `local_hero_level`, `local_card_levels` and the `opponent_*` twins, filled by `PreMatchFlow` from `PlayerProfile` (the AI mirrors the player's cards and levels; its god is a TEMP constant). `map_id` is set by `PreMatchFlow` via `MapDB.get_random_map_id()`. `MatchConfig` itself calls no other autoload. |
| `InputR` | Input routing (tap-to-move targets, gesture state). |
| `Settings` | Persistent user settings (`user://settings.cfg`): `lock_camera`, `music_volume`, `sfx_volume`, `voice_volume` (linear 0–1). Single source of truth for volumes — emits `settings_changed`, never touches `AudioServer` itself. |
| `AudioManager` | The single entry point for all sound (`audio.md`). Owns every audio player (music A/B crossfade, UI pool, voice, announcer, stinger, 16-voice positional SFX pool + 4 flat SFX voices), scans `data/sounds/` into id-keyed `SoundData` (same scan/`.remap` pattern as `CardDB`), applies bus volumes from `Settings`. **Presentation-only, client-side** — the one autoload that deliberately holds nodes; it is never called from the pure-logic autoloads (`BattleManager`, `EnergySystem`, `HealingSystem`, `HeroAI`). Listed directly after `Settings` in `project.godot` because its `_ready()` reads it. Replaced the old `Music` autoload (`scenes/music.tscn`, an `AudioStreamPlayer2D` — wrong node type for music). No per-match state → no `reset_match_state()`. |
| `HeroAI` | Per-team HP-threshold hysteresis for the AI-controlled hero (`NORMAL` / `LOW_HP`, 20%→50% band). **Zero scene/UI dependencies by design** — pure state+math, same contract as `EnergySystem`/`HealingSystem`. Doesn't know about pods, positions, targets, or navigation — that decision-making and pathing lives in `hero_dummy.gd`. Own `reset_match_state()`. |

`BattleManager.arena_root` is injected by `arena.gd` each match (autoload has no
scene of its own to parent spawned nodes under).

---

## Index

Read only the file that matches the task — not all of them.

- [docs/arch/data_layer.md](arch/data_layer.md) — `.tres` layout, `CardData`/`UnitData`/`SpellData`/`HeroData`/`SkillData`, `MapData`, collection fields, pure helpers, match manifest & synergy, `PlayerProfile`; read before touching data resources, `CardDB`, `PlayerProfile` or deck/level rules.
- [docs/arch/battle_scene.md](arch/battle_scene.md) — arena shell, map scenes, archetype scenes, HUD pieces, `BattleManager`/`EnergySystem`/`HealingSystem` APIs, camera, card hand, enemy AI, respawn, win/lose; read before touching `arena.gd`, the HUD or match flow.
- [docs/arch/combat_movement.md](arch/combat_movement.md) — unit/hero state machines, targeting, cast-point attacks, navigation, status effects, knockback, god skills, spells; read before touching `unit.gd`, `player.gd`, `hero_dummy.gd`, `SkillEffects` or `SpellZone`.
- [docs/arch/conventions_pitfalls.md](arch/conventions_pitfalls.md) — hard-won Godot pitfalls and project conventions (resets, input, navmesh, textures, scenes, UI layout); skim the relevant bullets before any non-trivial change.
- [docs/arch/networking.md](arch/networking.md) — design-time networking posture and the prepared server seams; read before adding state that a server would own.
- [docs/arch/menu_ui.md](arch/menu_ui.md) — main menu hub, tab pages, Deck screen, framed overlays, UI Theme, Card Detail; read before touching `scenes/menu/` or `scripts/ui/`.
- [docs/arch/audio.md](arch/audio.md) — `AudioManager` buses, API, `SoundData`, SFX pool, end-of-match sequence; read before adding or wiring sounds.
