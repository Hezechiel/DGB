# Duel of Gods: Babylon — Architecture

> Technical companion to `docs/game_design.md`. Session rules and environment setup
> live in `CLAUDE.md`. Update this file when an architectural decision is made.
> Canonical copy: `docs/architecture.md` in the repo (mirrored to the project
> knowledge as `architecture.md`). Merged Oct 2026 from the project copy, the
> older repo copy and `Claude outputs/architecture.md` (superseded).

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
  styles belong in `assets/UI/dgb_theme.tres` (§8), not in per-node overrides.
  Plain boxes are drawn by Godot (`StyleBoxFlat`); only pieces with real painted
  detail are textures, used as 9-slice `StyleBoxTexture`s. Words are never
  painted into art — titles and button labels are `Label`/`Button` text.
- **Tuning numbers live in data, display text is generated from them.** A god
  skill's numbers sit in its `SkillData.values`; the Card Detail text is a
  template filled from those values (§3), so a balance change never needs a
  text rewrite. The runtime effect reads the same values (§5).
---

## 2. Autoloads

| Autoload | Role |
|---|---|
| `BattleManager` | Match state owner: team registries, structures, spawn entry points, the per-team **match manifest** (levels + synergy, §3), hero respawn, match timer, `match_ended` (+ read-only `is_match_over()`, true from the frame the result is decided). Also the navigation query helpers `has_navigation()` / `snap_to_navigation()` (§5 Navigation) — stateless wrappers over `NavigationServer2D`, no per-match state of their own. |
| `CardDB` | Startup scan of `data/cards/`, `data/heroes/`, `data/packs/` (plus the legacy `data/units/` / `data/spells/` roots if they still exist) into id-keyed dictionaries. The scan is **recursive** (content sits in per-pantheon subfolders) and skips folders named `frames` (SpriteFrames) and `skills` (SkillData, reached via `HeroData.skill`). Each resource is routed **by type, not folder** — `UnitData`/`SpellData` → cards, `HeroData` → gods, `PackData` → packs — so the folder layout can change without code changes; a bare `CardData` file (pre-merge format) is rejected with an error. Handles `.tres.remap` suffixes in Android exports. Duplicate-id guard. Also: `has_card()` / `has_hero()` (silent existence checks), sorted `list_card_ids()` / `list_hero_ids()` / `list_pack_ids()`, and `get_pack_pool(faction)` — the drop pool by rarity for `PackRoller`. |
| `PlayerProfile` | The player's collection and decks, saved to `user://profile.json` (`save_version` 2; v1 is migrated on load). Owned cards and gods as `{level, copies}`, **one deck per god** (`_decks`) and the active god. Read API returns copies only. Mutation API: `grant_cards()`, `upgrade_card()`, `set_deck()`, `reset_profile()` — nothing else may change the collection. `get_deck_hero()` / `get_deck_cards()` = what goes into the match; `get_deck_for(god)` = saved deck or a default built by `DeckRules`. A broken save falls back to the starter profile; ids the game no longer knows are dropped. Logs a content error for any god that cannot field 7 allowed cards. No scene or node references; depends only on `CardDB`. Must be listed **after `CardDB`** in `project.godot`. No per-match state. |
| `MapDB` | Same scan pattern as `CardDB`, over `data/maps/` into a single id-keyed `MapData` dictionary. Exposes `get_map(id)`, `list_map_ids()`, and a TEMP `get_random_map_id()` (uniform random, ignores `release_ready` on purpose — see §3) used by `PreMatchFlow` for testing until real map selection exists. |
| `EnergySystem` | Per-team energy: float pools, base regen, and a modifier list (temporary regen multipliers / cost reductions). **Zero scene/UI dependencies by design** — pure state+math so it ports to an authoritative server as-is; its only dependency is `CardDB` (cost lookup). Driven by the caller (`arena.gd` today): `reset_match_state()` / `start()` / `stop()`. Emits `energy_int_changed`. |
| `HealingSystem` | Per-team pod cooldowns + active heal-over-time state. **Zero scene/UI dependencies by design**, same contract as `EnergySystem` — no scene/node/Area2D/Sprite2D references, pure state+math so it ports to an authoritative server as-is. Third autoload with its own `reset_match_state()` (same pattern as `EnergySystem`). Death safeguard lives in the hero scripts: `die()` calls `HealingSystem.cancel_heal(team)`, which clears the active HoT and emits `heal_ended` — the same signal path a normally-completed heal uses to clear the health bar's pending band. Emits `pod_ready`, `heal_instant`, `heal_tick`, `heal_started`, `heal_ended`. |
| `MatchConfig` | Holder for pre-match data. Display fields (rank, both players' name/faction label) are placeholders and never networked. It also carries the **deck manifest inputs**: `local_hero_id`, `local_deck_card_ids`, `local_hero_level`, `local_card_levels` and the `opponent_*` twins, filled by `PreMatchFlow` from `PlayerProfile` (the AI mirrors the player's cards and levels; its god is a TEMP constant). `map_id` is set by `PreMatchFlow` via `MapDB.get_random_map_id()`. `MatchConfig` itself calls no other autoload. |
| `InputR` | Input routing (tap-to-move targets, gesture state). |
| `Settings` | Persistent user settings (`user://settings.cfg`): `lock_camera`, `music_volume`, `sfx_volume`, `voice_volume` (linear 0–1). Single source of truth for volumes — emits `settings_changed`, never touches `AudioServer` itself. |
| `AudioManager` | The single entry point for all sound (§9). Owns every audio player (music A/B crossfade, UI pool, voice, announcer, stinger, 16-voice positional SFX pool + 4 flat SFX voices), scans `data/sounds/` into id-keyed `SoundData` (same scan/`.remap` pattern as `CardDB`), applies bus volumes from `Settings`. **Presentation-only, client-side** — the one autoload that deliberately holds nodes; it is never called from the pure-logic autoloads (`BattleManager`, `EnergySystem`, `HealingSystem`, `HeroAI`). Listed directly after `Settings` in `project.godot` because its `_ready()` reads it. Replaced the old `Music` autoload (`scenes/music.tscn`, an `AudioStreamPlayer2D` — wrong node type for music). No per-match state → no `reset_match_state()`. |
| `HeroAI` | Per-team HP-threshold hysteresis for the AI-controlled hero (`NORMAL` / `LOW_HP`, 20%→50% band). **Zero scene/UI dependencies by design** — pure state+math, same contract as `EnergySystem`/`HealingSystem`. Doesn't know about pods, positions, targets, or navigation — that decision-making and pathing lives in `hero_dummy.gd`. Own `reset_match_state()`. |

`BattleManager.arena_root` is injected by `arena.gd` each match (autoload has no
scene of its own to parent spawned nodes under).

---

## 3. Data layer

**One `.tres` per card or god (Oct 2026).** A card file is the card *and* its
gameplay data, the same way `hero_zeus.tres` is both the god's card and its
avatar. `CardData` (`scripts/arena/ui/card_data.gd`) is the shared base and is
never used on its own; `UnitData` and `SpellData` extend it.

```
data/
  cards/<pantheon>/
    units/             UnitData   — CardData fields + archetype_scene, max_hp,
                                    damage, attack_cooldown, speed,
                                    target_filter, sprite_frames, attack_type,
                                    attack_range, projectile_scene,
                                    damage_point_ratio, attack_sfx / death_sfx,
                                    unit_count, formation_radius (squad)
      frames/          SpriteFrames
    spells/            SpellData  — CardData fields + spell_type (int),
                                    radius, cast_time, zone_duration,
                                    effect_duration, damage, tick_interval,
                                    slow_multiplier, impact_anim_duration,
                                    sprite_frames
      frames/          SpriteFrames
  heroes/<pantheon>/   HeroData   — id, stats, projectile_scene, sprite_frames,
                                    sounds, + collection fields: rarity (4 =
                                    UNIQUE), obtain_source, faction, domain,
                                    description, forbidden_tags, synergy_tag,
                                    synergy_count, synergy_bonuses,
                                    card_art (Texture2D — the god's big card
                                    art for Card Detail; null = first idle
                                    frame), skill (SkillData)
    frames/            SpriteFrames
    skills/            SkillData  — id, display_name, cooldown, cast_range,
                                    values (tuning dictionary),
                                    description_template ({key} placeholders)
  packs/               PackData   — id, display_name, card_count, faction
                                    filter, rarity_weights (5), guaranteed_
                                    min_rarity, price
  progression/         LevelCurve — max_level, copies per level per rarity,
                                    stat multiplier per level, god attack-speed
                                    multiplier per level (one file, all tuning)
  maps/                MapData    — id, display_name, release_ready, map_scene,
                                    bounds (Rect2), camera_edge_margin,
                                    camera_edge_pan_speed_max, hero_spawn_player,
                                    hero_spawn_enemy
  sounds/              SoundData  — id, streams (variants), bus, priority, volume_db,
                                    volume_jitter_db, pitch_jitter, max_instances,
                                    min_interval, positional, max_distance (§9)
```

**`CardData` base fields** (every unit and spell card): `id`
(`card_<pantheon>_<name>`), `display_name`, `cost`, `scroll_texture`, and the
collection fields `rarity` (int 0–3), `obtain_source` (int), `faction`
(pantheon), `domain`, `tags`, `description` (Card Detail lore intro).
`card.unit_data` / `card.spell_data` are **non-exported typed views** on
`CardData` that return the card itself cast to its type, or `null` for the
other kind — so call sites such as `if card.unit_data != null` read the same as
before the merge, and `card.unit_data.unit_count` reaches the squad fields. Card
ids did not change in the merge, so saves, decks, packs and the AI were
unaffected. Creatures without a card yet are ordinary `UnitData` cards with
`obtain_source = 0` (hidden from the encyclopedia, deck pool and packs).

**God skills (`SkillData`, `scripts/arena/skill_data.gd`).** One active skill
per god, a file in `data/heroes/<pantheon>/skills/`, linked from
`HeroData.skill`. `values` holds every tuning number (keys ending in `_pct` are
percentages, e.g. `damage_pct = 220` = 220 % of Attack Power);
`get_value(key)` is the runtime read. `description_template` uses `{key}`
placeholders (plus `{cooldown}` / `{cast_range}`); `get_description()` fills
them through `String.format()` and `format_number()` (220.0 → "220",
0.4 → "0.4"). An unknown placeholder stays visible as `{key}`. Design rules
(start on cooldown, tap-to-fire at the current target within `cast_range`,
AI uses skills too) live in `heroes_greek.md`. The same `values` drive both
the Card Detail text (§8) and the runtime effect (§5 "God skills"), so a
retune changes gameplay and text together. A runtime-only tuning number can
be read with a code default (`get_value(&"knockback_time", 0.2)`) and added to
`values` later without breaking anything — but then it is not in the text.

Resolution chain for a played card:
`card_id → CardDB.get_card() → (UnitData) archetype_scene.instantiate()
→ configure(data, team, stat_mods) → add to arena`, where `stat_mods` is the
multiplier dictionary `BattleManager` builds from the team's manifest (below).

A card with `unit_count > 1` summons a squad: `BattleManager.spawn_unit()` returns
`Array[Node]` and places each unit with a **deterministic** ring offset
(`_formation_offset()`, no RNG) so both clients derive an identical formation from
the same `{card_id, position, team}` message. Squad size (`unit_count`,
`formation_radius`) lives on the unit card itself; a single and a squad version
of the same soldier are two card files (as Hoplite and Phalanx already are).
`BattleManager` also self-registers healing pods (`register_healing_pod()`,
called from each pod's own `_ready()`, same pattern as turrets/bases) and
exposes `get_nearest_ready_healing_pod(team, from_pos)` — strict own-side-first:
falls through to the opposite side only if the caller's own side has no
ready pod. `owning_side` on each pod is derived from its node name at
runtime (`"Player"` in the name → `"player"`), not a scene field — pods
remain fully cross-team usable for the actual heal trigger; `owning_side`
only affects AI seek-preference.
`BattleManager` tracks **protection zones** the same self-register way as
healing pods: `_protection_zones: Dictionary = {"player": [], "enemy": []}`,
populated by each structure's own `_ready()` (`register_protection_zone(zone,
owner_team)`) and cleared by its destruction handler
(`unregister_protection_zone(zone, owner_team)`) — turret/base scripts hold
their zone as an `@export var protection_zone: Rect2`, hand-tuned per
structure per map (no shared formula; see each map scene's per-node values —
`map_authoring_guide.md` has the full checklist).
`get_active_protection_zones(team) -> Array` returns a `.duplicate()` of the
live list (never the internal array itself) — used both by
`is_deploy_position_valid()` and by the UI overlay in §4. `deploy_bounds`
(the map's outer `Rect2`, set by `configure_map()`, §6) and protection zones
are two separate checks: `is_deploy_position_valid(pos, team)` first rejects
anything outside `deploy_bounds`, then rejects anything inside a **currently
active** zone belonging to the opposing team — a destroyed structure's zone
is simply absent from the list, no special-casing needed. `reset_match_state()`
resets `_protection_zones` back to the empty dict alongside the other
per-match registries. `is_card_target_valid()` (spell targeting) does **not**
consult protection zones at all — only `deploy_bounds` — which is what keeps
spells targetable anywhere on the map (`game_design.md` §3.11).
A card is a unit card **or** a spell card by its type (`UnitData` /
`SpellData`), so "both or neither" can no longer happen. Resolution chain for a
played spell: `card_id → CardDB.get_card() → (SpellData) → BattleManager.cast_spell()`.
`SpellData` carries **two separate durations** — `zone_duration` (how long
the area lives on the map) and `effect_duration` (how long stun/root/slow
lasts on a unit that was hit). They are not interchangeable: Storm's zone
outlives the short slow it refreshes each tick, which is what makes leaving
the zone matter. `zone_duration = 0.0` is the "instant" configuration (one
tick at impact, then free) used by Stun and Net.

`MapData` follows the same scan/lookup pattern as the other resource
types: the `MapDB` autoload (§2) scans `data/maps/` into an id-keyed
dictionary at startup, exactly like `CardDB`. `arena.tscn` is a generic
match shell — HUD, `ArenaCamera`, `MoveMarker`, `DenialZoneOverlay`,
`DeployGhost`, and an empty `MapRoot` node — and holds **no** map content
of its own (§4). At the top of `_ready()` it resolves
`map_data = MapDB.get_map(MatchConfig.map_id)`, instantiates
`map_data.map_scene` into `MapRoot` **synchronously** (not
`call_deferred` — the map's structures must self-register into
`BattleManager` before the hero-spawn code later in the same `_ready()`),
then calls `BattleManager.configure_map(map_data)` (sets the mutable
`deploy_bounds`) and `arena_camera.configure_map(map_data)` (sets
`bounds_min`/`bounds_max`/`edge_margin`/`edge_pan_speed_max`).
`MatchConfig.map_id` is set once per match by `PreMatchFlow`, via
`MapDB.get_random_map_id()` — a uniform-random **TEMP** picker used for
testing multiple maps, not real map selection (open question,
`game_design.md` §6). `MapData.release_ready` (default `true`) marks
whether a map belongs in a future real player-facing pool; the TEMP
random picker deliberately ignores it so WIP maps stay visible while
testing — nothing filters on it yet. This is what unifies the two
previously-independent hardcoded bounds systems (§6) into one per-map
resource, and adding a new map is authoring a new `.tres` + a new map
`.tscn` (no script changes — the `MapDB` scan picks it up automatically;
see `map_authoring_guide.md` for the full checklist). Structures
(turrets/bases/healing pods) are **not** part of `MapData` — their
positions and `protection_zone` rects live on the structure nodes
themselves in each map's own `.tscn` (`scenes/arena/maps/<Name>Map.tscn`),
hand-tuned per map (see the protection-zone paragraph above and
`game_design.md` §3.7). The navigation mesh is **not** part of `MapData`
either — it lives in each map scene's own `NavigationRegion2D` (§5
Navigation).

**WIP, Sept 2026 — map visual pipeline is being migrated to tiles, one map
at a time.**
`GreekPlateauMap.tscn` was reworked as the test bed to build the map
entirely from `TileMapLayer`s instead of one background `Sprite2D` + a
single ground-collision `TileMapLayer` — the background `Sprite2D` node is
gone entirely on that map, and it now also carries the map's
`NavigationRegion2D` (§5). `NordPlainsMap.tscn` is **mid-migration** to the
same structure (`Terrain`, `Patches`, `MapBorder`, `NavigationRegion2D`
added) but still also carries its old `Rock`/`Tree`/`Wall` obstacles and
`NavigationObstacle2D`, and its navmesh is not yet correctly set up (see
`map_authoring_guide.md` §0). Don't treat either map as a finished template
for a third map without checking with the author first;
`map_authoring_guide.md` §0 has the running list of what's unresolved
before this becomes the real pipeline (and replaces, rather than sits
alongside, the checklist in that doc's §1–§4).

**Collection fields are plain `int` codes, not enums** (same reason as
`SpellData.spell_type`): `rarity` 0 COMMON, 1 RARE, 2 EPIC, 3 LEGENDARY,
4 UNIQUE (gods); `obtain_source` 0 NONE (test card, never granted or listed),
1 PACK, 2 ACHIEVEMENT, 3 QUEST, 4 EVENT. `obtain_source` says where *additional
copies* come from; the starter grant is a separate list in `PlayerProfile`,
because starter cards must also drop from packs. **Vocabulary:** `faction` is
the pantheon (greek, norse…); `domain` is the cross-pantheon grouping (olympus,
sea, underworld…); `tags` are free labels. A card's effective tags are
`tags + faction + domain` (`DeckRules.card_tags()`).

**Pure helpers (no nodes, no autoload calls — server-portable, same contract
as `EnergySystem`):**
- `LevelCurve` (`scripts/level_curve.gd`, resource) — `copies_to_next(rarity,
  level)`, `get_stat_multiplier(level)`, `get_hero_attack_speed_multiplier
  (level)`. Preloaded as a constant by `BattleManager` and `PlayerProfile`.
- `PackRoller.roll(pack, rng, pool)` — weighted rarity per slot; the last slot
  carries the guarantee; an empty rarity falls to the nearest lower, then
  nearest higher, **never** to a rarity whose weight is 0 (so a 0 % pack can
  never give a god). Pool and RNG are arguments.
- `DeckRules` — `card_tags()`, `is_card_allowed(god, card)` / `find_forbidden()`
  (god-against-card only, default allowed), `build_default_deck()`, the synergy
  trio `count_synergy_cards()` / `is_synergy_active()` /
  `is_synergy_beneficiary()`, and `describe_synergy(god)` (the one UI text for
  a rule).
- `DebugLog.info(tag, text)` — static switch for the `[pack]` / `[profile]` /
  `[synergy]` / `[spawn]` / `[skill]` (and UI `[menu]` / `[frame]`)
  diagnostics, off by default.

**Deck source.** There is exactly one: `PreMatchFlow` copies the active god,
deck and levels from `PlayerProfile` into `MatchConfig`; `card_hand.gd` and
`enemy_card_ai.gd` both build their cycle from `MatchConfig`. Neither scene
holds a deck. Opening `arena.tscn` directly (F6) therefore has no map, god or
deck — start from the main menu.

**Match manifest.** `arena.gd::_ready()` calls
`BattleManager.set_team_manifest(team, hero_id, hero_level, card_levels)` for
both teams **before** spawning the gods. The deck is the key set of
`card_levels`. Synergy is evaluated there, once, and stored
(`synergy_have`, `synergy_active`); `reset_match_state()` clears the
manifests. At the entry points: `spawn_unit()` → `_unit_stat_mods()` (level ×
synergy, keys `max_hp`, `damage`, `speed`, `attack_speed`); `cast_spell()` →
level × `spell_damage` synergy passed to `SpellZone.configure()` as a damage
multiplier; `spawn_hero()` → `_hero_stat_mods()` (level only — synergy never
buffs the god). Scaled values live on the spawned node; shared resources are
never written. The energy-regeneration synergy is an infinite
`EnergySystem` modifier added by `arena.gd`. `get_synergy_status(team)` and
`get_team_hero_data(team)` are the read side for UI. **Attack speed is the
simple version** — `attack_cooldown / m` for units, `recovery_time / m` for
gods; animation and windup are untouched (rework postponed).
---

## 4. Battle scene structure

- `scenes/arena/arena.tscn` — the generic match shell, not map content:
  HUD, `MatchResultBanner`, `ArenaCamera`, `MoveMarker`, `DenialZoneOverlay`,
  `DeployGhost`, and an empty `MapRoot` mount node. Also owns the
  base-destroyed **end sequence** (§9 "End-of-match sequence"). Resolves and instantiates its map at
  runtime (§3) — holds no lanes, structures, or terrain of its own.
  `_unhandled_input` tap-to-move snaps the tapped world position onto the
  navmesh (`BattleManager.snap_to_navigation()`) before handing it to
  `InputR.set_move_target()` and `MoveMarker.show_at()`, so the marker
  always shows the point the hero will actually reach (§5 Navigation).
- `scenes/arena/maps/<Name>Map.tscn` (e.g. `GreekPlateauMap.tscn`,
  `NordPlainsMap.tscn`) — one per map, instantiated into `arena.tscn`'s
  `MapRoot` at runtime. Holds that map's two horizontal lanes; per team:
  Base + 3 turrets (Top, Bot, Base). Structures self-register with
  BattleManager (combat registries **and** their `protection_zone` Rect2,
  §3); destroyed structures become wrecks (**no `queue_free()`**), which
  also unregisters their protection zone, permanently opening that slice
  of the map (`game_design.md` §3.7). See `map_authoring_guide.md` for the
  full checklist to add a new one.
  **Tile-built structure (`GreekPlateauMap.tscn`; `NordPlainsMap.tscn`
  mid-migration — see the note in §3 and `map_authoring_guide.md` §0):**
  ground is a `Terrain/TileMapLayer` (no background `Sprite2D`), obstacles
  split into a visual `Obstacles/TileMapLayer` plus collision-only
  `Patches/*` instances (`LargePatch.tscn`/`SmallPatch.tscn`, both
  inheriting a script-free base scene, `ObstaclePatch.tscn` —
  `StaticBody2D`, `collision_layer=4`/`collision_mask=0`, one
  `CollisionPolygon2D` in `Solids` build mode seeded with a small
  placeholder square so it's never an invalid empty polygon), a
  `MapBorder` node (`scenes/arena/maps/MapBorder.tscn` /
  `scripts/arena/map_border.gd`) giving the map an actual outer physical
  boundary, and one `NavigationRegion2D` (§5 Navigation). `Patches`,
  `PlayerStructures` and `EnemyStructures` are in the `nav_obstacle`
  group — that's what carves the navmesh holes; `MapBorder` is
  deliberately not.
  **Old structure (NordPlains before its migration):** background
  `Sprite2D`; one ground-collision `TileMapLayer`; `Obstacles` with
  `Rock`/`Tree`/`Wall` instances; an unconfigured `NavigationObstacle2D`
  that nothing reads (a leftover — safe to delete once the migration is
  done); no physical outer boundary, only the logical `MapData.bounds`
  rectangle (camera clamp + deploy check).
- `scenes/arena/units/melee_unit.tscn` and `scenes/arena/units/ranged_unit.tscn`
  (Sept 2026) — two sibling archetype scenes (CharacterBody2D + Hurtbox +
  AttackRange + AggroRange + AnimatedSprite2D + HealthBar + TargetMarker +
  `NavAgent`), **both attaching the same `unit.gd` script** — they differ only
  in scale and their own scene-baked `AnimatedSprite2D`/`AttackRange` defaults
  (editor-preview/crash-prevention values only, same footgun as
  `player.tscn`/`hero_dummy.tscn`, see `hero_authoring_guide.md` §1 —
  `configure()` always overwrites both from `UnitData` at spawn). Melee vs.
  ranged combat *behavior* is a data branch inside `unit.gd`
  (`UnitData.attack_type`), not a script fork — see §5 and
  `unit_authoring_guide.md`. Siege archetypes, if they diverge in movement/
  targeting rather than just attack resolution, would be a genuine new
  sibling script; a third *attack type* would not. **Both scenes must carry
  the `NavAgent` child** — `unit.gd` resolves it with `@onready`, so a scene
  missing it crashes on spawn (§6). `ranged_unit.tscn`'s root node is still
  named `MeleeUnit` (duplication leftover, harmless, rename when convenient).
- `scenes/arena/player.tscn` — locally-controlled hero. Carries a `NavAgent`
  (`NavigationAgent2D`) child (§5 Navigation).
- `scenes/arena/hero_dummy.tscn` (`hero_dummy.gd`) — AI-controlled enemy hero
  avatar. Movement/targeting/combat logic ported from `player.gd` (same
  fields, `find_nearest_enemy()`/`_try_fire()`/`fire_bolt()`, same
  animation helpers), driven instead by `HeroAI`'s hp-state output:
  `NORMAL` → march toward nearest enemy structure (`BattleManager.
  get_nearest_structure()`, interval-refreshed same as `unit.gd`); `LOW_HP`
  → seek nearest ready healing pod (`BattleManager.
  get_nearest_ready_healing_pod()`), falling back to retreat toward own
  spawn if no pod anywhere is ready (retreat point snapped onto the navmesh,
  §5). Walking onto a pod triggers the heal automatically via the pod's
  existing `area_entered` handler — no explicit "use pod" call from the AI.
  All three destinations go through the single `_steer_towards()`, which
  follows the navmesh via its own `NavAgent` child. Card-play AI lives in
  `enemy_card_ai.gd`. Now also wires `target_marker` (see §6).
  Both expose `configure(data, team)`, `die()`, `revive()`.
- `scenes/arena/DeployGhost.tscn` (`deploy_ghost.gd`) — world-space drag-to-deploy
  preview: a translucent circle at the drop position, green = legal, red = not.
  Drawn in `_draw()` (no assets). Sibling of `MoveMarker`, driven by `arena.gd`
  from `CardHand` signals (CardHand is in a CanvasLayer; the ghost is world-space).
  One child, `ScrollAnim` (`AnimatedSprite2D`, no frames assigned in the scene) —
  plays the spell's `"drag"` animation just above the circle while dragging.
  `configure_for_card()` runs **once per drag** (from `deploy_preview_started`)
  and sets both the radius and the animation: spell cards get the spell's *real*
  `radius` so the circle shows exactly what will be hit; unit cards get the flat
  `unit_radius` and no animation. Per-frame position still comes through
  `deploy_preview_updated`, whose signature is unchanged.
- `scenes/arena/DenialZoneOverlay.tscn` (`denial_zone_overlay.gd`) — world-space
  UI hint, sibling of `DeployGhost`, drawn in `_draw()` at a fixed
  `position = Vector2(0,0)` (it draws directly in the zones' own world-space
  coordinates, unlike `DeployGhost` which recenters on the drag point). Cheap
  per-zone approach instead of a shader: `show_for_card(card)` (called from
  `deploy_preview_started`) iterates
  `BattleManager.get_active_protection_zones(enemy_team)` and `draw_rect()`s
  each one directly — no composite "hole" geometry, so overlapping zones look
  slightly darker where they overlap (accepted cosmetic trade-off; no live
  per-frame re-evaluation mid-drag). `show_for_card()` early-outs to
  `visible = false` when `card.spell_data != null`, since spells aren't
  restricted by protection zones (`game_design.md` §3.11) — only unit-card
  drags show the overlay. `hide_zones()` (from `deploy_preview_ended`) hides
  it again. `DRAGGING_TEAM` is currently a hardcoded `"player"` const, same
  TEMP assumption as `card_hand.gd` (only the local player drags cards today).
- `scenes/arena/HealingPod.tscn` (`healing_pod.gd`) — static pickup, `Area2D`
  with `collision_layer=0`, `collision_mask=24` (bits 4+5 — same hurtbox mask
  pattern as `LightningBolt`). Team is resolved on `area_entered` from the
  entering Area2D's `player_hurtbox`/`enemy_hurtbox` group, not layer bits —
  cross-team usable by design (either hero can use either pod). Activation is
  a `Sprite2D` texture swap (`pod_active.png`/`pod_inactive.png`), no
  `AnimatedSprite2D`. Cooldown and HoT state live in `HealingSystem`; the node
  is sensor + visual only. 4 static placements per map scene (inside
  `PlayerStructures`/`EnemyStructures`), one per lane per side
  (`HealingPodPlayerTop/Bot`, `HealingPodEnemyTop/Bot`). Being an `Area2D`,
  a pod is ignored by the navmesh bake even though its parent container is
  in the `nav_obstacle` group — pods stay walkable, which is required.
- `scenes/arena/SpellZone.tscn` (`spell_zone.gd`) — the **single** runtime
  node behind every spell. `Node2D` with a single `CastAnim`
  (`AnimatedSprite2D`) child, **no `Area2D` and no
  collision shape**: targeting is a per-tick radius query, not physics
  overlap. Two phases driven in `_process`: `PHASE_CAST` (lasts
  `cast_time`, draws a warning circle, applies nothing) then `PHASE_ZONE`
  (first tick fires *exactly* at impact, then every `tick_interval` for
  `zone_duration`, re-querying targets each time). `zone_duration = 0.0`
  → one tick, then `queue_free()`. Spawned by `BattleManager.cast_spell()`
  with the same `instantiate() → configure() → add_child()` contract units
  and heroes use. During `PHASE_CAST`, `CastAnim` plays the spell's `"cast"`
  animation stretched via `speed_scale` to finish *exactly* at impact, then
  stops and hides — the placeholder `_draw()` circle (orange = casting,
  purple = active zone) carries the zone phase alone until impact/duration
  art exists.
- `scenes/arena/ui/EnergyBar.tscn` (`energy_bar.gd`) — player energy bar in the
  HUD. Polls `EnergySystem.get_energy("player")` each frame for the fill. `Bar`
  is a `TextureProgressBar` (gold fill texture, left-to-right) behind a
  `FrameOverlay` stone frame, with an `EmptyBg` ColorRect showing through empty
  cells; the count label updates from `energy_int_changed`. `bar` stays typed
  `Range`, so the swap from the placeholder `ProgressBar` needed no script change.
- `scenes/arena/ui/SynergyIcon.tscn` (`synergy_icon.gd`, `class_name
  SynergyIcon`) — a `Button` in the HUD beside the energy bar, left of the
  hand. Shows the player's synergy count; grey when the deck threshold is not
  met, gold and pulsing when it is; a tap toggles a tooltip (auto-hides) with
  the `DeckRules.describe_synergy()` text. Being a `Button`, it consumes the
  tap so it never reaches tap-to-move. Configured once by
  `arena.gd` (`hud.synergy_icon.configure("player")`) after the manifests are
  set — the state cannot change during a match. Placeholder look, no art.
- `scenes/arena/ui/SkillButton.tscn` (`skill_button.gd`, `class_name
  SkillButton`, Oct 2026) — the local god's skill button: a round placeholder
  `Button` above the energy bar (bottom-right, clear of `CardHand`). Grey with
  the remaining seconds while on cooldown, gold with the skill name when
  ready, disabled while the god is dead, hidden when the god has no skill or
  `SkillEffects.is_implemented()` is false. `configure(hero)` is called once by
  `arena.gd` right after `spawn_hero(... "player" ...)`; `_process()` polls
  `hero.get_skill_cooldown_left()`; `pressed` → `hero.try_cast_skill()`.
  `process_mode = PAUSABLE` (§6 HUD child pitfall). A `Button`, so the tap
  never reaches tap-to-move.
- Skill FX — `ChainLightningFx` / `TidalWaveFx`
  (`scripts/arena/skills/chain_lightning_fx.gd`, `tidal_wave_fx.gd`) —
  code-built `Node2D`s added under `BattleManager.arena_root`, drawn in
  `_draw()` (zigzag polyline / translucent cone), `z_index = 50`, fade out in
  ~0.25–0.35 s and `queue_free()`. Placeholder visuals; scene-owned, so no
  reset code.
- `scenes/hud/HUD.tscn` (CanvasLayer) — TouchScreenButtons (pause, recenter),
  `CardHand` (hand + draw cycle in `card_hand.gd`; `play_card(slot_index, world_pos)`
  is the single card-play entry point — drag-to-deploy calls it today, future
  double-tap and the network handler call the same function — which now also
  spends energy via `EnergySystem.try_spend()` and refuses unaffordable plays; emits
  `deploy_preview_started` (once, at drag start, carrying the `CardData`) /
  `deploy_preview_updated` / `deploy_preview_ended` for `arena.gd` to drive the
  DeployGhost), `EnergyBar`, `SynergyIcon`, `Minimap`, `MatchInfoBar` (timer label,
  tower icons, two `RespawnCounter`s driven by BattleManager signals). The hand's
  deck comes from `MatchConfig` (§3), not from `CardHand.tscn`. The HUD also
  instances `SettingOverlay` as the pause screen (§8 "Framed overlays").
  `play_card()` branches on card type: `unit_data` → `BattleManager.spawn_unit()`,
  `spell_data` → `BattleManager.cast_spell()`. Both the live drag preview and
  the release check call `BattleManager.is_card_target_valid(card, pos, team)`.
- `scenes/ui/PreMatchFlow.tscn` (`prematch_flow.gd`) — placeholder pre-match
  flow: a "searching for battle" panel then a versus panel, each ~1s, then
  `change_scene_to_file(arena.tscn)`. Reached from the main-menu Battle card
  (§8). Also resolves this match's map: calls `MapDB.get_random_map_id()` into
  `MatchConfig.map_id` once, and shows the resolved `MapData.display_name`
  on the finding screen (§3). Faction/avatar are ColorRect placeholders
  pending assets.
- `scenes/arena/audio/AmbientEmitter.tscn` (`ambient_emitter.gd`,
  `class_name AmbientEmitter`) — map ambient sound, hand-placed in each map
  scene under an `Ambient` `Node2D` (same authoring style as turrets/pods).
  `LOOP` mode = bed on its own `AudioStreamPlayer` (fade-in, never through
  the SFX pool); `RANDOM` mode = one-shot via `AudioManager.play_sfx()` every
  `min_interval`–`max_interval` s after a random `first_delay`. Lives with
  the map scene, so match end / scene change clean it up — no reset code
  (§9, `map_authoring_guide.md` §2.11).
- `MatchAnnouncer` (`scripts/arena/match_announcer.gd`, plain `Node`,
  added by `arena.gd::_ready()` via `add_child(MatchAnnouncer.new())`, same
  as `EnemyCardAI`) — self-subscribes to `BattleManager.hero_died` and calls
  `AudioManager.play_announcer()`; today only "first blood" (first hero
  death of the match, either side). Per-match state lives on the node and
  resets with the arena. `arena.gd::_exit_tree()` calls
  `AudioManager.stop_announcer()` so no line or music duck leaks into the menu.
- `scenes/arena/ui/MatchResultBanner.tscn` (`match_result_banner.gd`,
  `class_name MatchResultBanner`) — the VICTORY/DEFEAT banner of the end
  sequence. Its own `CanvasLayer` (`layer = 20`), a sibling of `HUD` in
  `arena.tscn` — **not** inside the HUD, because the HUD is hidden for the
  whole sequence. Nodes: `Band` (dark full-width strip), `Band/Title`,
  `Band/Subtitle`, `Fade` (full-screen black for the final fade). Everything
  is `mouse_filter = IGNORE`. One entry point, `show_result(winner,
  total_duration)`, called by `arena.gd`; it knows nothing about
  `BattleManager` and connects no signals. Code/fonts only, no textures —
  node names are kept stable so art can be swapped in without script changes.
  Its title style (CinzelDecorative-Black, gold, black outline) is also the
  title style of the framed menu screens (§8).

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
  not per frame. Separation steering with cached interval updates. Units only
  collide with layer 4 (`collision_mask = 4`: structures/obstacles/border) —
  not with each other or with heroes; separation is the only thing spacing a
  squad apart.
- **Navigation (Sept 2026) — every mover follows a baked navmesh; the
  navmesh only picks the direction, never the velocity.**
  - *Map side.* Each map scene carries one `NavigationRegion2D`. Its
    `NavigationPolygon`'s walkable **outline** is hand-drawn to match the
    `MapBorder` shape; the **holes** are baked from source geometry:
    `Parsed Geometry Type = Static Colliders`, `Parsed Collision Mask = 4`,
    `Source Geometry Mode = Groups With Children`, group `nav_obstacle`
    (on `Patches`, `PlayerStructures`, `EnemyStructures`). `MapBorder` is
    intentionally outside the group (§6). Agent radius is the default 10 px
    (hero body circle is 7 px; unit 16×16 box reaches ~11 px at the corners —
    accepted, they just slide past corners). Baked **at edit time, static**:
    nothing on the map changes topology mid-match (structure wrecks never
    `queue_free()`), so there's no runtime rebaking.
  - *Mover side.* `player.tscn`, `hero_dummy.tscn`, `melee_unit.tscn` and
    `ranged_unit.tscn` each carry a `NavAgent` (`NavigationAgent2D`) child —
    `path_desired_distance = 4`, `target_desired_distance = 8`, avoidance
    **off**. Each of the three scripts has its **own verbatim copy** of
    `_nav_direction_to(goal) -> Vector2` (same deliberate duplication as the
    status effects, §6). It returns only a unit direction; each script's
    existing pipeline (windup lock, root, slow, `velocity`, `move_and_slide()`,
    animation) is unchanged. `NavigationAgent2D.velocity` / `velocity_computed`
    are not used anywhere.
  - *Where it plugs in.* `player.gd`: `get_move_input()` (tap-to-move) and
    the `primary_target` chase branch. `hero_dummy.gd`: inside
    `_steer_towards()`, so march, pod-seek and retreat all path. `unit.gd`:
    inside `_steer_towards()`, where the navmesh direction replaces only the
    **seek** term — separation is still added on top, unchanged.
  - *Repath rule.* The agent's `target_position` is only re-sent when the
    goal moved more than 16 px (`NAV_REPATH_DIST_SQ`) since the last one
    (`_nav_goal`), so chasing a moving target doesn't recompute the path
    every frame. `_nav_goal = Vector2.INF` forces a fresh path — reset on
    tap-to-move arrival and `on_new_move_command()` (player), and in
    `die()`/`revive()` (both heroes). Units never revive, so they don't reset.
  - *Goals inside a hole.* A structure sits inside a navmesh hole, so the path
    ends at the hole's edge; when `is_navigation_finished()` is true the helper
    falls back to direct steering for the last few pixels and the existing
    `AttackRange` overlap check takes over. No snapping of structure/pod goals.
  - *Queries.* `BattleManager.has_navigation()` is false when the current map
    has no `NavigationRegion2D` **and** on the first physics frame after load
    (`map_get_iteration_id() == 0`, server not synced yet) — every
    `_nav_direction_to()` then falls back to straight-line steering, i.e. the
    pre-navmesh behavior. `BattleManager.snap_to_navigation(pos)` returns the
    closest navmesh point (unchanged without a navmesh); used for the
    tap-to-move target (`arena.gd`) and the AI hero's retreat point (a spawn
    point inside the 10 px agent-radius margin would otherwise never satisfy
    the 8 px arrival check).
  - *Not built yet.* Deploy validation doesn't consult the navmesh —
    `is_deploy_position_valid()` still only checks bounds, own half and
    protection zones, so a unit card can be dropped inside a patch (next
    step: reject positions off the navmesh). No RVO avoidance — deliberately
    off; if squads clump at chokepoints the first lever is separation
    tuning, RVO is a separate decision (it changes how velocity is owned).
- **Minions get a two-phase attack windup too (Sept 2026), but a
  deliberately simpler one than heroes'.** `UnitData.attack_type`
  (MELEE/RANGED) and a data-driven `attack_range` (replacing what used to
  be a scene-baked `AttackRange` radius) drive `_process_engaging()`:
  on entering range, the unit winds up for `damage_point_ratio` (same
  0.0-1.0 semantics and 0.7 default as `HeroData`) of the live-derived
  `"attack"` animation duration, then resolves — direct `take_damage()` for
  MELEE, or spawns the same `projectile.tscn` heroes already fire for
  RANGED — and `attack_cooldown` (unchanged field, now playing the role
  `HeroData.recovery_time` plays for heroes) starts counting from that
  point. Unlike heroes, this is implemented as a **plain countdown
  (`windup_left`) inside the existing synchronous `_physics_process` state
  machine, not an `await` coroutine** — `unit.gd` had no async patterns
  before this and shouldn't gain one just for a windup timer. The payoff:
  since nothing disables `_physics_process` during a minion's windup (unlike
  heroes' `set_physics_process(false)`), the pre-existing stun
  freeze-and-resume behavior (see §6) already covers a stun landing
  mid-swing correctly, with no direct-cancel hook needed. Minions also get
  **no** cancel-on-new-command mechanic — they have no player-issued
  commands to cancel on, and no AI retreat state either; a target leaving
  `attack_range` mid-windup is left to the existing march-state fallthrough
  (`ENGAGING → CHASING` silently abandons the pending windup, no hit, no
  explicit cancel-animation) rather than a built interrupt system. Full
  detail in `unit_authoring_guide.md` §2.2.
- **Hero attacks are an interruptible two-phase cast-point (Sept 2026).**
  Targeting priority is unchanged: manual primary target (tap) with chase,
  auto-target fallback without chase. The swing itself now splits at
  `HeroData.damage_point_ratio` (0.0-1.0, default `0.7`) of the live-derived
  cast-point (`attack_left`'s `frame_count/speed`, same derivation as
  always). Before that fraction elapses the hero hasn't committed — a
  genuinely new command (a new tap-to-move, or an explicit tap on a
  *different* target) cancels the swing for free: no damage, `fire_left`
  reset to 0, animation snapped to idle, movement unlocked immediately.
  Re-issuing the same target mid-swing is a no-op, not a cancel. At/after
  the damage point the hit lands right then and movement unlocks
  immediately either way, with `recovery_time` now counting from the
  damage point rather than the old full-animation end. This replaced a
  single monolithic movement-lock for the whole `attack_left` duration
  with no way to interrupt it — the cause of a "hero feels rooted mid-fight"
  bug (tap-move, arrive, auto-fire on a newly-arrived enemy, then be stuck
  for the full swing before the next tap-move could even register). Full
  mechanic and per-hero tuning guidance live in `hero_authoring_guide.md`
  §2.2 — this doc covers the *why*, that one covers the *how to tune it
  per hero*.
- **AI retreat interrupts an in-progress swing.** `hero_dummy.gd`'s
  `HeroAI` NORMAL⇄LOW_HP hysteresis flip cancels a mid-swing attack via
  the same cancel path player commands use, hooked into `take_damage()`
  rather than `_physics_process` (see §6 for why). Meant to be the first
  of several future AI "interrupt and reconsider" triggers (e.g. spotting
  a higher-priority target) — only the HP-retreat one exists today.
- **God skills (Oct 2026) — cooldown on the hero, effect in one shared place.**
  - *Split.* Cooldown state and the cast entry point are **duplicated** in
    `player.gd` and `hero_dummy.gd` (thin: `skill`, `skill_cd_left`,
    `get_skill_cooldown_left()`, `can_cast_skill()`, `try_cast_skill()`,
    `_reset_skill_cooldown()`), same deliberate duplication as the status
    effects. The **effects** are written once, in `SkillEffects`
    (`scripts/arena/skills/skill_effects.gd`, static functions only, no
    stored state except a warn-once set): `is_implemented(skill)`,
    `cast(skill, caster, caster_team, target, attack_power) -> bool`, plus the
    shared target helpers `is_alive()`, `find_nearest_target()`,
    `pick_cast_target()`, `skill_damage()`, `enemy_team_of()`. `cast()`
    dispatches on `skill.id` with `if/elif`; an unknown id warns once and
    returns `false`. Tuning is read only through `skill.get_value()`.
  - *Cooldown.* Starts full at spawn (`configure()`) and again on every
    `revive()`. Ticks in `_process`, **not** `_physics_process` (a locked
    attack windup and the spawn animation disable physics, and the cooldown
    must not pause for them); doesn't tick while dead; keeps ticking while
    stunned; pauses with the game.
  - *Cast rules.* `can_cast_skill()` is false when the skill is missing or not
    implemented, on cooldown, the god is dead or stunned, the match is over,
    or there is no target. Target = the player's `primary_target` if it's a
    registered, alive enemy within `cast_range`, otherwise the nearest alive
    enemy within `cast_range` (center-to-center, candidates from
    `get_targets_in_radius()`, so bases are never targets). The AI uses the
    nearest rule only. A cast is **instant** (no skill windup or animation
    yet): it cancels a pending auto-attack windup, faces the target, calls
    `SkillEffects.cast()`, and starts the cooldown only if that returned
    `true` — a refused cast costs nothing.
  - *AI.* `hero_dummy.gd` casts whenever `can_cast_skill()` is true, in both
    NORMAL and LOW_HP states (first pass, no cluster scoring).
  - *Attack Power* = the caster node's level-scaled `projectile_damage`;
    damage = `maxi(1, roundi(AP × pct / 100))`.
  - *Implemented:* **Zeus — Chain Lightning**: hit the target, then up to
    `jumps` more (1 + 5 = 6 targets) to the nearest not-yet-hit alive enemy
    within `jump_range` of the last hit; damage falls off multiplicatively per
    jump (220 → 176 → 141 %…); every hit is stunned 0.4 s and a turret also
    gets `interrupt_shot()` (`fire_left = fire_cooldown`, called only by this
    skill — the Stun spell is unchanged). **Poseidon — Tidal Wave**: a cone of
    `cone_angle` / `wave_range` aimed at the target; every enemy inside takes
    flat damage, then a slow (`1 - slow_pct/100` for `slow_duration`) and a
    knockback of `knockback` px radially away from Poseidon over
    `knockback_time` (code default 0.2 s). Turrets take damage only. Both
    resolve in one frame, deterministically. The other ten gods' skills are
    not implemented (no button, the AI never casts).
  - *Adding a skill* = one `if/elif` branch + one `_<skill>()` function in
    `SkillEffects` and its id in `is_implemented()`; new mechanics it needs
    (shield, charm, summon…) go where their kind already lives (a status
    effect → the three mover scripts).
- **Knockback (Oct 2026)** is the fourth status effect, next to stun/root/slow
  in `unit.gd`, `player.gd`, `hero_dummy.gd`: `knockback_left`,
  `knockback_velocity`, `apply_knockback(direction, distance, duration)`. A new
  knockback replaces a running one. In `_physics_process` its branch sits
  **above** the stun early-return: it moves the mover with `move_and_slide()`
  (so obstacles, structures and the border stop it, `collision_mask = 4`),
  ignores root and slow, and also moves a stunned target. `apply_knockback()`
  resets `_nav_goal` (stale path) and cancels the swing in progress — heroes
  through `_cancel_attack_windup()` (a locked windup disables
  `_physics_process`, so the push would never run otherwise), units by
  clearing `windup_left` / `_swing_target` (their melee hit doesn't re-check
  range on landing, so a pushed unit would still hit from 60 px away).
  `revive()` clears any leftover knockback. Turrets and bases have no
  `apply_knockback()` and are never moved.
- Hero death: hide + disable (collision & hurtbox zeroed deferred → attackers get
  `area_exited` and disengage), unregister, respawn via BattleManager countdown.
- Range checks use `distance_squared_to()`.
- **Deploy zone:** `BattleManager.is_deploy_position_valid(pos, team)` is the single
  source of truth — the live drag preview (circle colour) and the spawn on release
  both call it, so they cannot disagree. Today: inside `DEPLOY_BOUNDS` and on the
  team's own half (midline `x = 0`). It is **positional only** (takes no `card_id`);
  energy affordability is a *separate* check and is deliberately NOT folded in here,
  so the red circle never conflates "bad spot" with "can't afford". Future zone
  rules (expansion on turret kill, obstacles / off-navmesh rejection) go inside
  this function.
  - **Spell targeting:** `BattleManager.is_card_target_valid(card, pos, team)`
  is the single source of truth for *both* card types and wraps (never
  modifies) `is_deploy_position_valid()`. Spells: inside `DEPLOY_BOUNDS`
  only, either half. Units: the existing own-half rule, untouched.
- **AoE queries:** `BattleManager.get_targets_in_radius(pos, radius, affected_team)`
  is the shared radius query — **team-scoped by parameter, never
  position-only**. `SpellZone` passes the caster's *opposing* team, so
  spells can't friendly-fire. Public (no leading underscore) because it is
  called from outside the autoload; future AoE unit attacks should call this
  same helper rather than rolling their own overlap scan.
- **Spell effects are a re-query per tick, never a snapshot.** `SpellZone`
  calls `get_targets_in_radius()` fresh on every tick, so a unit that walks
  into an active Storm gets hit and one that walks out stops being hit.
  Holding a target array across time was the *old* model and was deliberately
  removed — if a future spell needs stick-to-the-target behaviour
  (poison/bleed), that belongs as per-unit state on the victim, like the
  status timers, not as an array held by the caster.
- **`cast_spell()` applies nothing.** It validates the card and spawns a
  `SpellZone`; all timing and all effect application live on that node. This
  keeps every spell's lifetime bound to the arena scene tree.
- **Status effects** live as plain per-instance state (`stun_left`,
  `root_left`, `slow_left`, `slow_multiplier` + `apply_stun()` /
  `apply_root()` / `apply_slow()`) duplicated **independently** in
  `unit.gd`, `player.gd`, and `hero_dummy.gd` — no shared base class, same
  principle as the HealingSystem signal hooks. Stun short-circuits at the
  top of `_physics_process` (movement *and* attack cooldown both freeze);
  root zeroes movement only, inside the steering function; slow multiplies
  the velocity magnitude. None of the three interacts with navigation: the
  agent's path simply waits while the mover is stunned/rooted and resumes
  afterwards. **Sept 2026: `player.gd`/`hero_dummy.gd`'s
  `apply_stun()` additionally cancels a mid-swing attack outright (see the
  bullet above and §6) — this is no longer byte-identical to `unit.gd`'s
  version. `unit.gd` gained its own windup (`windup_left`, see above) but
  deliberately did NOT gain an equivalent cancel call: its windup is a
  plain `_physics_process` timer rather than an `await` coroutine, so the
  existing freeze-and-resume stun behavior already pauses it correctly —
  adding a direct cancel there would be solving a problem `unit.gd` doesn't
  have.**
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
- **Resolved:** the above starvation is why drag-to-deploy needed its own
  camera hook instead of reusing `arena_camera.gd`'s pan handler. `ArenaCamera`
  now exposes `begin_deploy_pan()` / `update_deploy_pan(screen_pos)` /
  `end_deploy_pan()`, driven from `arena.gd`'s existing
  `deploy_preview_started` / `deploy_preview_updated` / `deploy_preview_ended`
  handlers rather than from raw input — `deploy_preview_updated` now also
  carries the drag's screen position (not just world position) specifically
  so the camera can do screen-edge proximity panning without ever needing the
  starved input events. Runs independently of `Settings.lock_camera` (checked
  in `_physics_process` *before* the lock gate); only the post-release
  behaviour branches on lock state, and does so by reusing the existing
  `_return_timer`/`_return_ramp`/`return_delay`/`return_ramp_time` fields
  rather than adding a parallel return mechanism.
- **`Camera2D`'s native `limit_left`/`limit_right`/`limit_top`/`limit_bottom`
  are a second, engine-level clamp — separate from `arena_camera.gd`'s own
  `bounds_min`/`bounds_max` + `_clamp_to_bounds()`.** Both can be active at
  once, and the engine's native limit wins if it's more restrictive, which
  makes changing `bounds_min`/`bounds_max` in the Inspector look like it does
  nothing. `arena_camera.gd` now forces the native limits wide open in
  `_ready()` so `bounds_min`/`bounds_max` is unconditionally the only clamp
  that applies, regardless of whatever `limit_*` values happen to be saved on
  the `Camera2D` node (easy to inherit by duplicating a scene, since it's a
  separate Inspector section from the script's own exported vars).
- **Resolved:** the two independently-hardcoded bounds systems referenced
  above (native `Camera2D` limits vs. the script's own `bounds_min`/
  `bounds_max`) are now both driven from one place — `MapData.bounds`,
  applied via `arena_camera.configure_map(map_data)` — and
  `BattleManager.deploy_bounds` (formerly a `const DEPLOY_BOUNDS`, now
  mutable) is set from the same resource via
  `BattleManager.configure_map(map_data)`, both called once from
  `arena.gd._ready()`. One `MapData.tres` per map now fully describes bounds,
  camera pan tuning, and hero spawn points (§3).
- **`ArenaCamera`'s initial `position`/`zoom` are NOT per-map.** They're
  hardcoded on the `Camera2D` node inside `arena.tscn` (the shared shell) —
  `configure_map()` only ever touches `bounds_min`/`bounds_max`/
  `edge_margin`/`edge_pan_speed_max`. Works today because both existing
  maps (`GreekPlateauMap`, `NordPlainsMap`) share the same bounds size; a
  map with meaningfully different dimensions will likely need this
  addressed (a `camera_start_position`/`camera_start_zoom` on `MapData`,
  most likely) — noted in `map_authoring_guide.md` §2.9, not built yet.
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
- Typing a bar reference as `Range` (the shared base of `ProgressBar` and
  `TextureProgressBar`) let the energy bar's placeholder→textured swap happen
  with zero script change — `energy_bar.gd` still only touches
  `min_value`/`max_value`/`value`. Reach for the base class when a UI node is a
  known future art-swap target.
- **A third autoload (`HealingSystem`) also holds per-match state outside
  `BattleManager.reset_match_state()`.** Its OWN `reset_match_state()` must be
  called from `arena._enter_tree()` alongside BattleManager's and
  EnergySystem's. Same pitfall as the EnergySystem reset rule above, third
  owner: every new per-match field in HealingSystem must be reset there, or it
  leaks across matches (stale pod cooldowns, stuck HoT).
- Hero `Hurtbox` groups (`player_hurtbox`/`enemy_hurtbox`) — added for
  collision-layer/team wiring — turned out reusable as a plain team-detection
  signal for non-combat systems too, not just combat targeting:
  `HealingPod._on_area_entered()` reads the group off the entering Area2D to
  resolve team, no layer-bit math needed. Worth reaching for before inventing
  a parallel team-tag mechanism.
- **Autoload enums can't be used as type annotations or `match` patterns.**
  `HeroAI.State` can't do `var s: HeroAI.State` or `match s: HeroAI.State.X:`
  — an autoload is a singleton *instance*, not a `class_name`, so its enum
  isn't a real type in that sense. Runtime access like
  `HeroAI.State.LOW_HP` in expressions/comparisons is fine; cache the
  value as untyped/`int` and branch with `if`/`elif` instead of `match`.
- **An autoload's `get_tree().node_added` listener never sees the boot
  scene.** At startup the autoloads *and* the main scene (`MainMenu.tscn`)
  are all under `root` before the SceneTree initializes; Godot runs
  `_enter_tree` (which emits every `node_added`) for the whole tree first
  and only then `_ready`. So a listener connected in an autoload's
  `_ready()` misses every node of the first scene — that's why MainMenu
  buttons had no tap sound while later scenes did (confirmed in a minimal
  Godot 4.7 headless repro). Fix/pattern: after connecting, also walk the
  nodes already present once (`get_tree().root.find_children("*", "",
  true, false)`) through the same handler, with an idempotency guard
  (`AudioManager` uses meta `_ui_sfx_wired`). Applies to any future
  "auto-wire every X" autoload.
- **Looping sounds never go through a stealable voice pool.** A loop would
  hold a pool voice forever, and priority stealing would silence it
  permanently. Ambient beds own their own `AudioStreamPlayer`
  (`AmbientEmitter` LOOP mode); only finite one-shots use `play_sfx()`.
  Corollary: a one-shot `.ogg` imported with `loop=true` (Godot's OGG
  default can be on) plays forever and pins a voice — check the Import dock
  when adding any one-shot OGG (`amb_greek_cymbals.ogg` hit this).
- **Attack sounds fire at the damage point, not at swing start.** Hero and
  unit `attack_sfx` play where the hit lands (melee) or the projectile is
  released (ranged) — a hero's windup is cancelable (§5), and a swing-start
  sound would play for swings that never happened.
- **The match result is logic; the ending is presentation.** When a base
  falls, `BattleManager.on_base_destroyed()` still decides the winner and
  emits `match_ended` in the same frame — nothing in `BattleManager` waits.
  The 3.5 s end sequence (camera, banner, fade, delayed scene change) lives
  entirely in `arena.gd` / `ArenaCamera` / `MatchResultBanner`. Anything
  that must stop acting once the result exists (card plays, future network
  handlers) gates on `BattleManager.is_match_over()`, never on whether the
  scene has changed yet. Same split as audio: a future server decides the
  result; each client plays its own ending.
- **`Control.pivot_offset` must be set after layout.** Scaling a `Control`
  from its center (the banner's band/title "slam") needs `pivot_offset =
  size / 2`, and `size` is only valid once the container layout has run.
  `MatchResultBanner` sets its pivots inside `show_result()` (the node has
  been in the tree, hidden, since the arena loaded) — never hardcode pixel
  pivots, they break on other aspect ratios (`stretch/aspect = "expand"`).
- **Deleting a resource that a scene still references can make Godot
  embed it into that scene.** When the old `assets/music/music_menu.mp3` was
  deleted while `scenes/music.tscn` still pointed at it, the editor re-saved
  `music.tscn` with the whole MP3 inlined as a `PackedByteArray` sub-resource
  (309 B → 6.3 MB), and with `export_filter = "all_resources"` that ships in
  the APK. Delete the *referencing* scene first (or in the same FileSystem
  selection), then the asset — and check file sizes afterwards.
- **A fourth autoload (`HeroAI`) holds per-match state outside
  `BattleManager.reset_match_state()`.** Same pitfall as `EnergySystem`/
  `HealingSystem`: its own `reset_match_state()` must be called from
  `arena._enter_tree()` alongside the other three, or the low-HP hysteresis
  flag leaks across matches.
- `hero_dummy.tscn`'s `TargetMarker` node existed unused in the scene since
  its creation — `melee_unit.tscn` hides its own copy in the scene file,
  but the hero scene didn't, so it was invisibly always-on until wired up
  in `hero_dummy.gd` (`set_targeted()` + hidden in `_ready()`/`die()`).
  Worth double-checking for other copy-pasted scene subtrees with the same
  silently-active-node issue.
- `BattleManager`'s healing-pod registry needs the same `tree_exited`
  cleanup as the unit registries (`register()`), not the "permanent wreck,
  never freed" pattern turrets/bases use — `single_use` pods (future
  portable pods) actually `queue_free()` themselves, unlike turrets/bases.
- **Status effects are duplicated by design, not by omission.** `apply_stun`/
  `apply_root`/`apply_slow` are near-identical in three files (Sept 2026:
  `player.gd`/`hero_dummy.gd`'s `apply_stun()` now additionally cancels a
  mid-swing attack, see below — so the three are no longer byte-identical,
  but the divergence is a direct, intentional consequence of only heroes
  having a lockable windup at all). Resist the refactor into a shared parent
  or component: the three scripts have genuinely different movement
  pipelines (`unit.gd` steers with separation, `player.gd` blends
  tap-to-move with chase, `hero_dummy.gd` is single-target steering) and
  the *insertion points* differ even though the timers don't. A shared
  class would force those pipelines to converge. `MapDB` follows the same
  discipline: it duplicates `CardDB`'s scan/load pattern verbatim rather
  than extracting a shared base class (see §2/§3) — two unrelated small
  scanners, not a reason to generalize yet. **`_nav_direction_to()` (§5
  Navigation) follows the same rule** — three verbatim copies, one per
  movement script, plugged in at each script's own insertion point. Keep the
  three copies in sync by hand if one changes. (Menu chrome is the
  opposite case: the framed screens share one base scene, §8 — they are the
  same thing with different content, not different pipelines. Card data is
  also the opposite case: `UnitData`/`SpellData` *are* one thing — a card —
  so they share the `CardData` base, §3.)
- **A stunned unit's `attack_left` also stops ticking.** The stun early-return
  sits *above* the cooldown decrement in `_physics_process`, so a unit
  stunned mid-cooldown resumes with the same cooldown remaining rather than
  attacking instantly on recovery. Intentional; don't "fix" it by moving the
  decrement above the stun check. **Heroes diverge from this for an
  in-progress swing specifically (Sept 2026):** a locked windup disables
  `_physics_process` entirely (`set_physics_process(false)`), so the
  freeze-and-resume behavior above literally cannot apply to a mid-swing
  stun — the stun timer wouldn't even be evaluated until the swing finished
  on its own. `player.gd`/`hero_dummy.gd`'s `apply_stun()` now calls
  `_cancel_attack_windup()` directly when landing mid-swing, canceling the
  attack outright instead of pausing it. `unit.gd` minions are unaffected
  (no cast-point system to interrupt) and this bullet's original
  freeze-and-resume behavior still fully applies to their plain
  `attack_cooldown` timer, and to a hero's own *cooldown* between swings —
  and (Sept 2026) to `unit.gd`'s new `windup_left` timer too, by the same
  logic: it's just another countdown that lives inside `_physics_process`,
  which already early-returns on `stun_left > 0.0` before reaching it. This
  is the reason `unit.gd`'s windup was deliberately built as a plain timer
  rather than a copy of the hero `await` pattern — it gets correct stun
  behavior for free instead of needing the direct-cancel workaround heroes
  required.
- **`attack_range` as a stat name collides with `attack_range` as an
  Area2D node reference.** `unit.gd` used to have only
  `@onready var attack_range: Area2D = $AttackRange`; adding a data-driven
  `attack_range: float` stat (Sept 2026, mirroring `HeroData`) required
  renaming the node reference to `attack_range_area`, matching the split
  `player.gd`/`hero_dummy.gd` already used (`attack_range: float` stat vs.
  `attack_range_area: Area2D` node). Any future archetype adding a
  `HeroData`/`UnitData`-style data-driven range stat should use this same
  `<stat>` / `<stat>_area` naming split from the start rather than
  colliding with whatever `@onready` name came first.
- **A locked windup disables `_physics_process` outright, so anything meant
  to interrupt it can't wait for the next physics frame.** `_perform_attack()`'s
  `set_physics_process(false)` (unless `can_move_while_attacking`) means the
  entire per-frame update — including any status-timer countdown or state
  check — simply doesn't run until the windup ends or cancels on its own.
  Every interrupt trigger added so far (`on_new_move_command()`,
  `set_primary_target()` targeting a new node, `apply_stun()`, and
  `hero_dummy.gd`'s HP-hysteresis flip via `take_damage()`) is therefore
  hooked directly at the call site that changes the relevant state, calling
  `_cancel_attack_windup()` synchronously — never inferred later inside
  `_physics_process`. Keep this pattern for any future interrupt condition
  (e.g. an AI "higher-priority target spotted" trigger). God skill casts and
  knockback already follow it: both call `_cancel_attack_windup()` at the call
  site (§5).
- **Anything that must keep counting during a locked windup lives in
  `_process`, not `_physics_process`.** The god skill cooldown ticks there for
  that reason (§5). Conversely, a forced move (knockback) must run in
  `_physics_process`, so it cancels the windup first to turn physics back on.
- **A unit's melee hit does not re-check range when it lands.**
  `unit.gd::_resolve_attack_hit()` trusts the target locked at windup start.
  Anything that moves a unit mid-swing (knockback today) must cancel the
  pending windup (`windup_left = 0.0`, `_swing_target = null`), or the hit
  lands from wherever the unit was pushed to.
- **New effects that are "the same thing for every caster" go into
  `SkillEffects`, not into the hero scripts.** The hero scripts only own
  per-hero state (cooldown) and the cast entry point. Don't copy an effect
  into `player.gd` and `hero_dummy.gd` — that's the one place the
  status-effect duplication rule does *not* apply.
- **Timed multi-second effects belong on a scene node, not in an autoload.**
  Storm's damage-over-time was originally an `await`-based loop inside
  `BattleManager` holding a target snapshot across several seconds — which
  survived units dying (`is_instance_valid()` per tick) but was *not* safe
  against a match ending or scene change mid-loop. Moving the timing into
  `SpellZone`'s `_process` fixed that for free: the node is a child of the
  arena, so match end, scene change, and `reset_match_state()` all clean it
  up with no guard code. Reach for this pattern before adding another
  `await` chain to an autoload. Note the deliberate consequence —
  **`SpellZone` state is intentionally absent from every
  `reset_match_state()`**, unlike the four autoloads; scene ownership is the
  reset mechanism.
- **Never mutate a shared `SpriteFrames` at runtime.** Stretching a spell's
  cast animation to fit `cast_time` is done with
  `AnimatedSprite2D.speed_scale` on the *node*
  (`speed_scale = frame_count / animation_speed / cast_time`), never with
  `set_animation_speed()` / `set_animation_loop()` on the resource — those
  would leak across every instance using that resource. Same rule as "never
  write runtime state back into a resource" in §1, one step further: playback
  parameters are node state too. The same goes for scene sub-resources such as
  a `StyleBoxTexture`: `main_menu.gd` `.duplicate()`s the Background stylebox
  before swapping its texture rather than editing the cached one.
- **Animation names are a contract for spells as well as units.** Spell
  `SpriteFrames` must expose `"drag"` and `"cast"`; both playback sites guard
  with `has_animation()`, so a spell with a missing or absent frames resource
  degrades to the plain circle instead of erroring. `"cast"` is authored with
  `loop = 1` and is never visibly seen looping because the node hides it at
  the phase flip — don't "fix" the resource.
- **Control siblings draw in child order — later siblings draw on top —
  regardless of each one's own `visible` state.** A hidden fullscreen overlay
  declared *before* an opaque sibling in the scene tree stays visually buried
  under it even once `visible = true`; the fix is `Control.move_to_front()`
  at open time, not a permanent scene reorder. First hit on `MainMenu.tscn`'s
  `SettingOverlay`/`CreditsOverlay` vs. `Background` (§8) — worth checking
  first whenever a Control-based overlay "doesn't show" despite `visible`
  being true and no texture/logic bug found.
- **A `Node2D` child of a `Control` container is not auto-arranged by it.**
  Containers (`HBoxContainer`, `CenterContainer`, …) only lay out `Control`
  children; a `Node2D` (e.g. an `AnimatedSprite2D`) parented under one keeps
  whatever `position` it's given, unaffected by the container's sizing pass.
  Center or position it manually — via the parent Control's `resized` signal,
  not a hardcoded offset, so it stays correct across the different canvas
  shapes `window/stretch/aspect = "expand"` produces per device. First hit on
  `MainMenu.tscn`'s hero showcase (§8), reused for the framed screens' god
  window.
- **A filled (`Solids` build-mode) `CollisionPolygon2D` is for something you
  can't enter, not for something you can't leave.** `MapBorder`'s first
  version used `Solids`, which treats the whole polygon interior as solid
  mass — the hero spawned inside the border's own footprint and got pushed
  *out* of the playable area instead of contained by it. `build_mode =
  Segments` is the correct mode for any boundary/containment shape (a
  two-sided wall along the outline only, no fill); `Solids` stays correct
  for actual obstacles (rocks, `ObstaclePatch` blobs) where the whole
  footprint should genuinely be impassable from every direction. Don't
  copy `build_mode` between the two use cases — they solve opposite
  problems.
- **`MapBorder.tscn` currently carries two `CollisionPolygon2D` children**
  — `CollisionPolygon2D` (written by `map_border.gd`'s `@tool` parametric
  generator) and `CollisionPolygon2D2` (hand-traced), with only the
  hand-drawn one enabled (`disabled = true` on the generated one) for
  side-by-side testing. This is a deliberate temporary state for
  comparison, not a finished design — **pick one approach and remove the
  other's node before release**; a `StaticBody2D` with two enabled shape
  children unions both, which was never the intent here. The navmesh's
  walkable outline is hand-drawn to match the **hand-traced** border; if the
  border shape changes, redraw the outline and rebake.
- **Navmesh bake source: groups, never "everything on layer 4".** The
  `NavigationPolygon`'s default `Source Geometry Mode = Root Node Children`
  only parses nodes *under* the `NavigationRegion2D` — obstacles living
  elsewhere in the map scene produce a mesh with no holes at all. Using
  plain collision-mask parsing would pull in `MapBorder` too, and a border
  parsed as an obstruction can carve out the entire arena. Use
  `Groups With Children` + the `nav_obstacle` group on the obstacle/structure
  containers only; `MapBorder` stays out of the group, and the walkable
  outline is drawn by hand instead.
- **A TileSet with a Navigation Layer silently adds a second navmesh.** Any
  `TileMapLayer` whose tiles carry navigation polygons registers its own
  navigation regions on the same map, overlapping the baked one and ignoring
  its holes. The Greek tileset has no navigation layer by design; keep it
  that way for every new tileset (or turn off the layer's
  `Navigation → Enabled`).
- **Copying a `NavigationRegion2D` between maps copies the baked polygons
  too.** The `NavigationPolygon` sub-resource stores the bake result
  (`vertices`/`polygons`), not just the settings — duplicating it into another
  map scene gives that map the *other* map's holes until you set the
  `nav_obstacle` groups on the new map and press **Bake NavigationPolygon**
  there. Always rebake per map.
- **Every mover archetype scene must carry `NavAgent`.** `player.gd`,
  `hero_dummy.gd` and `unit.gd` resolve it with `@onready var nav_agent =
  $NavAgent`; a scene sharing one of those scripts without the node crashes
  on spawn. Two unit scenes share `unit.gd` — both need it, and so will any
  future sibling archetype scene.
- **Never set `NavigationAgent2D.target_position` every frame.** Each
  assignment triggers a new path query. `_nav_direction_to()` only re-sends
  it when the goal moved more than 16 px (`NAV_REPATH_DIST_SQ`); a chase of a
  moving target would otherwise repath every physics frame per agent.
- **`has_navigation()` is false on the first physics frame after a map
  loads** (`NavigationServer2D.map_get_iteration_id() == 0` until the server
  syncs). Anything querying the navmesh during spawn must tolerate the
  fallback (direct steering / unsnapped point) rather than assume a path
  exists.
- **The HUD is ready before the match manifest exists.** HUD children run
  `_ready()` before `arena.gd::_ready()` sets the manifests, so HUD UI that
  shows match-derived state gets an explicit `configure()` call from the arena
  afterwards (`minimap.configure_map()`, `synergy_icon.configure()`), instead
  of reading `BattleManager` in its own `_ready()`.
- **`CardDB` routes by type, so folders are free — but its skip list is
  not.** The recursive scan must keep skipping `frames/` (`SpriteFrames` have
  no `id` and would each raise "failed to load resource") and `skills/`
  (`SkillData` has an `id` but is not a card). A new kind of helper resource
  stored under `data/cards|heroes|packs/` needs its folder added to
  `SKIP_DIRS`, or it is rejected as an unknown type.
- **Autoload order matters for `PlayerProfile`.** It validates its save against
  `CardDB` in `_ready()`, so it must come after `CardDB` in `project.godot`.
- **Save files are versioned and migrated, never silently reset.** A known
  older `save_version` is converted in memory and rewritten; only an unreadable
  or unknown-version file falls back to the starter profile. Add a migration
  branch whenever the profile's shape changes.
- **Menu tiles listen to mouse-button events only.** With
  `emulate_touch_from_mouse` on and Godot's mouse-from-touch emulation, handling
  `InputEventScreenTouch` as well makes every tap fire twice (`DeckTile`).
- **A tap inside a scrolling list needs a distance check.** `DeckTile` only
  counts a release within 10 px of the press; otherwise a finger that scrolled
  the pool selects whatever tile it lifts off.
- **`self_modulate` to tint a control without tinting its children.**
  `SynergyIcon` greys the circle and count but leaves its tooltip readable;
  Card Detail's close button darkens itself on press the same way.
- **Hand-written `.tres` / `.tscn` reference new files by `path=` only.** Never
  invent a `uid`; Godot assigns one. When moving resources outside the editor,
  keep every existing `uid` and fix the `path=` strings. A scene that points at
  a file that does not exist yet (e.g. an art asset still being drawn) fails
  to load as a missing dependency — reference only files that are on disk.
- **A path-only reference does not survive an editor move (Oct 2026).** When
  files are dragged in the FileSystem dock, Godot rewrites references that
  carry a `uid`, but a hand-written `[ext_resource]` with only `path=` can be
  left pointing at the old location — four cards broke this way when units
  moved under `cards/greek/units/`. After hand-writing resources, open and
  save them once (or run Project → Tools → Upgrade Project Files) so they
  gain uids **before** any move; after a move, grep for the old folder path.
- **A computed property can give a base class typed views of its subclasses.**
  `CardData.unit_data` / `.spell_data` are `get:`-only properties returning
  `self as UnitData` / `self as SpellData` — a base script naming its own
  subclasses is a cyclic class reference, which Godot 4 resolves. Not
  exported, so never serialized; an old `.tres` that still sets
  `unit_data = …` is a pre-merge file and is rejected by `CardDB`.
- **Texture filtering follows how much the art is scaled on the device.**
  With `stretch_mode = canvas_items` textures render at device resolution
  (S25 FE = 2× the 1170×540 viewport), so a texture's real on-screen scale is
  `node scale × camera zoom × 2` (arena camera zoom = 3). Three cases, three
  settings:

  | Art | Real scale | Setting | Where it's set |
  |---|---|---|---|
  | **Painted UI** (frames, backgrounds, buttons) | ~1–1.3× | **Linear** (`texture_filter = 2`) | once on the **scene root**, children inherit — `MainMenu`'s `Background`, `framed_overlay.tscn`, `card_detail.tscn` |
  | **Minified battlefield sprites** (hero + unit sheets, 250–420 px frames at node scale 0.1–0.15) | ~0.6–0.9× on device, ~0.3× in a desktop window | import **mipmaps** (`mipmaps/generate=true`) + **Linear Mipmap** (`texture_filter = 4`) | on the **`AnimatedSprite2D` only** in `player.tscn`, `hero_dummy.tscn`, `melee_unit.tscn`, `ranged_unit.tscn` — not the root, so health bars and target markers keep their own look |
  | **Enlarged pixel-style art** (map tiles, turrets, bases, projectile) | 3–6× | **Nearest** — the project default (`default_texture_filter = 0`), set nowhere | nothing to do; never change the project default |

  Why: Nearest at an uneven scale (e.g. 1.15×) duplicates rows unevenly and
  stair-steps painted diagonals; Nearest while shrinking makes moving sprites
  shimmer, and Linear alone stops helping past ~2× shrink — mipmaps (pre-shrunk
  copies) cover that; Linear on enlarged pixel art just blurs it.
  Rules for new content: a new UI scene sets Linear on its root; a new
  hero/unit sprite sheet gets mipmaps in its `.import` (the archetype scenes'
  sprite node already has Linear Mipmap); a new archetype scene copies
  `texture_filter = 4` onto its `AnimatedSprite2D`. Author painted UI at
  roughly **2× its logical on-screen size** — never shrink it to the viewport
  size. Costs and caveats: mipmaps add ~33 % texture memory per sheet and
  soften slightly; at small mip levels they blend across frame borders of a
  sprite sheet, so frames need transparent padding (a faint line of a
  neighbouring frame at a sprite's edge = missing padding in the art, not code).
- **Large card art is one file per card, not a sheet.** God covers
  (`HeroData.card_art`) live as individual PNGs in
  `assets/sprites/gods/<pantheon>/<god>/` (`<god>_decal1.png`, alternates
  `<god>_decal2.png` …). The same texture is the god's picture in Card Detail
  and on the small `DeckTile`s (Deck screen, Encyclopedia); the tile draws it
  with Linear Mipmap, so the PNG needs **Mipmaps** on in its Import dock: a sheet would load every god's art to show one,
  quickly exceeds the 4096 px mobile texture limit, and makes every repaint
  shift region coordinates. Sheets/atlases stay for small art drawn many times
  at once (unit sprites, tiles, icons). The unit scroll faces
  (`decals_greek.png` + `AtlasTexture` regions) predate this rule.
- **Inherited scenes: a derived script that overrides `_ready()` must call
  `super()` first.** Godot 4 does not chain `_ready()` automatically;
  `FramedOverlay` (§8) wires its close button, title and god layout in its own
  `_ready()`, and a derived overlay that forgets `super()` silently loses all
  three.
- **A scene instanced in two places can run under two different
  `process_mode`s.** `SettingOverlay` inherits `WHEN_PAUSED` inside the HUD
  (the tree is paused while it is open) but is overridden to `INHERIT` in
  `MainMenu.tscn` (the tree is not paused). Anything inside it that must
  animate in both places — the god idle sprite — is set to `ALWAYS`
  explicitly; relying on the inherited mode makes it freeze in one of the two.
- **The framed screens' dim is a rectangle with a hole, and that only works
  because the art's god window is a closed hole.** `DimWithHole` draws four
  non-overlapping rects *behind* the frame art around the window's bounding
  box (padded a few px); the rectangle's edges fall under opaque frame pixels,
  so no seam shows. If a frame is repainted with the window opening to the
  outer edge (a gap in the vines), a rectangle is no longer enough — that
  needs a mask texture.
- **9-slice texture margins are in the texture's own pixels.** A
  `StyleBoxTexture` keeps its corners at native texture size, so art drawn
  much smaller than its source (tabs: 61 px art in ~30 px buttons) can let the
  corners eat most of the height. Tune `texture_margin_*` in the Theme editor,
  not in art; crop transparent padding with `region_rect` (the inactive gold
  button) instead of re-exporting.
- **Tab panes that hold long text sit in a `ScrollContainer`.** Card Detail's
  Skills and Details panes each live in their own `ScrollContainer`
  (`horizontal_scroll_mode = 0` so labels wrap, the inner pane
  `size_flags_horizontal = 3`); the tab toggles the **scroll container's**
  visibility, not the pane's — a visible empty scroll container stacked in the
  same `PanelContainer` would swallow the other tab's drag.
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
  `HealingSystem` is the third: pod cooldown state and per-team HoT state are
  both pure data with no scene or UI dependency, so a server would run
  `trigger_heal()` / `consume_pod()` / `cancel_heal()` verbatim, same as
  EnergySystem's spend path.
- Authority model (dedicated server vs. relay/P2P) is an open decision with real
  cost implications — treat as its own project phase.
- `HeroAI` is the fourth such module: per-team hp-threshold hysteresis is
  pure data (a bool + two constants), so a server would run
  `get_hp_state()` verbatim. The *decision* of what to do about a LOW_HP
  state (which structure, which pod, which spawn point) stays in the hero
  script/controller layer, not in `HeroAI` — keeping the autoload itself
  trivially portable regardless of how targeting logic evolves.
- Spell casts fit the existing spawn-message shape: `{card_id, position, team}`
  → the receiving side calls the same `cast_spell()` local play uses. Unlike
  `EnergySystem`/`HealingSystem`/`HeroAI`, the spell layer is **not** a
  scene-free pure-state module — `SpellZone` is a scene node and applies
  effects to live nodes directly. `get_targets_in_radius()` is the clean
  seam: a server-authoritative version would run the zone's tick schedule
  and that query, and send resulting damage/status to clients rather than
  letting each client resolve its own. The cast delay is also a genuine
  gameplay window (not just a visual), so it must be server-timed, not
  client-timed, once authority exists.
- **God skills fit the same shape:** `{team, skill_id, target_id}` → the
  receiving side calls the same `SkillEffects.cast()` local play uses
  (`try_cast_skill()` only picks the target; `cast()` takes it as an
  argument, which is that seam). Tuning values are resolved from the shared
  database (`SkillData.values`), never sent. Both implemented skills resolve
  in one frame with no RNG, so they're deterministic given the same target
  and positions. Cooldown would be server-owned once authority exists. Hermes's energy steal touches
  `EnergySystem`, so it is server-authority material like `try_spend()`.
- **Audio is never networked and never authoritative.** Every client plays
  its own sounds from its own local events (hit landed, unit died, hero
  died signal), so nothing about audio enters a message. `AudioManager`
  randomness (variant pick, pitch/volume jitter, ambient timers) uses the
  global `randf()`/`randi()` — if gameplay ever moves to a seeded,
  lockstep RNG, audio must keep using a separate generator so a sound
  choice can't desync the simulation.
- **The end-of-match sequence is client-side presentation.** The winner is
  decided (and `match_ended` emitted) the instant the base falls; the
  camera focus, banner and 3.5 s delay before `MatchEndScreen` are local to
  each client and never networked.
- Map selection will need the same treatment: `MatchConfig.map_id` is
  currently a client-local TEMP random pick (§2/§3) with no server
  involved — real matchmaking will need to agree on a map id before either
  client instantiates `MapDB.get_map(id).map_scene`, the same way card
  database version needs to match today.
- **Movement commands carry goals, never paths.** A tap-to-move message will
  be `{target_position}` (already navmesh-snapped by the sender or re-snapped
  by the receiver); each simulation computes its own path from the map's
  baked navmesh. That makes the navmesh bake part of the map "version" both
  sides must agree on, the same as the card database. Under a
  server-authoritative model the server runs the agents and clients only
  render positions.
- **The match manifest is the deck message.** Today `MatchConfig` is filled
  locally; with networking, both sides exchange `{hero_id, hero_level,
  card_levels}` once before the match and a server validates it against the
  player's inventory. Spawn messages do not change.
- **`PlayerProfile`'s mutation API is the server boundary** for the meta game:
  `grant_cards()`, `upgrade_card()`, `set_deck()` become requests; `PackRoller`
  and `DeckRules` run server-side unchanged because they take all inputs as
  arguments. The local JSON save is a stand-in and is cheatable by design.
  Card Detail's Upgrade button already goes through `upgrade_card()` only.
- **Synergy is derived, not transmitted.** Both sides compute it from the same
  manifest and the same card database, so it needs no message — but it makes
  `tags`, `domain`, `faction` and the gods' synergy fields part of the database
  version both clients must agree on.

---

## 8. Main menu / UI shell

`scenes/menu/MainMenu.tscn` (`scripts/ui/main_menu.gd`) — the hub screen
reached on launch and returned to after a match. Pure UI chrome, no match
state — everything here is display/navigation only. Node structure, all
under `Background` (a full-screen `Panel`, the last declared child of the
menu root so it draws over the overlay instances declared above it, see the
draw-order pitfall in §6):

- `Background` itself (Oct 2026) — its `StyleBoxTexture` (with a darkening
  `modulate_color`) is the hub backdrop. `main_menu.gd::_apply_menu_background()`
  runs in `_ready()` (so on launch and on every return from a match): it
  `load()`s **one** path from `MENU_BACKGROUNDS`
  (`assets/menu/background/greek/greek_tier1–3.png`) — never preloads all
  three — duplicates the stylebox, sets the texture and overrides it.
  The choice is `_pick_background_path()`, a uniform-random **TEMP** pick;
  by design the tier will follow account level (`game_design.md` §3.13),
  and only that function changes then. The scene's own stylebox texture
  (tier 1) is the editor preview and the fallback when a load fails.
  `texture_filter = Linear` on `Background` (§6 filtering).
- `NavRail` (`VBoxContainer`, left edge, anchored full-height) —
  `DeckButton` (inventory icon) → `EncyclopediaOverlay`; `HeroesButton` →
  `DeckOverlay` (the button will be renamed); `ShopButton` → `ShopOverlay`;
  `RewardsButton` → `_show_coming_soon()`; a `Control` spacer; `ExitButton`.
  All are `TextureButton`s.
- `TopBar` (`HBoxContainer`, top edge) — `CurrencyGroup` (a `ColorRect` +
  static `"0"` `Label`, placeholder), `MailButton`/`GiftButton` (same
  flat-color placeholder pattern as the nav rail), `SettingsButton`
  (`TextureButton`, opens `SettingOverlay`).
- `MainContent` (`HBoxContainer`, fills the space between the nav rail and
  the screen edge) — `HeroShowcase` (`Control`, `size_flags_horizontal = 3`
  to take remaining width) containing a single `AnimatedSprite2D` child
  (`ZeusIdle`) that plays a hero's existing `SpriteFrames` idle animation
  directly (currently `frames_zeus.tres`'s `"iddle_left"`, `autoplay =
  true`) — reuses match art as-is, no separate menu-only asset; and
  `BattleCard` (`Button`, `custom_minimum_size` fixed, `size_flags_vertical
  = 4` to center within the row), the sole entry point into
  `PreMatchFlow.tscn` (§4).
- `ComingSoonToast` (`PanelContainer`, hidden by default) — generic "<X> —
  coming soon" toast for any unimplemented nav-rail/top-bar button, shown
  via `main_menu.gd::_show_coming_soon(feature_name: String)`. Debounced
  with a `_toast_token: int` counter: each call increments the token and
  only the matching deferred hide (`get_tree().create_timer(...).timeout`)
  actually hides the toast, so rapid taps across different placeholder
  buttons extend the visible window instead of an earlier timer hiding it
  mid-read. Reusable pattern for any future auto-hiding transient UI.
- `FooterBar` (`HBoxContainer`, bottom edge) — title, `•`, `VersionLabel`
  (reads `ProjectSettings.get_setting("application/config/version", ...)`
  at `_ready()`, backed by a real `config/version` project setting — never
  hardcoded in two places), `•`, `ServerStatusLabel` (static placeholder
  text, no real server/backend yet).
- `SettingOverlay` / `CreditsOverlay` — fullscreen overlay scene instances
  built on the framed-overlay base (below), siblings of `Background` but
  declared *before* it in the tree (see the draw-order pitfall in §6). Both
  start `visible = false`; `main_menu.gd` calls `move_to_front()` on whichever
  one it opens, and hides `NavRail` and `MainContent` while it is open.
  Settings holds a `CreditsButton` that closes Settings and emits
  `credits_requested`, which `main_menu.gd` answers by opening Credits — the
  two are never open at once. These two are still wired with `[connection]`
  entries in `MainMenu.tscn`. Known gap: in a match the HUD does not listen
  to `credits_requested`, so the Credits button there closes the pause screen
  without resuming — hide it in the arena or wire it.
- `ShopOverlay`, `DeckOverlay`, `EncyclopediaOverlay` — three more fullscreen
  overlay instances following the same pattern (`open()` / `close()`, a
  `closed` signal, `move_to_front()` at open, nav rail and main content hidden
  while open). Unlike the two older overlays they are connected **in code** in
  `main_menu.gd::_ready()`, not with `[connection]` entries. Plain default-theme
  controls, no art yet (except Card Detail, below).
  - `shop_overlay.gd` — lists `CardDB.list_pack_ids()`; opening a pack rolls
    with `PackRoller`, grants through `PlayerProfile.grant_cards()` (one call
    per pack) and shows a list reveal (NEW / +1 copy).
  - `deck_overlay.gd` + `deck_tile.gd` (`DeckTile`, built in code) — 8 slots
    (god + 7) and, in edit mode, the pool. Works on a draft; one `_place()`
    function serves both Godot's Control drag-and-drop and tap-then-tap. Only
    Save writes (`PlayerProfile.set_deck()`, which also makes that god active).
    Switching god loads `get_deck_for(god)`; unsaved card edits raise a
    Discard / Cancel dialog. Cards the draft god refuses are greyed
    ("Forbidden"). A live synergy line sits under the slots.
  - `encyclopedia_overlay.gd` — a tab per pantheon found in the data; sections
    Gods / Units / Spells of `DeckTile`s (locked ones tappable). Gods are
    listed regardless of `obtain_source`; cards with `obtain_source = 0` are
    hidden. A god tile shows `HeroData.card_art`, falling back to the first
    idle frame (`DeckTile._hero_texture()`). Hosts `card_detail.tscn` (`CardDetail`, below) as its `CardDetail`
    node and calls `open_for(tile.item_id, tile.kind)`. The overlay rebuilds on
    `PlayerProfile.profile_changed`.
- Debug keys in the main menu (debug builds only): **F9** reset profile,
  **F10** +1 copy of everything obtainable (and every god), **F11** toggle
  `DebugLog`.

### Framed overlays (Oct 2026)

`scenes/menu/framed_overlay.tscn` + `scripts/ui/framed_overlay.gd`
(`class_name FramedOverlay`) is a **base scene**; `setting_overlay.tscn` and
`credits_overlay.tscn` are **inherited scenes** of it (scene inheritance, so
each one's content stays editable and previewable in the editor). A new
framed screen = a new inherited scene + `title_text` + its own children under
`ContentArea`. Base tree:

- root `FramedOverlay` (full rect, `mouse_filter` STOP — blocks taps behind,
  including tap-to-move in the arena; `texture_filter = Linear`, §6)
- `Dim` (`DimWithHole`, `scripts/ui/dim_with_hole.gd`) — first child, draws
  `dim_color` around `hole_source` (`DimHole`) grown by `hole_pad` (§6 pitfall)
- `FrameFit` (`AspectRatioContainer`, ratio of the art, FIT, centered) →
  `FrameRoot`, whose children are anchored by **fractions of the art**, so
  they stay on their painted regions at any screen aspect:
  - `DimHole` — marker only, the window's bounding box
  - `FrameArt` — `assets/menu/settings/settings_frame_blank.png` (no title,
    one asset for every framed screen)
  - `TitleLabel` — on the title plate; CinzelDecorative-Black, gold
    `Color(1.0, 0.82, 0.3)`, black outline 3, uppercase, the end-of-match
    banner style. `set_title()` / `_fit_title()` shrink the font from 26 to at
    least 14 px so any title fits the plate; re-fits on `resized`.
  - `GodWindow` / `GodIdle` (`AnimatedSprite2D`, `process_mode ALWAYS`, §6) —
    the active god's `iddle_left` (`PlayerProfile.get_deck_hero()`), scaled
    by one shared factor from `GOD_REF_FRAME_H = 400` (so gods keep their
    relative sizes from the art), bottom-centred on the podium, drawn
    *behind* `FrameArt` so the columns overlap it. Tunables `god_height_fill`,
    `god_foot_nudge`.
  - `ContentArea` (`MarginContainer`) — empty slot over the marble.
  - `CloseButton` — `TextureButton` at the frame's top-right corner
    (group `ui_sfx_close`, `process_mode ALWAYS`). **Known gap:** it has no
    texture, and `settings_frame_blank.png` no longer paints an X, so the
    hit area is invisible — give it `assets/menu/close.png` (as Card Detail
    does).
- API for derived scripts: call `super()` first in `_ready()` (§6), call
  `_frame_opened()` from `open()` and `_frame_closed()` from `close()`,
  override `_on_frame_close_pressed()`. Exports: `title_text`,
  `frame_texture` (optional per-screen art override, null by default),
  `god_height_fill`, `god_foot_nudge`.
- `SettingOverlay` (`setting_overlay.gd`, `class_name SettingsOverlay`, root
  `process_mode = 2`) keeps its public API (`open(show_return_to_mainmenu_button)`,
  `close()`, signals `closed_requested` / `exit_requested` /
  `credits_requested`): audio rows (label + `AudioControl` slider), lock
  camera, Credits + Main Menu buttons, in a scrollable list. Instanced in
  `MainMenu.tscn` and in `HUD.tscn` (pause screen).
- `CreditsOverlay` (`credits_overlay.gd`) — `title_text = "Credits"`, a
  scrollable role/name list; `open()` / `close()` / `closed`.
- Art rule going forward: frames are painted **without** words and without
  the close X — `assets/menu/close.png` is the standard close button, placed as
  a real `TextureButton` (Card Detail already does this; the framed overlays
  still need it, see the gap above).

### UI Theme — `assets/UI/dgb_theme.tres` (Oct 2026)

One `Theme` for panel and button styles, applied on a **scene root** (today
only `card_detail.tscn`; not project-wide, so older default-theme screens are
unaffected until they are restyled). Type variations:

| Variation | Base | Look |
|---|---|---|
| `StatTile` | `PanelContainer` | `StyleBoxFlat` dark navy, radius 5, 1 px border |
| `DarkStrip` | `PanelContainer` | `StyleBoxFlat` translucent black, radius 4 |
| `LevelBadge` | `PanelContainer` | `StyleBoxFlat` circle, blue fill, gold 3 px border |
| `TabButton` | `Button` | 9-slice `tab_inactive.png` / `tab_active.png` (pressed), Oswald-Bold 17, grey → gold text |
| `GoldButton` | `Button` | 9-slice `upgrade_card_button_active.png`; disabled = `upgrade_card_button_inactive.png` with `region_rect` crop; Oswald-Bold 20, dark text |

Plus `Label` font colour (cream) and the Oswald default font. Rules: a plain
rectangle is a `StyleBoxFlat` (sharp at any size, no texture memory, one place
to tune); only painted detail (gold bevels, ornaments) is a texture, and it is
used as a 9-slice `StyleBoxTexture` on a normal `Button` so Godot draws the
text — `TextureButton` stays for icon-only buttons. Fonts: Oswald (static
Bold / SemiBold / Medium / Regular) for card and stat UI;
CinzelDecorative-Black for framed-screen titles and the end-of-match banner;
Marcellus for older menus.

### Card Detail (Oct 2026)

`scenes/menu/card_detail.tscn` + `scripts/ui/card_detail.gd`
(`class_name CardDetail`) replaced `card_flashcard.tscn` / `CardFlashcard`
with the **same API** — `open_for(id: StringName, kind: StringName)`,
`close()`, signal `closed` — and the same stat formulas (`LevelCurve` via
`PlayerProfile.LEVEL_CURVE`). The old flashcard files are no longer
referenced and can be deleted (delete order: §6). Not a `FramedOverlay`:
different frame (`assets/menu/deck/card_detail_blank.png`, no god window).
Root has `theme = dgb_theme.tres` and `texture_filter = Linear`.

- Layout over the frame (fractions of the art, inside an `AspectRatioContainer`
  like the framed overlays): `FrameArt`; `ThemeArt` — a full-canvas
  per-pantheon scenery layer (`FACTION_THEME_ART`: `greek` →
  `deck/themes/greek_theme.png`, `norse` → `nordic_theme.png`; missing key =
  hidden); `CardArt` (`CardData.scroll_texture`, or `HeroData.card_art`
  falling back to the first idle frame; greyed when not owned); `AltArtRow`
  (three "UNK" placeholder slots); `LevelBadge`; `InfoColumn` (name, epithet
  "UNK", Type + Rarity `StatTile`s, description — the card's / god's
  `description` lore intro — beside the scenery, `StatsGrid` of 8 tiles);
  `TabsColumn` (Skills / Details `TabButton`s in a `ButtonGroup`, each pane in
  its own `ScrollContainer` — `SkillsScroll` / `DetailsScroll`, §6);
  `UpgradePanel` inside the box painted in the frame; `CloseButton`
  (`close.png`, darkens via `self_modulate` while held).
- **Skills tab:** for a god, `SkillName` shows `HeroData.skill.display_name`
  and `SkillDescription` shows `"Cooldown: Ns"` plus
  `SkillData.get_description()` — the template filled from the skill's
  current `values` (§3), so retuning a number updates the text. Cards and gods
  without a skill show "—". `IconSlot` is still a placeholder `ColorRect`.
  **Details tab:** pantheon, domain, tags, obtain source and, for gods,
  `DeckRules.describe_synergy()`.
- `scenes/menu/stat_tile.tscn` (`StatTile`, `PanelContainer`,
  `theme_type_variation = "StatTile"`) — `set_stat(name, value, delta = "")`;
  the green delta is the gain at the next level (`+62`, or `-0.04s` for a
  god's recovery), shown only when owned and not max.
- Upgrade: the button is disabled unless `PlayerProfile.can_upgrade(id)`;
  pressing it calls `PlayerProfile.upgrade_card(id)` and refreshes (also on
  `profile_changed`). States: not owned → "Locked"; max → "Max level".
- Placeholders are literal `"UNK"` strings in the scene/script (epithet,
  Deploy Time, alternate arts) — `game_design.md` §6 lists what each one
  waits for. The layout is a stop-gap: a readability rework of the Skills
  area is planned.

Two general Control-layout pitfalls surfaced building the main menu — the
draw-order one and the `Node2D`-in-a-`Control` centering one — are filed in
§6 rather than duplicated here, since both are reusable lessons beyond the
main menu specifically.

---

## 9. Audio

All sound goes through the `AudioManager` autoload (§2). Built in three
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
| `play_ui(id)` | button taps | TEMP `UI_SOUNDS` table; auto-wired to every `BaseButton`/`TouchScreenButton` via `node_added` (+ one walk of the boot scene, §6). Groups: `ui_sfx_close` → close sound, `ui_sfx_none` → silent |
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
`class_name` resource, not on the autoload (§6 autoload-enum pitfall).
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
  (§6), `death_sfx` in `die()`. `player.gd::play_spawn_animation()` plays
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
- Maps: `AmbientEmitter` nodes (§4).
- `MatchAnnouncer` (§4), `MatchEndScreen` (stingers), `main_menu.gd` /
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
