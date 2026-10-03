# Scrolls — Confirmed Decisions (2026-10-03)

Companion to `DGB_Scrolls_Card_Collection_Design.docx`. Records Bakula's answers to decisions 1–11 and the follow-up answers on gods. Where this file and the docx disagree, this file wins.

## Vocabulary (changed 2026-10-03)

- **Faction = pantheon**: Greek, Norse, Chinese, Mayan… (the docs and step 1 called this "era").
- **Domain = cross-pantheon grouping**: Olympus/sky, sea, underworld… (the docs and step 1 called this "faction"). All sea gods across all pantheons give the same synergy bonus.
- Data fields are renamed to match in step 1b: `era` → `faction`, `faction` → `domain`.

## Decisions

| # | Decision | Status | Final |
|---|---|---|---|
| 1 | Deck size | **Overridden** | SWFA shape: **1 god (hero) + 7 cards**, units and spells mixed. Not 8. |
| 2 | Spells | Confirmed | Spells take normal deck slots. |
| 3 | Rarities | **Amended** | Common/Rare/Epic/Legendary share one level scale. Gods get their own fifth tier, **Unique**. |
| 4 | Level cap and curve | Confirmed | Cap 10; copies per level e.g. 2/4/10/20/50 for Commons, fewer for rarer; diminishing increments, ~+50% total. All in a tunable resource. |
| 5 | What scales | **Amended** | Units: HP + damage. Spells: damage only. CC durations never scale. **Gods: HP, damage and attack speed.** |
| 6 | Upgrade cost | Confirmed | Copies only in phase 1. |
| 7 | Pack shape | **Amended** | One "Greek Scroll Pack", 5 cards, one Rare+ guaranteed, pantheon filter. Rarity weights live per pack: Unique is **0% in low-cost packs**, and only "cherished" packs and events carry a chance. |
| 8 | Obtainability | **Amended** | CardData and HeroData get `rarity`, `faction` (pantheon), `obtain_source` (replaces the `obtainable` bool). |
| 9 | Starter set | **Amended** | Starter deck = god + **7** cards at level 1. **Gods are cards/scrolls too**, obtainable through pack drops; some gods are exclusive to an achievement, quests or special events. |
| 10 | AI levels | Confirmed | AI mirrors the player's deck and levels. |
| 11 | Number of decks | Confirmed | One deck; versioned save. |

## Gods — follow-up answers

| Topic | Decision |
|---|---|
| God leveling | Gods level up with copies like every other card. Level scales **HP, damage and attack speed**. |
| God rarity | Own tier, **Unique**; this is what gates them out of cheap packs (weight 0) and into cherished packs / events. |
| Duplicate god | Adds to the god's copy stack. Player-to-player trading is a possible future use of duplicates — **omitted for now**. |
| Starter god | **Zeus**. |
| Event-only gods | A few gods will be obtainable only through special events. Which ones: decided later. |
| Synergy rule | The god grants a **synergy bonus** to matching units; it does **not** restrict the deck. Matching is by **domain**, shared across pantheons. |
| Synergy bonus type | **Stat boost** (not cost discount) — resolves cards_greek.md Open Question 1. The boosted stats are **per god/domain**. **Zeus: HP and damage.** Others will boost different stats (move speed, attack speed, …). |
| Synergy trigger | Intended design: the bonus is **earned by fulfilling the god's passive-ability condition**, not always on. **Kept simple for now** — the condition system is not designed yet. |
| Attack speed | For now implemented the simple way (shorter cooldown/recovery after the hit). Bakula is **not satisfied with cooldown-only**; a proper attack-speed rework (swing/animation speed) is **postponed**. |
| Deck restrictions | Not used now, but the mechanism must exist: some combinations will be forbidden later (arch-enemies cannot field their opposites' units — "holy entities won't hire defiled vampires"). |

## Data organisation (decided 2026-10-03)

- Folders are **type, then pantheon**: `data/cards/greek/`, `data/units/greek/` (+ `frames/`), `data/heroes/greek/` (+ `frames/`), `data/spells/greek/` (+ `frames/`). No folders by rarity or domain (both are tunable data, not identity).
- `CardDB` scans recursively and skips `frames` folders.
- Cards are named, not numbered: file and id `card_<pantheon>_<name>` (e.g. `card_greek_hoplite`). The numbered test cards `card_01`–`card_09` are deleted; spell cards become `card_greek_storm` / `_stun` / `_ensnaring_net`.
- Unit, hero and spell-data ids are unchanged (`greek_hoplite`, `hero_zeus`, `spell_storm`).

## Consequences

- **Hero cards are in scope** (the docx listed them as out of scope). The deck is `{hero_id, cards[7]}`, and the deck manifest exchanged at match start carries the hero and its level too.
- Gods use the same ownership record as cards (`copies`, `level`), so `grant_cards()` / `upgrade_card()` need no god-specific path.
- `obtain_source` (plain int: 0 NONE, 1 PACK, 2 ACHIEVEMENT, 3 QUEST, 4 EVENT) says where additional copies come from. The starter grant is a separate list, not a source value, because starter cards must also drop from packs. `PackRoller` only rolls source PACK, and Unique only when the pack's Unique weight is above 0.
- `PackData` carries a rarity-weight table per pack rather than one global table.
- Synergy is data on the god: `HeroData.synergy_bonuses` is a `{stat: multiplier}` dictionary (keys `max_hp`, `damage`, `speed`, `attack_speed`), applied at unit spawn next to level scaling when the card's `domain` matches the god's. `&""` domain = common pool.
- Deck restrictions: a pure-math `DeckRules.validate(hero_id, card_ids) -> Array` of violations, driven by data (exclusion list empty for now), called from `PlayerProfile.set_deck()` and later by the server.
- A 7-card deck with 3 hand slots + 1 preview leaves 3 cards unseen in the cycle queue.
- cards_greek.md Open Question 2 is resolved on deck size (hero + 7). The sidekick part is still open.

## Placeholder numbers (LevelCurve, all tunable)

| Rarity | Copies to next level (1→2 … 9→10) |
|---|---|
| Common | 2, 4, 10, 20, 50, 100, 200, 400, 800 |
| Rare | 2, 3, 6, 12, 25, 50, 100, 200, 400 |
| Epic | 1, 2, 4, 8, 15, 30, 50, 100, 200 |
| Legendary | 1, 1, 2, 4, 6, 10, 15, 20, 30 |
| Unique | 1, 1, 2, 2, 3, 4, 5, 6, 8 |

- Stat multiplier by level 1–10: 1.00, 1.08, 1.15, 1.21, 1.27, 1.32, 1.37, 1.41, 1.45, 1.48.
- God attack-speed multiplier by level 1–10: 1.00 to 1.18 in steps of 0.02 (smaller cap because it multiplies with damage).
- Synergy bonus: ×1.1 on each boosted stat.

## Build progress

| Step | Status |
|---|---|
| 1. Data: fields on CardData/HeroData, `LevelCurve`, tags on existing data | Prompt `prompt_scrolls_step1_data.md`; Claude Code working on it 2026-10-03 |
| 1b. Restructure: type/pantheon folders, recursive `CardDB`, named cards, `era`→`faction` / `faction`→`domain` | Prompt `prompt_scrolls_step1b_restructure.md` written 2026-10-03; run after step 1 |
| 2. `PlayerProfile` autoload, starter grant, deck as single source for hand and AI | Not started |
| 3. Levels and synergy in matches (deck manifest, scaling in `configure()`) | Not started |
| 4. `PackData` + `PackRoller` + Shop screen | Not started |
| 5. Collection + Deck screen, `DeckRules` | Not started |
| 6. Debug panel | Not started |

## Still open

1. Which gods are pack / achievement / quest / event. Zeus is the starter; Poseidon is tagged PACK as a placeholder so the cherished-pack path is testable.
2. Starter deck: which 7 of the 11 named cards (8 units + 3 spells).
3. Card rarities for the Greek roster (placeholders: Hippeus, Phalanx, Priestess, Gastraphetes, Storm, Stun = Rare; the rest Common).
4. God passive-ability conditions that unlock the synergy bonus.
5. Attack-speed rework (postponed).
6. Sidekick: escort, card, or separate unlock (cards_greek.md Open Question 2, second half).
7. Priestess scroll art is missing from `decals_greek.png` (her card uses the Hoplite cell as a placeholder).

## Greek unit roster — first stat pass (2026-10-03)

`greek_<id>.tres` for 17 new units were authored with placeholder sprite frames (hoplite frames for melee, toxotes frames for ranged). Anchor: hoplite 150 HP / 10 dmg / 1.2 s cooldown / speed 35; turret 300 HP, 20 dmg per 1.5 s, range 120. The first eight (human soldiery) have cards: `card_greek_<name>.tres` with the cost × count below.

| Unit | Domain | Type | HP | Dmg | CD | Speed | Range | Card (cost × count) |
|---|---|---|---|---|---|---|---|---|
| Hoplite (existing) | Common | Melee | 150 | 10 | 1.2 | 35 | 16 | 2 × 1 |
| Toxotes (existing; proposed 80 / 12 / 1.4) | Common | Ranged | 150 | 10 | 1.2 | 35 | 90 | 2 × 1 |
| Peltast | Common | Ranged | 60 | 9 | 1.0 | 45 | 60 | 2 × 2 |
| Sphendonetes | Common | Ranged | 45 | 5 | 1.1 | 35 | 110 | 1 × 2 |
| Hippeus | Common | Melee | 200 | 24 | 1.6 | 65 | 18 | 4 × 1 |
| Phalanx | Common | Melee | 190 | 12 | 1.4 | 28 | 22 | 5 × 3 |
| Priestess | Common | Ranged | 90 | 6 | 1.6 | 32 | 80 | 3 × 1 |
| Gastraphetes (existing) | Common | Ranged, structures only | 150 | 30 | 2.0 | 20 | 150 | 5 × 1 |
| Satyr | Common | Melee | 55 | 7 | 0.9 | 48 | 14 | 2 × 3 (suggested) |
| Centaur | Common | Melee | 300 | 18 | 1.2 | 50 | 18 | 4 × 1 (suggested) |
| Harpy | Common | Melee | 110 | 14 | 0.9 | 60 | 14 | 3 × 1 (suggested) |
| Cyclops | Common | Melee | 650 | 45 | 2.4 | 22 | 22 | 6 × 1 (suggested) |
| Pegasus | Olympus | Melee | 240 | 18 | 1.1 | 70 | 16 | 4 × 1 (suggested) |
| Bronze Automaton | Olympus | Melee | 520 | 28 | 1.8 | 26 | 18 | 5 × 1 (suggested) |
| Hippocampus Rider | Sea | Melee | 300 | 24 | 1.4 | 50 | 20 | 4 × 1 (suggested) |
| Nereid | Sea | Ranged | 110 | 8 | 1.5 | 36 | 85 | 3 × 1 (suggested) |
| Ketos | Sea | Melee | 800 | 55 | 2.6 | 20 | 26 | 7 × 1 (suggested) |
| Shades | Underworld | Melee | 35 | 6 | 1.0 | 42 | 14 | 2 × 4 (suggested) |
| Spartoi | Underworld | Melee | 120 | 13 | 1.1 | 38 | 16 | 3 × 2 (suggested) |
| Erinyes | Underworld | Melee | 160 | 26 | 1.0 | 58 | 16 | 4 × 1 (suggested) |

Mechanics in cards_greek.md that `UnitData` cannot express yet (stats above are base stats only): healing (Priestess, Nereid), first-hit charge bonus (Hippeus), formation armor (Phalanx), flying / terrain crossing (Harpy, Pegasus), Cyclops boulder throw.