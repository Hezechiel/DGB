# Data layer — DGB architecture

> Part of docs/architecture.md — see the index there.

## Data layer

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
                                    min_interval, positional, max_distance (`audio.md`)
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
the Card Detail text (`menu_ui.md`) and the runtime effect (`combat_movement.md` "God skills"), so a
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
`is_deploy_position_valid()` and by the UI overlay in `battle_scene.md`. `deploy_bounds`
(the map's outer `Rect2`, set by `configure_map()`, `conventions_pitfalls.md`) and protection zones
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
types: the `MapDB` autoload (`architecture.md` §2) scans `data/maps/` into an id-keyed
dictionary at startup, exactly like `CardDB`. `arena.tscn` is a generic
match shell — HUD, `ArenaCamera`, `MoveMarker`, `DenialZoneOverlay`,
`DeployGhost`, and an empty `MapRoot` node — and holds **no** map content
of its own (`battle_scene.md`). At the top of `_ready()` it resolves
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
previously-independent hardcoded bounds systems (`conventions_pitfalls.md`) into one per-map
resource, and adding a new map is authoring a new `.tres` + a new map
`.tscn` (no script changes — the `MapDB` scan picks it up automatically;
see `map_authoring_guide.md` for the full checklist). Structures
(turrets/bases/healing pods) are **not** part of `MapData` — their
positions and `protection_zone` rects live on the structure nodes
themselves in each map's own `.tscn` (`scenes/arena/maps/<Name>Map.tscn`),
hand-tuned per map (see the protection-zone paragraph above and
`game_design.md` §3.7). The navigation mesh is **not** part of `MapData`
either — it lives in each map scene's own `NavigationRegion2D` (`combat_movement.md`
Navigation).

**WIP, Sept 2026 — map visual pipeline is being migrated to tiles, one map
at a time.**
`GreekPlateauMap.tscn` was reworked as the test bed to build the map
entirely from `TileMapLayer`s instead of one background `Sprite2D` + a
single ground-collision `TileMapLayer` — the background `Sprite2D` node is
gone entirely on that map, and it now also carries the map's
`NavigationRegion2D` (`combat_movement.md`). `NordPlainsMap.tscn` is **mid-migration** to the
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

## Moved from CLAUDE.md (Oct 2026)

Facts from the old CLAUDE.md catalogue that the sections above did not
already cover.

### MapDB / MapData (from CLAUDE.md)

Two maps exist today: `greek_plateau.tres` (release-ready) and
`nord_plains.tres` (`release_ready = false`, still WIP). `MapData.bounds` is
the single source of truth for both `BattleManager.deploy_bounds` and
`ArenaCamera`'s pan bounds, so the two can never drift apart.

### PlayerProfile (from CLAUDE.md)

- Autoload order: after `CardDB`, before `MapDB`/`MatchConfig`
- **One 7-card deck per god** (`DECK_SIZE = 7`) plus the active god whose deck goes into the match
- Saved to `user://profile.json`, `SAVE_VERSION = 2` (v1 single-deck saves migrate automatically); corrupt/incompatible save → starter grant (`STARTER_HERO = hero_zeus` + 7 `STARTER_CARDS`)
- Read API: `owns_card`, `get_card_level`, `get_copies_to_next`, `can_upgrade`, `get_deck_hero`, `get_deck_cards`, `get_deck_for`, …
- Each mutation saves and emits `profile_changed`. `set_deck()` validates via `DeckRules` and also makes that god active; `upgrade_card()` is the manual level up and spends copies

### Pure helpers (from CLAUDE.md)

- `LevelCurve` — `stat_multiplier` per level applies to units: HP + damage; spells: damage only; gods: HP + damage. CC durations never scale
- `PackData` (`scripts/pack_data.gd`) — `card_count`, `faction` filter, per-pack `rarity_weights`, `guaranteed_min_rarity` on the last slot, `price` (always 0 — no currency yet). Packs today: `greek_scroll_pack.tres`, `greek_cherished_pack.tres`; `data/progression/level_curve.tres` is the single `LevelCurve` used by both `PlayerProfile` and `BattleManager`
- `CardDB.get_pack_pool(faction)` builds the drop pool from cards **and** gods with `obtain_source == 1`
- Card ids are named `card_greek_<name>` (e.g. `card_greek_hoplite`, `card_greek_storm`); gods are `hero_<name>`

### Match manifest & synergy (from CLAUDE.md)

- Missing manifest entry → level 1 (`get_card_level()` / `get_hero_level()`)
- Synergy is active when the deck holds at least `synergy_count` (default 4) cards that carry the god's `synergy_tag` **and** belong to the god's pantheon (units and spells both count); never re-evaluated mid-match
- Beneficiaries: every card of the god's own pantheon (`card.faction == hero.faction`), tagged or not; foreign-pantheon cards neither count nor benefit; the god itself is never buffed
- `synergy_bonuses` keys: `max_hp`/`damage`/`speed`/`attack_speed` for units, `spell_damage`, `energy_regen`. CC durations are untouched by `spell_damage`. `get_synergy_energy_regen(team)` feeds the `&"synergy"` energy modifier; `is_synergy_active(team)` and `get_synergy_status(team)` (`{tag, have, need, active, bonuses}`, empty = no synergy) are UI read helpers
