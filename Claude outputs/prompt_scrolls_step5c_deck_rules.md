# Claude Code prompt — Scrolls step 5c: tags, forbidden cards, one deck per god

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 5b is merged (`PlayerProfile.upgrade_card()` and `scripts/ui/card_flashcard.gd` exist). If not, stop and tell me.

## Goal

1. **Tags and a god-against-card rule.** Cards carry tags; a god lists the tags it refuses. A neutral god refuses nothing. There are no card-against-card rules and no pantheon restriction — pantheons may be mixed freely.
2. **One deck per god.** The profile stores a deck for every god plus which god is active. Picking another god in the editor brings that god's saved deck, or a default one. Because every god has its own deck, a forbidden card can never be left behind by a god change.
3. **Save format v2** with a real migration from v1 (the player's progress must survive).
4. **Deck editor:** forbidden cards are greyed in the pool; switching god with unsaved card changes asks **Discard / Cancel**.

No tags are assigned to real content in this step, so the game plays exactly as before. Code comments: the project's mixed Slovak/English style, no diacritics.

## 1. Data fields

`scripts/arena/ui/card_data.gd` — add to the Scrolls metadata block:

```gdscript
# Volne znacky (holy, undead, beast, ...). Boh moze niektore odmietat
# (HeroData.forbidden_tags). faction a domain sa pri pravidlach rataju ako
# znacky automaticky — netreba ich sem opakovat.
@export var tags: Array[StringName] = []
```

Also fix the stale comment above `faction` (`Karty roznych panteonov sa nemiesaju.`): pantheons may now be mixed in one deck.

`scripts/arena/hero_data.gd` — add to its Scrolls block:

```gdscript
# Znacky kariet, ktore tento boh ODMIETA v balicku. Prazdne = neutralny boh.
# Porovnava sa s CardData.tags + faction + domain karty.
@export var forbidden_tags: Array[StringName] = []
```

Do not write tags into any `.tres`.

## 2. New file `scripts/deck_rules.gd`

Pure static rules — no nodes, no autoloads; takes resources as arguments so a server can call it later.

```gdscript
extends RefCounted
class_name DeckRules

# DeckRules — pravidla balicka: boh proti karte. Cista matematika, ziadne
# nody ani autoloady. Ziadne pravidla karta-proti-karte, ziadne obmedzenie
# panteonu (panteony sa mozu miesat).

# Vsetky znacky karty: explicitne tags + faction + domain (ak nie su prazdne).
static func card_tags(card: CardData) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(card.tags)
	if card.faction != &"" and not result.has(card.faction):
		result.append(card.faction)
	if card.domain != &"" and not result.has(card.domain):
		result.append(card.domain)
	return result

static func is_card_allowed(hero: HeroData, card: CardData) -> bool:
	if hero.forbidden_tags.is_empty():
		return true
	for tag in card_tags(card):
		if hero.forbidden_tags.has(tag):
			return false
	return true

# Id-cka kariet, ktore boh odmieta. Prazdne pole = balicek je v poriadku.
static func find_forbidden(hero: HeroData, cards: Array[CardData]) -> Array[StringName]:
	var bad: Array[StringName] = []
	for card in cards:
		if not is_card_allowed(hero, card):
			bad.append(card.id)
	return bad

# Predvoleny balicek pre boha bez ulozeneho balicka: zober `base` (balicek,
# ktory hrac prave pouzival), odmietnute karty nahrad prvymi povolenymi z
# `pool` (volajuci ho dodava zoradeny: cost, potom id). Vysledok moze byt
# KRATSI nez size, ak povolenych kariet nie je dost — to je chyba obsahu.
static func build_default_deck(hero: HeroData, base: Array[CardData], pool: Array[CardData], size: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for card in base:
		if result.size() < size and is_card_allowed(hero, card) and not result.has(card.id):
			result.append(card.id)
	for card in pool:
		if result.size() >= size:
			break
		if is_card_allowed(hero, card) and not result.has(card.id):
			result.append(card.id)
	return result
```

Use this code as given.

## 3. `scripts/PlayerProfile.gd` — a deck per god, save v2

State: replace `_deck_hero` / `_deck_cards` (lines 31–32) with:

```gdscript
# Balicek pre KAZDEHO boha: hero_id -> Array[StringName] (presne DECK_SIZE).
var _decks: Dictionary = {}
# Boh, s ktorym sa ide do zapasu. Jeho balicek je "aktivny".
var _active_hero: StringName = &""
```

`SAVE_VERSION := 2`. Update the header comment (line 4): one deck per god.

Read API:

- `get_deck_hero()` → `_active_hero` (unchanged meaning: the god taken into a match).
- `get_deck_cards()` → a copy of the active god's deck (unchanged meaning).
- New `has_saved_deck(hero_id: StringName) -> bool`.
- New `get_deck_for(hero_id: StringName) -> Array[StringName]`: the saved deck (a copy) if there is one; otherwise a default built with `DeckRules.build_default_deck(hero_data, base, pool, DECK_SIZE)` where `base` = the active deck's `CardData`s and `pool` = every **owned** card's `CardData`, sorted by `cost`, then id. Returns an empty array for an unknown god. Does **not** store anything.

Mutation API:

- `set_deck(hero_id, card_ids) -> bool`: valid only if the god is owned, exactly `DECK_SIZE` cards, each owned, no duplicates, **and** `DeckRules.find_forbidden(...)` is empty. Valid → `_decks[hero_id] = card_ids.duplicate()`, `_active_hero = hero_id`, save, emit, `true`. Invalid → `false`, nothing changes. Put the new forbidden check inside `_is_deck_valid()` so loading uses it too.
- `reset_profile()` and `_apply_starter()`: the starter deck becomes `_decks[STARTER_HERO]` and `_active_hero = STARTER_HERO`.

Save format v2:

```json
{
	"save_version": 2,
	"cards": { "card_greek_hoplite": { "level": 1, "copies": 0 } },
	"heroes": { "hero_zeus": { "level": 1, "copies": 0 } },
	"active_hero": "hero_zeus",
	"decks": { "hero_zeus": ["card_greek_hoplite", "..."] }
}
```

`load_profile()`:

1. Missing file → starter, as today.
2. Unparseable / not a Dictionary → warning + starter, as today.
3. **`save_version == 1` → migrate in memory**, then continue as v2: `decks = { deck.hero: deck.cards }`, `active_hero = deck.hero`. Keep `cards` and `heroes` untouched. After a successful load, save once so the file is rewritten as v2. Print `[profile] migrated save v1 -> v2`.
4. `save_version == 2` → read `cards`, `heroes`, `active_hero`, `decks`.
5. Any other version → warning + starter.
6. Validation after reading: drop every saved deck that fails `_is_deck_valid()` (one `push_warning` each). If the active god is not owned, or it has no valid deck left, fall back exactly like today's invalid-deck path (`_apply_starter(true)`), then save.

Content sanity check (a pantheon must not ship with a god that cannot field a deck): add `_check_content()` called at the end of `load_profile()` — for every god in `CardDB.list_hero_ids()`, count the cards with `obtain_source != 0` that `DeckRules.is_card_allowed()` accepts; if fewer than `DECK_SIZE`, `push_error("PlayerProfile: OBSAH — boh '%s' ma len %d povolenych kariet (treba %d)" % [...])`. It only reports; it changes nothing.

`_print_summary()`: print the active god, its deck, and the number of saved decks.

## 4. `scripts/ui/deck_tile.gd` — a forbidden state

Add next to `set_note()`:

```gdscript
# Karta, ktoru aktualny boh odmieta: seda, neda sa vybrat ani tahat.
func set_forbidden() -> void:
	locked = true
	modulate = Color(0.45, 0.45, 0.45)
	set_note("Forbidden")
```

Nothing else in this file changes.

## 5. `scripts/ui/deck_overlay.gd` — god switching and forbidden cards

- `_load_draft()` (lines 48–50) keeps using `get_deck_hero()` / `get_deck_cards()` (the active god and deck).
- **Dirty check** — a helper, no stored flag:

```gdscript
# Neulozene zmeny KARIET aktualneho draft boha (samotna vymena boha sa neráta).
func _has_unsaved_card_changes() -> bool:
	return _draft_cards != PlayerProfile.get_deck_for(_draft_hero)
```

- **Placing a god on slot 0** (in `_place()`, the `to_slot == 0` branch): if `id == _draft_hero` → nothing to do. Otherwise call a new `_request_hero_switch(id)`:
  - Compute `var deck := PlayerProfile.get_deck_for(id)`. If `deck.size() != PlayerProfile.DECK_SIZE` → `push_error` (content bug), show `"This god cannot field a full deck."` in `hint_label`, do not switch.
  - If `_has_unsaved_card_changes()` → show a confirmation dialog: text `"Unsaved changes to this deck will be lost."`, OK button `"Discard"`, cancel button `"Cancel"`. Discard → switch. Cancel → nothing changes. **There is no Save option in the dialog** — saving happens only through the main Save button.
  - Switch = `_draft_hero = id`, `_draft_cards = deck`, clear the selection, `_rebuild()`.
- The dialog is a `ConfirmationDialog` created in code in `_ready()` (`add_child`), connected in code; remember the pending god id in a variable. Do not add it to the `.tscn`.
- **Forbidden cards in the pool:** in `_rebuild()`, after creating each pool **card** tile, if the card is owned and `not DeckRules.is_card_allowed(CardDB.get_hero(_draft_hero), CardDB.get_card(id))` → `tile.set_forbidden()` (call it after `set_in_deck`).
- `_place()` card branch: additionally return `false` when the card is not allowed for `_draft_hero`.
- **Save** (line 65) is unchanged: `PlayerProfile.set_deck(_draft_hero, _draft_cards)` now also makes that god active.
- Cancel and Close behave as today (reload the active god and deck).
- Update the class comment (lines 4–8): one deck per god, the discard prompt.

## DO NOT TOUCH

- `scripts/ui/prematch_flow.gd` (it keeps calling `get_deck_hero()` / `get_deck_cards()`), `scripts/MatchConfig.gd`, `scripts/BattleManager.gd`.
- `scripts/ui/encyclopedia_overlay.gd`, `scripts/ui/card_flashcard.gd`, `scripts/ui/shop_overlay.gd`, `scripts/ui/main_menu.gd`, every `.tscn`.
- `scripts/CardDB.gd`, `scripts/level_curve.gd`, `scripts/pack_roller.gd`, `scripts/pack_data.gd`.
- In `PlayerProfile.gd`: `grant_cards`, `upgrade_card`, `can_upgrade`, `get_copies_to_next`, `_read_owned`, the level/copies data.
- Everything under `scripts/arena/` except the single `tags` export (and comment fix) in `ui/card_data.gd` and the single `forbidden_tags` export in `hero_data.gd`.
- Everything under `data/` and `assets/`, `project.godot`, `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- Card-against-card rules, pantheon or region ("continental") restrictions, allow-lists.
- Synergy changes of any kind (`synergy_bonuses`, `_unit_stat_mods`) — a separate step reworks synergy.
- Assigning tags or forbidden tags to any real card or god.
- Showing tags in the flashcard or encyclopedia; filters by tag.
- A Save option inside the discard dialog; a discard prompt on Cancel/Close; auto-save.
- Multiple decks per god, deck names, copying decks between gods.
- A separate AI deck: the AI keeps mirroring the player's active deck.

## VERIFY

Static checks (run and report output):

1. `grep -n "_deck_hero\|_deck_cards" scripts/PlayerProfile.gd` — no match (replaced by `_decks` / `_active_hero`).
2. `grep -n "SAVE_VERSION" scripts/PlayerProfile.gd` — value `2`, and the loader handles `1` (migration) and `2`.
3. `grep -n "get_node\|\$\|get_tree\|CardDB\|PlayerProfile" scripts/deck_rules.gd` — no match (pure).
4. `grep -rn "DeckRules\." --include=*.gd scripts/` — only `PlayerProfile.gd` and `scripts/ui/deck_overlay.gd`.
5. `grep -rn "set_deck" --include=*.gd scripts/` — the definition and the single call in `deck_overlay.gd`.
6. `git diff scripts/ui/prematch_flow.gd scripts/ui/encyclopedia_overlay.gd scripts/ui/card_flashcard.gd scenes/` — empty.
7. `grep -rn "tags = \|forbidden_tags = " data/` — no match.
8. `git status --short` — only `card_data.gd`, `hero_data.gd`, `deck_rules.gd` (new), `PlayerProfile.gd`, `deck_tile.gd`, `deck_overlay.gd`.

Runtime checks (I run these in the Godot editor — list them for me, do not claim them as done). **Back up `profile.json` first.**

1. Launch with the existing v1 save: console prints the migration line; levels, copies and the deck are all as before; `profile.json` is now version 2 with `active_hero` and `decks`.
2. Relaunch: no migration line, same data. No `OBSAH` error in the console.
3. A match plays as before with the active deck.
4. Own a second god (open Cherished packs until Poseidon appears). In the deck editor, drag Poseidon onto the god slot with no card edits: no prompt; his default deck is the same seven cards. Save → Poseidon is active; start a match → you play Poseidon.
5. Edit a card for Poseidon, Save. Switch to Zeus: Zeus's own deck comes back unchanged. Switch to Poseidon again: his edited deck comes back.
6. Change a card (do not save), then drag the other god onto the god slot: the dialog appears. Cancel → nothing changes. Discard → the other god's deck loads and the edit is gone.
7. Forbidden rule, temporarily in the Inspector: give `card_greek_gastraphetes.tres` `tags = [siege]` and `hero_poseidon.tres` `forbidden_tags = [siege]`. Delete Poseidon's entry from `decks` in `profile.json`. Relaunch: switching to Poseidon gives a default deck without Gastraphetes (replaced by the cheapest other owned card); Gastraphetes is grey and marked "Forbidden" in the pool and cannot be placed; under Zeus it is normal. Revert both `.tres` files afterwards.
8. With the test tags still set, put `forbidden_tags = [greek]` on Poseidon instead: the console shows the `OBSAH` error at launch and the editor refuses to switch to him with the hint text. Revert.
