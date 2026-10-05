# Docs patch — Scrolls (card collection), October 2026

Copy-paste blocks for `game_design.md`, `architecture.md`, `cards_greek.md` and the two authoring guides, organised by exact section. Each entry says **REPLACE**, **ADD** or **DELETE** and quotes the text to find. Source of truth for the decisions: `claude/scrolls_decisions.md`; for what was built: `claude/scrolls_build_log.md`.

Vocabulary used throughout (new): **faction = pantheon** (Greek, Norse…), **domain = cross-pantheon grouping** (Olympus/sky, sea, underworld…), **tags** = free labels on cards. Older text that says "era" means faction; older text that says "faction" for Olympus/Sea/Underworld means domain.

---

# 1. `game_design.md`

## §2 Core Loop — step 3

**REPLACE** the sentence `The AI opponent plays from an identical but hidden hand on the same rules (§3.10).` with:

```markdown
The deck is the player's own: one god plus seven scrolls chosen in the Deck
   screen (§3.14). The AI opponent plays a mirror of that deck from a hidden hand
   on the same rules (§3.10).
```

## §3.1 Cards & hand

**REPLACE** the bullet starting `- Every card is data (`CardData` resource): id, name, cost, scroll art, linked unit.` (the whole bullet) with:

```markdown
- Every card is data (`CardData` resource): id, name, cost, scroll art, and
  either a unit or a spell (§3.11) — never both. Cards also carry collection
  data: rarity, pantheon, domain, tags, where copies come from, a description
  (§3.14).
- **The deck is 1 god + 7 scrolls** (SWFA shape), units and spells mixed, no
  duplicates. It comes from the player's profile, not from the hand scene. With
  3 slots and a preview, three cards are always out of sight in the cycle.
```

**REPLACE** the bullet starting `- Nine placeholder cards exist (costs 2–6, varying squad sizes)` with:

```markdown
- Eleven named Greek cards exist: eight units (Hoplite, Toxotes, Peltast,
  Sphendonetes, Hippeus, Phalanx, Priestess, Gastraphetes) and three spells
  (Storm, Stun, Ensnaring Net). Costs, squad sizes and rarities are
  placeholders; five of the eight units still use placeholder sprites, and
  Priestess has no scroll art yet. A shared scroll-back art shows while a card
  is being dragged.
```

## §3.3 Heroes

**ADD** at the end of the section:

```markdown
- **The god is part of the deck** (§3.14): the player fields the god of the
  active deck. The enemy god is still a fixed placeholder (Poseidon).
- Gods are scrolls too — they are collected and leveled like cards. A god's
  level raises HP, damage and attack speed.
```

## §3.10 Enemy hero AI — Wave 2

**REPLACE** the bullet starting `- The AI side holds **its own hand on the player's exact rules**: same 9-card` with:

```markdown
- The AI side holds **its own hand on the player's exact rules**: a mirror of
  the player's 7-card deck and card levels, shuffled once at match start, same
  back-of-the-queue draw cycle, same 3 active slots, same costs, same atomic
  energy spend. It is the player's mechanic run by a different decider — not a
  spawn script with its own economy.
```

**REPLACE** the bullet starting `- Deck parity is maintained **by hand**` with:

```markdown
- Deck parity is automatic: the hand and the AI both read their deck from the
  same match configuration, filled once from the player's profile before the
  match. The AI's god is not mirrored (still Poseidon), so its synergy rule is
  checked against the mirrored deck.
```

## §3.13 Main menu / hub

**REPLACE** the bullet starting `- The nav rail currently exposes **Deck, Heroes, Shop, Rewards** as` with:

```markdown
- The nav rail's buttons are now real, except Rewards (still a "coming soon"
  toast): the **inventory** button opens the **Encyclopedia**, the **Heroes**
  button opens the **Deck** screen (to be renamed), and **Shop** opens the pack
  shop — all described in §3.14. Each is a full-screen overlay over the menu.
```

## §3.14 — new section

**ADD** after §3.13 (before `## 4. Roadmap`):

```markdown
### 3.14 Scrolls — collection, packs, decks, synergy
- **Collection.** A card or god is unlocked by owning one copy; duplicates
  stack as copies. Everything is stored in a local profile (cheatable — fine
  until there is a server).
- **Rarities:** Common, Rare, Epic, Legendary on one shared level scale; gods
  have their own tier, **Unique**.
- **Leveling is manual.** Level cap 10. Rarer cards need fewer copies per
  level. The player presses a level-up button; nothing levels automatically.
  Upgrades cost copies only (no currency yet).
- **What a level does:** units gain HP and damage; spells gain damage only —
  stun/root/slow durations never scale; gods gain HP, damage and attack speed.
  Increments shrink per level, about +48 % at level 10 (gods' attack speed
  +18 %).
- **Packs.** Free for now, five scrolls each, with rarity weights **per pack**:
  the basic Greek pack can never drop a god; the "cherished" pack has a small
  chance. The last scroll in a pack has a guaranteed minimum rarity.
- **Starter:** Zeus and seven cards at level 1.
- **Shop** (nav rail): open packs; the reveal lists each scroll as NEW or +1
  copy.
- **Encyclopedia** (inventory button): every god and card of a pantheon, owned
  and locked. Tapping one opens its **flashcard** — art, level, copies
  progress, description, battle stats with a "current > next level" preview —
  and the level-up button lives there. Long-term the flashcard should open from
  every view that shows cards.
- **Deck screen** (Heroes button): the god on the far left, then seven scrolls.
  Edit shows the pool (locked scrolls greyed, to show what is still out of
  reach); scrolls are placed by drag-and-drop or tap-then-tap. Placing a scroll
  replaces a slot, so a deck is never incomplete.
- **One deck per god.** Choosing another god brings that god's saved deck, or a
  default (the deck in use, with any refused scroll swapped for the cheapest
  owned one the god accepts). Unsaved changes on a god switch ask Discard or
  Cancel — saving is only ever the main Save button.
- **Deck rules: god against card only.** Scrolls carry tags; a god may refuse
  some tags ("holy won't hire undead"). Neutral gods refuse nothing. No
  card-against-card rules. A god that cannot field seven allowed scrolls is a
  content bug and must not ship.
- **Pantheons may be mixed** in one deck. The price is synergy, not a ban.
  (Idea for later: neighbouring pantheons — e.g. the Asian ones — mixing
  without penalty.)
- **Synergy: one threshold per god, no tiers.** If the deck holds enough
  scrolls of the god's synergy tag *from the god's own pantheon* (units and
  spells both count), every scroll of that pantheon gets the god's bonus —
  unit stats, spell damage or energy regeneration, depending on the god. A
  foreign-pantheon scroll neither counts nor benefits. Zeus: four Olympus
  scrolls → Greek units +10 % HP and damage. It is decided at match start and
  never changes during a match.
- **Synergy is shown in two places:** a small icon by the hand in the arena
  (grey / glowing, tap for the bonus text) and a live count in the Deck screen.
- Placeholder numbers throughout: copies per level, level multipliers, pack
  weights, synergy size and thresholds, rarities of individual cards.
```

## §4 Roadmap

**ADD** as a new item 8, and renumber the old `8. Then: ranged/siege archetypes…` to 9:

```markdown
8. ~~**Scrolls (card collection)**~~ — profile and starter grant, levels in
   matches, free packs and shop, Deck screen (one deck per god), Encyclopedia
   with flashcard and manual level-up, god-against-card deck rules, and the
   deck-threshold synergy with its HUD icon are implemented (§3.14). **Not
   built:** currency and prices, account level, pack-opening presentation,
   real tags on content, Olympus/Sea/Underworld cards, the attack-speed rework.
```

## §5 Future vision

**REPLACE** the bullet starting `- **Factions (Greek era):** Olympus/Sky, Sea, Underworld` with:

```markdown
- **Domains (Greek pantheon):** Olympus/Sky, Sea, Underworld — domain cards
  beyond the common pool. Domains are shared across pantheons. The synergy
  mechanism is decided (§3.14): a stat-style boost unlocked by a deck
  threshold, never a cost discount. The domain cards themselves are not in the
  game yet.
```

**REPLACE** the bullet starting `- **Meta:** deck building, collection, per-match deck selection` with:

```markdown
- **Meta:** collection, packs, leveling and deck building exist (§3.14).
  Still future: currency and pricing, account level (intended to drive
  structure strength), battle pass, trading duplicate gods between players,
  matchmaking by level.
```

## §6 Open questions

**REPLACE** `- Faction synergy mechanism (see above).` with:

```markdown
- ~~Faction synergy mechanism.~~ Resolved (§3.14): a boost unlocked by one deck
  threshold per god.
```

**ADD** at the end of the section:

```markdown
- Scrolls: which gods come from packs, achievements, quests or events (only
  Zeus as the starter is fixed).
- Scrolls: the tag vocabulary and which gods refuse what — no tags are
  assigned to real content yet.
- Scrolls: each god's synergy rule (tag, threshold, effect); only Zeus's is
  sketched. Whether a god's passive ability should later add an in-match
  condition on top of the deck threshold.
- Scrolls: "continental" affinity between pantheons — an idea, not designed.
- Scrolls: starter deck contents and per-card rarities are placeholders.
- Attack speed currently only shortens the pause after a hit; a proper rework
  (swing speed) is wanted and postponed.
- The flashcard should open from every card view; on the Deck screen a tap
  already means "select", so that screen needs a different gesture.
- Thematic name for the level-up button; description texts for cards and gods.
```

---

# 2. `architecture.md`

## §1 Guiding principles

**ADD** two bullets at the end of the list:

```markdown
- **Levels and synergy never travel per spawn.** Spawn messages stay
  `{card_id, position, team}`. A per-team **match manifest** (god, god level,
  card levels) is set once at match start; `BattleManager` looks multipliers up
  by team at its three entry points.
- **The collection changes through one API.** Owned cards, copies, levels and
  decks are mutated only by `PlayerProfile`'s `grant_cards()`, `upgrade_card()`,
  `set_deck()`, `reset_profile()` — the calls a server will later own. Rules
  and math around them (`LevelCurve`, `PackRoller`, `DeckRules`) are pure
  static code with no nodes and no autoload calls.
```

## §2 Autoloads

**REPLACE** the `CardDB` table row with:

```markdown
| `CardDB` | Startup scan of `data/cards/`, `data/units/`, `data/heroes/`, `data/spells/`, `data/packs/` into id-keyed dictionaries. The scan is **recursive** (content sits in per-pantheon subfolders) and skips folders named `frames`. Handles `.tres.remap` suffixes in Android exports. Duplicate-id guard. Also: `has_card()` / `has_hero()` (silent existence checks), sorted `list_card_ids()` / `list_hero_ids()` / `list_pack_ids()`, and `get_pack_pool(faction)` — the drop pool by rarity for `PackRoller`. |
```

**REPLACE** the `MatchConfig` table row with:

```markdown
| `MatchConfig` | Holder for pre-match data. Display fields (rank, both players' name/faction label) are placeholders and never networked. It also carries the **deck manifest inputs**: `local_hero_id`, `local_deck_card_ids`, `local_hero_level`, `local_card_levels` and the `opponent_*` twins, filled by `PreMatchFlow` from `PlayerProfile` (the AI mirrors the player's cards and levels; its god is a TEMP constant). `map_id` is set by `PreMatchFlow` via `MapDB.get_random_map_id()`. `MatchConfig` itself calls no other autoload. |
```

**ADD** a row after `CardDB`:

```markdown
| `PlayerProfile` | The player's collection and decks, saved to `user://profile.json` (`save_version` 2; v1 is migrated on load). Owned cards and gods as `{level, copies}`, **one deck per god** (`_decks`) and the active god. Read API returns copies only. Mutation API: `grant_cards()`, `upgrade_card()`, `set_deck()`, `reset_profile()` — nothing else may change the collection. `get_deck_hero()` / `get_deck_cards()` = what goes into the match; `get_deck_for(god)` = saved deck or a default built by `DeckRules`. A broken save falls back to the starter profile; ids the game no longer knows are dropped. Logs a content error for any god that cannot field 7 allowed cards. No scene or node references; depends only on `CardDB`. Must be listed **after `CardDB`** in `project.godot`. No per-match state. |
```

**REPLACE** the first sentence of the `BattleManager` row (`Match state owner: team registries, structures, spawn entry points, hero respawn, match timer, `match_ended``) with:

```markdown
Match state owner: team registries, structures, spawn entry points, the per-team **match manifest** (levels + synergy, §3), hero respawn, match timer, `match_ended`
```

## §3 Data layer

**REPLACE** the whole fenced `data/` tree block with:

```
data/
  cards/<pantheon>/    CardData   — id (card_<pantheon>_<name>), display_name,
                                    cost, scroll_texture, unit_data XOR
                                    spell_data, unit_count, formation_radius,
                                    + collection fields: rarity (int 0–3),
                                    obtain_source (int), faction (pantheon),
                                    domain, tags, description
  units/<pantheon>/    UnitData   — id, archetype_scene, max_hp, damage,
                                    attack_cooldown, speed, target_filter,
                                    sprite_frames, attack_type, attack_range,
                                    projectile_scene, damage_point_ratio,
                                    attack_sfx / death_sfx
    frames/            SpriteFrames
  heroes/<pantheon>/   HeroData   — id, stats, projectile_scene, sprite_frames,
                                    sounds, + collection fields: rarity (4 =
                                    UNIQUE), obtain_source, faction, domain,
                                    description, forbidden_tags, synergy_tag,
                                    synergy_count, synergy_bonuses
    frames/            SpriteFrames
  spells/<pantheon>/   SpellData  — id, display_name, spell_type (int),
                                    radius, cast_time, zone_duration,
                                    effect_duration, damage, tick_interval,
                                    slow_multiplier, sprite_frames
    frames/            SpriteFrames
  packs/               PackData   — id, display_name, card_count, faction
                                    filter, rarity_weights (5), guaranteed_
                                    min_rarity, price
  progression/         LevelCurve — max_level, copies per level per rarity,
                                    stat multiplier per level, god attack-speed
                                    multiplier per level (one file, all tuning)
  maps/                MapData    — (unchanged)
  sounds/              SoundData  — (unchanged)
```

**REPLACE** the resolution chain (`card_id → CardDB.get_card() → CardData.unit_data → archetype_scene.instantiate() → configure(data, team) → add to arena`) with:

```markdown
`card_id → CardDB.get_card() → CardData.unit_data → archetype_scene.instantiate()
→ configure(data, team, stat_mods) → add to arena`, where `stat_mods` is the
multiplier dictionary `BattleManager` builds from the team's manifest (below).
```

**ADD** at the end of §3 (after the map/tile WIP paragraph):

```markdown
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
  `[synergy]` / `[spawn]` diagnostics, off by default.

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
```

## §4 Battle scene structure

**ADD** a bullet after the `scenes/arena/ui/EnergyBar.tscn` bullet:

```markdown
- `scenes/arena/ui/SynergyIcon.tscn` (`synergy_icon.gd`, `class_name
  SynergyIcon`) — a `Button` in the HUD beside the energy bar, left of the
  hand. Shows the player's synergy count; grey when the deck threshold is not
  met, gold and pulsing when it is; a tap toggles a tooltip (auto-hides) with
  the `DeckRules.describe_synergy()` text. Being a `Button`, it consumes the
  tap so it never reaches tap-to-move. Configured once by
  `arena.gd` (`hud.synergy_icon.configure("player")`) after the manifests are
  set — the state cannot change during a match. Placeholder look, no art.
```

**REPLACE**, inside the `scenes/hud/HUD.tscn` bullet, the text `` `EnergyBar`, `MatchInfoBar` (timer label, tower icons, two `RespawnCounter`s driven by BattleManager signals). `` with:

```markdown
`EnergyBar`, `SynergyIcon`, `Minimap`, `MatchInfoBar` (timer label, tower
  icons, two `RespawnCounter`s driven by BattleManager signals). The hand's
  deck comes from `MatchConfig` (§3), not from `CardHand.tscn`.
```

## §6 Conventions & known pitfalls

**ADD** at the end of the list:

```markdown
- **The HUD is ready before the match manifest exists.** HUD children run
  `_ready()` before `arena.gd::_ready()` sets the manifests, so HUD UI that
  shows match-derived state gets an explicit `configure()` call from the arena
  afterwards (`minimap.configure_map()`, `synergy_icon.configure()`), instead
  of reading `BattleManager` in its own `_ready()`.
- **A fifth resource directory changed nothing in the scanner** — but the
  recursive scan must keep skipping `frames/`: `SpriteFrames` have no `id` and
  would each raise "failed to load resource".
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
  `SynergyIcon` greys the circle and count but leaves its tooltip readable.
- **Hand-written `.tres` / `.tscn` reference new files by `path=` only.** Never
  invent a `uid`; Godot assigns one. When moving resources outside the editor,
  keep every existing `uid` and fix the `path=` strings.
```

## §7 Networking posture

**ADD** at the end of the list:

```markdown
- **The match manifest is the deck message.** Today `MatchConfig` is filled
  locally; with networking, both sides exchange `{hero_id, hero_level,
  card_levels}` once before the match and a server validates it against the
  player's inventory. Spawn messages do not change.
- **`PlayerProfile`'s mutation API is the server boundary** for the meta game:
  `grant_cards()`, `upgrade_card()`, `set_deck()` become requests; `PackRoller`
  and `DeckRules` run server-side unchanged because they take all inputs as
  arguments. The local JSON save is a stand-in and is cheatable by design.
- **Synergy is derived, not transmitted.** Both sides compute it from the same
  manifest and the same card database, so it needs no message — but it makes
  `tags`, `domain`, `faction` and the gods' synergy fields part of the database
  version both clients must agree on.
```

## §8 Main menu / UI shell

**REPLACE** the bullet starting `- `NavRail` (`VBoxContainer`, left edge, anchored full-height)` with:

```markdown
- `NavRail` (`VBoxContainer`, left edge, anchored full-height) —
  `DeckButton` (inventory icon) → `EncyclopediaOverlay`; `HeroesButton` →
  `DeckOverlay` (the button will be renamed); `ShopButton` → `ShopOverlay`;
  `RewardsButton` → `_show_coming_soon()`; a `Control` spacer; `ExitButton`.
  All are `TextureButton`s.
```

**ADD** after the `SettingOverlay` / `CreditsOverlay` bullet:

```markdown
- `ShopOverlay`, `DeckOverlay`, `EncyclopediaOverlay` — three more fullscreen
  overlay instances following the same pattern (`open()` / `close()`, a
  `closed` signal, `move_to_front()` at open, nav rail and main content hidden
  while open). Unlike the two older overlays they are connected **in code** in
  `main_menu.gd::_ready()`, not with `[connection]` entries. Plain default-theme
  controls, no art yet.
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
    Gods / Units / Spells of `DeckTile`s (locked ones tappable). Hosts
    `card_flashcard.tscn` (`CardFlashcard`): the detail panel with the stat
    preview and the level-up button (`PlayerProfile.upgrade_card()`). The
    overlay rebuilds on `PlayerProfile.profile_changed`.
- Debug keys in the main menu (debug builds only): **F9** reset profile,
  **F10** +1 copy of everything obtainable, **F11** toggle `DebugLog`.
```

---

# 3. `cards_greek.md`

## Header blockquote

**ADD** a line at the end of the opening blockquote:

```markdown
> **Vocabulary changed (Oct 2026):** what this file calls an *era* is now a
> **faction / pantheon**; what it calls a *faction* (Olympus, Sea, Underworld)
> is now a **domain**, shared across pantheons. See `game_design.md` §3.14.
```

## §1 Structure overview

**REPLACE** the bullet starting `- **Era rule**: common cards never cross eras.` with:

```markdown
- **Pantheon rule (changed Oct 2026):** a deck *may* mix pantheons — a Greek
  god can field Norse scrolls. The cost is synergy: foreign scrolls neither
  count toward the god's threshold nor receive its bonus. Card ids are still
  never reused between pantheons.
```

## §2 Faction synergy rule

**REPLACE** the whole section body (the sentence and the Open Question 1 blockquote) with:

```markdown
**Resolved (Oct 2026).** Each god has one synergy rule: *if the deck holds at
least N scrolls carrying the god's synergy tag, from the god's own pantheon,
every scroll of that pantheon gets the god's bonus.* Units and spells both
count. One threshold, no tiers. The bonus is always a boost (unit stats, spell
damage or energy regeneration, depending on the god) — never a cost discount.

Zeus: four Olympus scrolls → Greek units +10 % HP and +10 % damage (numbers are
placeholders). Poseidon: four Sea scrolls, same placeholder bonus.

Most spells will carry only their pantheon as a tag; a domain tag (sea,
olympus, underworld, nature) on a spell is the exception.
```

## §6 Deck composition

**REPLACE** the Open Question 2 blockquote with:

```markdown
**Deck size resolved (Oct 2026): 1 god + 7 scrolls**, units and spells mixed,
no duplicates, one deck per god.

> ⚠️ **OPEN QUESTION 2 — sidekick acquisition** *(still open)*
> - Is the sidekick a permanent escort spawned with the hero, a card in the
>   deck, or unlocked/leveled separately from the hero?
> - Related open questions already listed in `heroes_greek.md`: sidekick death
>   handling, auto-cast vs player-triggered specials.
```

## §7 Era scaling template

**REPLACE** the last line (`Design work per era = 1 common pool + 2–3 factions + hero/sidekick pairs. No cross-era deck mixing.`) with:

```markdown
Design work per pantheon = 1 common pool + 2–3 domains + god/sidekick pairs,
plus the tags its gods refuse and each god's synergy rule. Decks may mix
pantheons at the cost of synergy.
```

## §8 Next steps

**REPLACE** these four checklist lines:

```
- [ ] Resolve Open Question 1 (faction bonus type) — SWFA research
- [ ] Resolve Open Question 2 (sidekick spawn/acquisition) — SWFA research
- [ ] Stat pass on common pool (HP / DPS / speed / cost numbers)
- [ ] Card rarity & upgrade/collection progression (separate economy spec)
```

and the line starting `- [ ] Decide whether spells count against the deck's card slots` with:

```markdown
- [x] Open Question 1 (synergy type) — resolved, §2
- [ ] Open Question 2 — deck size resolved (god + 7); sidekick still open
- [x] First stat pass on all 20 Greek units (values in
      `claude/scrolls_decisions.md`); cards exist for the eight human units.
      Balance pass still to do.
- [x] Card rarity, leveling and collection — built (`game_design.md` §3.14);
      per-card rarities are still placeholders
- [x] Spells take normal deck slots
- [ ] Domain cards: Pegasus, Bronze Automaton (Olympus); Hippocampus Rider,
      Nereid, Ketos (Sea); Shades, Spartoi, Erinyes (Underworld) — unit data
      exists with placeholder sprites, no cards yet
- [ ] Tag vocabulary (holy, undead, beast…) and which gods refuse what
- [ ] Synergy rule for every god beyond Zeus and Poseidon
- [ ] Mechanics the unit data cannot express yet: healing (Priestess, Nereid),
      charge bonus (Hippeus), formation armor (Phalanx), flying (Harpy,
      Pegasus), Cyclops boulder throw
```

---

# 4. `claude/unit_authoring_guide.md`

## §1

**REPLACE** every `data/units/<id>.tres` with `data/units/<pantheon>/<id>.tres`, and the sentence `At boot, `CardDB` scans `data/units/*.tres` into an id-keyed dictionary` with:

```markdown
At boot, `CardDB` scans `data/units/` **recursively** (skipping `frames/`
folders) into an id-keyed dictionary
```

**REPLACE** `calls `configure(data, team)`, which copies every stat onto the node` with:

```markdown
calls `configure(data, team, stat_mods)`, which copies every stat onto the node
— multiplied by `stat_mods`, the level and synergy multipliers `BattleManager`
looks up for that team and card (never written back to the resource)
```

## §2.1

**REPLACE** `data/units/frames/frames_<id>.tres` with `data/units/<pantheon>/frames/frames_<id>.tres`.

## §2.4 Wire it into a card

**ADD** at the end of the section:

```markdown
Card files live in `data/cards/<pantheon>/` and are named after their id:
`card_<pantheon>_<name>` (e.g. `card_greek_hoplite`). Besides the play fields,
set the collection fields: `rarity` (0 Common … 3 Legendary),
`obtain_source` (leave 0 for a test card that must never appear in packs or
screens; 1 = drops from packs), `faction` (pantheon, defaults to `greek`),
`domain` (empty = common pool), `tags` (only extra labels — pantheon and
domain count automatically) and `description` (flashcard text). A new card
appears in the Encyclopedia and the Deck pool automatically once
`obtain_source` is not 0; it enters matches only through a player's deck.
```

## §4 Verification checklist

**ADD** an item:

```markdown
10. Press **F11** in the main menu (debug build) and deploy the unit: the
    `[spawn]` line shows its card level and multipliers. Level 1 with no
    synergy must read `1.0` on all four.
```

---

# 5. `claude/hero_authoring_guide.md`

**ADD** a new section at the end (adjust the number to follow the last one):

```markdown
## Gods as scrolls (Oct 2026)

`HeroData` files live in `data/heroes/<pantheon>/`, frames in
`data/heroes/<pantheon>/frames/`. `configure(data, team, stat_mods)` on both
`player.gd` and `hero_dummy.gd` takes the god's level multipliers: `max_hp`
and `projectile_damage` are multiplied, `recovery_time` is divided by the
attack-speed multiplier. Synergy never buffs the god itself.

Collection and rule fields on `HeroData`:

| Field | Guidance |
|---|---|
| `rarity` | Leave at 4 (UNIQUE). |
| `obtain_source` | 0 = never granted; 1 = drops from packs whose Unique weight is above 0. |
| `faction` | Pantheon (`greek`, `norse`…). Decides who benefits from the god's synergy. |
| `domain` | `olympus`, `sea`, `underworld`… Informational today. |
| `forbidden_tags` | Tags this god refuses in its deck. Empty = neutral. Compared against a card's `tags` + pantheon + domain. **Check that at least 7 obtainable cards remain allowed** — the game logs an `OBSAH` error at launch otherwise. |
| `synergy_tag` / `synergy_count` | The deck threshold: how many own-pantheon scrolls with this tag. Empty tag = no synergy. |
| `synergy_bonuses` | Multipliers once the threshold is met: `max_hp`, `damage`, `speed`, `attack_speed` (units), `spell_damage`, `energy_regen`. |
| `description` | Flashcard text. |

The Deck screen and Encyclopedia show a god's first `iddle_left` frame (falls
back to `idle_left`) as its picture — there is no separate scroll art for gods.
```

---

# 6. Drift noticed that is not from the Scrolls work

Not patched here — decide which side is right:

- `game_design.md` §3.10 says the AI plays **at most one card per tick** and deploys units **at its own spawn point**. The code's own comments say it plays **every** affordable slot each tick and jitters unit positions around its **hero**.
- `architecture.md` §8 described the nav-rail buttons as plain `Button`s with flat colours; the scene uses `TextureButton`s with art (the §8 block above already says so).
- `game_design.md` §3.2 says only the melee archetype exists; a ranged archetype and a siege-style unit (Gastraphetes) have existed since September.
- `AGENTS.md` in the repo (the Codex twin of `CLAUDE.md`) still says Godot 4.6 and predates all of this.
