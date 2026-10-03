# Claude Code prompt — Scrolls step 2: PlayerProfile + one deck source

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** steps 1 and 1b are merged (`data/cards/greek/card_greek_*.tres` exist, `CardDB` scans recursively). If `data/cards/greek/card_greek_hoplite.tres` does not exist, stop and tell me.

## Goal

1. A `PlayerProfile` autoload that owns the player's collection (owned cards and gods, copies, levels) and the deck (**1 god + 7 cards**), saved to `user://profile.json`.
2. A starter grant on first launch.
3. The match reads the deck from **one place**: the player's hand and the enemy AI both take their card ids from `MatchConfig`, which `PreMatchFlow` fills from `PlayerProfile`. The hardcoded deck in `CardHand.tscn` and the duplicated id list in `enemy_card_ai.gd` are removed.

No UI in this step. No levels applied in matches. Code comments: the project's mixed Slovak/English style, no diacritics.

## 1. `scripts/CardDB.gd` — two lookups without error spam

Add next to the existing getters (the getters themselves stay unchanged):

```gdscript
# Tiche overenie existencie — get_card()/get_hero() pri neznamom id
# push_error-uju, co sa nehodi pri validacii ulozeneho profilu.
func has_card(id: StringName) -> bool:
	return _cards.has(id)

func has_hero(id: StringName) -> bool:
	return _heroes.has(id)
```

## 2. New file `scripts/PlayerProfile.gd` (autoload)

Pure state + file IO. **No scene, node or UI references.** Its only dependency is `CardDB`.

```gdscript
extends Node

# PlayerProfile — zbierka hraca (vlastnene karty a bohovia, kopie, levely)
# a balicek (1 boh + DECK_SIZE kariet). Uklada sa do user://profile.json.
#
# JEDINE mutacne API: grant_cards(), set_deck(), reset_profile(). Neskor sa
# z nich stanu server volania — nikto iny NESMIE menit zbierku priamo.
# Lokalny save je cheatovatelny; pre testovanie je to v poriadku.
# Ziadne sceny/nody — rovnaky kontrakt ako EnergySystem.

signal profile_changed

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 1
const DECK_SIZE := 7

# Starter grant — prvy start (alebo poskodeny/nekompatibilny save).
const STARTER_HERO: StringName = &"hero_zeus"
const STARTER_CARDS: Array[StringName] = [
	&"card_greek_hoplite", &"card_greek_toxotes", &"card_greek_peltast",
	&"card_greek_hippeus", &"card_greek_gastraphetes",
	&"card_greek_storm", &"card_greek_stun",
]

# id -> {"level": int, "copies": int}. copies = duplikaty NAD prvy kus.
var _cards: Dictionary = {}
var _heroes: Dictionary = {}
var _deck_hero: StringName = &""
var _deck_cards: Array[StringName] = []
```

Public read API (all return copies, never the internal containers):

| Function | Returns |
|---|---|
| `owns_card(id: StringName) -> bool`, `owns_hero(id: StringName) -> bool` | ownership |
| `get_card_level(id) -> int`, `get_hero_level(id) -> int` | level, `0` if not owned |
| `get_card_copies(id) -> int`, `get_hero_copies(id) -> int` | duplicate count, `0` if not owned |
| `get_owned_card_ids() -> Array[StringName]`, `get_owned_hero_ids() -> Array[StringName]` | ids |
| `get_deck_hero() -> StringName` | deck god |
| `get_deck_cards() -> Array[StringName]` | `_deck_cards.duplicate()` |

Mutation API:

- `grant_cards(ids: Array[StringName]) -> void` — for each id: if `CardDB.has_card(id)` it goes to `_cards`, else if `CardDB.has_hero(id)` to `_heroes`, else `push_warning` and skip. Not owned yet → `{"level": 1, "copies": 0}`. Already owned → `copies += 1`. Then **one** `save_profile()` and **one** `profile_changed.emit()` for the whole call.
- `set_deck(hero_id: StringName, card_ids: Array[StringName]) -> bool` — valid only if: hero owned, exactly `DECK_SIZE` cards, every card owned, no duplicates. Invalid → return `false`, change nothing. Valid → store, save, emit, return `true`.
- `reset_profile() -> void` — clear everything, apply the starter grant, save, emit.

Persistence:

- `save_profile()` writes JSON (`JSON.stringify(data, "\t")`) in this exact shape; `StringName` ids are written as plain strings:

```json
{
	"save_version": 1,
	"cards": { "card_greek_hoplite": { "level": 1, "copies": 0 } },
	"heroes": { "hero_zeus": { "level": 1, "copies": 0 } },
	"deck": { "hero": "hero_zeus", "cards": ["card_greek_hoplite", "..."] }
}
```

- `load_profile()` is called from `_ready()`:
  1. File missing → starter grant, save.
  2. Unparseable JSON, root not a Dictionary, or `save_version != SAVE_VERSION` → `push_warning`, starter grant, save. (No migration code yet — there is only one version.)
  3. Otherwise read `cards` / `heroes` / `deck`. JSON numbers arrive as float → `int()`. Convert ids back to `StringName`. **Silently drop** any id that `CardDB` no longer knows (renamed or deleted content), with one `push_warning` per dropped id. Clamp `level` to at least 1 and `copies` to at least 0.
  4. If the loaded deck is not valid (same rule as `set_deck`), fall back to the starter deck: make sure the starter god and starter cards are owned (grant only the missing ones, never add copies to ones already owned), set the deck to the starter deck, save.
- At the end of `load_profile()`, one debug line: `print("[profile] hero=%s deck=%s owned_cards=%d owned_heroes=%d" % [...])`.

The starter grant = own `STARTER_HERO` and the 7 `STARTER_CARDS` at level 1 with 0 copies, deck = that god + those 7 cards.

## 3. `project.godot` — register the autoload

Add exactly one line to `[autoload]`, directly after the `CardDB=` line (it must load after `CardDB`):

```
PlayerProfile="*res://scripts/PlayerProfile.gd"
```

## 4. `scripts/MatchConfig.gd` — carry the deck into the match

Add four fields (keep everything else; `MatchConfig` still takes no dependency on other autoloads):

```gdscript
# Balicky pre zapas — naplna PreMatchFlow z PlayerProfile (MatchConfig sam
# neberie zavislost na inom autoloade). Zaklad buduceho "deck manifest"-u,
# ktory si klienti vymenia na zaciatku zapasu; levely pridu v dalsom kroku.
var local_hero_id: StringName = &""
var local_deck_card_ids: Array[StringName] = []
var opponent_hero_id: StringName = &""
var opponent_deck_card_ids: Array[StringName] = []
```

Update the header comment line `NIC z tohto sa neposiela po sieti — iba lokalny display holder.` so it says the display fields are local-only while the deck fields are the future manifest.

## 5. `scripts/ui/prematch_flow.gd` — fill it

In `_ready()`, right after `MatchConfig.map_id = MapDB.get_random_map_id()`:

```gdscript
	# Balicek hraca z profilu. AI zatial ZRKADLI hracove karty (ferovy zaklad
	# pre testovanie); boh supera je TEMP napevno, kym nie je realny vyber.
	MatchConfig.local_hero_id = PlayerProfile.get_deck_hero()
	MatchConfig.local_deck_card_ids = PlayerProfile.get_deck_cards()
	MatchConfig.opponent_hero_id = &"hero_poseidon"
	MatchConfig.opponent_deck_card_ids = PlayerProfile.get_deck_cards()
```

## 6. `scripts/arena/arena.gd`

- Delete the constants `PLAYER_HERO_ID` and `ENEMY_HERO_ID` (lines 20–21) and their TEMP comment (lines 18–19).
- The two `BattleManager.spawn_hero(...)` calls use `MatchConfig.local_hero_id` and `MatchConfig.opponent_hero_id` instead.
- Extend the existing known-limitation comment above `var map_data` to say that opening `arena.tscn` directly (F6) also leaves the hero ids and decks empty.

## 7. `scripts/arena/ui/card_hand.gd` + `scenes/arena/ui/CardHand.tscn`

`card_hand.gd`:

- Remove `@export var deck: Array[CardData] = []` (line 13).
- In `_ready()`, replace `_cycle = deck.duplicate()` (line 31) with a build from `MatchConfig.local_deck_card_ids`:

```gdscript
	# balicek prichadza z MatchConfig (naplneny z PlayerProfile v PreMatchFlow)
	_cycle.clear()
	for id in MatchConfig.local_deck_card_ids:
		var card := CardDB.get_card(id)
		if card != null:   # CardDB.get_card uz push_error-uje samo
			_cycle.append(card)
```

- The slot fill loop must not crash on a short deck: only `configure()` a slot while `_cycle` is not empty.
- Change nothing else in this file (drag, input, `play_card`, affordability stay as they are).

`CardHand.tscn`:

- Remove the `deck = Array[...]([...])` line (line 30) and the eleven card `ext_resource` lines (lines 6–16) plus the `card_data.gd` script `ext_resource` (line 5) if nothing else in the scene uses it. Fix `load_steps` in the header if present. Touch nothing else in the scene.

## 8. `scripts/arena/enemy_card_ai.gd`

- Remove the `@export var deck_card_ids` block (lines 36–40) and replace the comment above it (lines 32–35) with one saying the AI deck comes from `MatchConfig.opponent_deck_card_ids`, the same source the player's hand uses.
- In `_ready()`, iterate `MatchConfig.opponent_deck_card_ids` instead of `deck_card_ids`.
- The hand fill (`for i in 3`) must not append when `_cycle` is empty.
- Update the header paragraph that says the list mirrors `CardHand.tscn` by hand, if it still claims that.
- Nothing else changes (decision loop, jitter, validation, spend).

## DO NOT TOUCH

- `scripts/BattleManager.gd`, `scripts/EnergySystem.gd`, `scripts/MapDB.gd`, `scripts/AudioManager.gd`, `scripts/settings.gd`, `scripts/level_curve.gd`.
- `scripts/arena/unit.gd`, `player.gd`, `hero_dummy.gd`, `unit_data.gd`, `hero_data.gd`, `spell_data.gd`, `scripts/arena/ui/card_data.gd`, `scripts/arena/ui/card.gd`.
- `scripts/ui/main_menu.gd` and every scene except `CardHand.tscn`.
- Everything under `data/` and `assets/`.
- `project.godot` beyond the single autoload line.
- The debug keys in `arena.gd::_input()`.
- `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- `upgrade_card()`, any use of `LevelCurve`, levels or synergy applied to stats.
- Packs, pack rolling, shop, collection or deck-editing UI, debug panel.
- Deck restriction rules beyond the four checks in `set_deck`.
- Save migration, encryption, cloud sync, multiple deck slots.
- Changing the enemy god or giving the AI its own profile.
- A fallback deck for launching `arena.tscn` directly with F6.

## VERIFY

Static checks (run and report output):

1. `grep -rn "PLAYER_HERO_ID\|ENEMY_HERO_ID\|deck_card_ids" --include=*.gd --include=*.tscn . | grep -v "local_deck_card_ids\|opponent_deck_card_ids"` — no match.
2. `grep -n "deck\|data/cards" scenes/arena/ui/CardHand.tscn` — no match.
3. `grep -rn "PlayerProfile\." --include=*.gd scripts/` — only `scripts/ui/prematch_flow.gd`.
4. `grep -n "PlayerProfile" project.godot` — one line, placed after `CardDB=`.
5. `grep -n "get_node\|\$\|get_tree\|preload\|load(" scripts/PlayerProfile.gd` — no match (no scene references).
6. `grep -rn "user://profile.json" scripts/` — only `scripts/PlayerProfile.gd`.
7. `git status --short` — only the files named in sections 1–8.

Runtime checks (I run these in the Godot editor — list them for me, do not claim them as done):

1. First launch: console prints `[profile] hero=hero_zeus deck=[…7 ids…] owned_cards=7 owned_heroes=1`, and `profile.json` appears in the user data folder (Project → Open User Data Folder) in the shape above.
2. Start a match from the main menu: the hand cycles through exactly the 7 starter cards (Sphendonetes, Phalanx, Priestess and Net never appear), and the enemy plays cards from the same 7.
3. Player god is Zeus, enemy god is Poseidon, as before.
4. Close and relaunch: the `[profile]` line is identical and the file is unchanged.
5. Break the save on purpose (edit `profile.json` to `{`): on next launch a warning is printed, the starter profile is restored, the game runs.
6. Edit `profile.json` so the deck lists an id that does not exist: warning printed, deck falls back to the starter deck, no crash.
