# Claude Code prompt — Scrolls step 1b: data restructure, named cards, field rename

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 1 (`rarity` / `era` / `obtain_source` / `synergy_bonuses` fields, `LevelCurve`) is already merged. If `scripts/level_curve.gd` does not exist, stop and tell me.

## Goal

Three housekeeping changes, no gameplay change beyond the deck contents:

1. Folder `data/` by type, then pantheon (`greek`), and make `CardDB` scan recursively.
2. Replace the numbered cards (`card_01` … `card_09`) with named cards. Eight named Greek unit cards already exist in `data/cards/greek/` (I placed them there; `CardDB` does not see them yet because its scan is flat).
3. Rename two data fields to match the design vocabulary: **faction = pantheon** (greek, norse…), **domain = cross-pantheon grouping** (olympus, sea, underworld).

Code comments: the project's mixed Slovak/English style, no diacritics.

## A. Target layout

```
data/
  cards/greek/            card_greek_<name>.tres            (8 unit cards already here + 3 spell cards moved in)
  units/greek/            greek_<name>.tres                 (all 20)
  units/greek/frames/     frames_greek_<name>.tres          (3)
  heroes/greek/           hero_zeus.tres, hero_poseidon.tres
  heroes/greek/frames/    frames_zeus.tres, frames_poseidon.tres
  spells/greek/           storm.tres, stun.tres, ensnaring_net.tres
  spells/greek/frames/    frames_storm.tres, frames_stun.tres, frames_ensnaring_net.tres
  maps/, sounds/, tilesets/, progression/                   (unchanged)
```

Moves — use `git mv` so history follows (for untracked files use a plain move):

| From | To |
|---|---|
| `data/units/greek_*.tres` (20 files) | `data/units/greek/` |
| `data/units/frames/*.tres` | `data/units/greek/frames/` |
| `data/heroes/hero_*.tres` | `data/heroes/greek/` |
| `data/heroes/frames/*.tres` | `data/heroes/greek/frames/` |
| `data/spells/*.tres` | `data/spells/greek/` |
| `data/spells/frames/*.tres` | `data/spells/greek/frames/` |
| `data/cards/card_storm.tres` | `data/cards/greek/card_greek_storm.tres` |
| `data/cards/card_stun.tres` | `data/cards/greek/card_greek_stun.tres` |
| `data/cards/card_ensnaring_net.tres` | `data/cards/greek/card_greek_ensnaring_net.tres` |

Delete: `data/cards/card_01.tres` … `card_09.tres` (nine files). Remove the now-empty `data/units/frames`, `data/heroes/frames`, `data/spells/frames` folders.

Keep every `uid="uid://…"` exactly as it is — in file headers and in every `ext_resource` line. Do not invent or add uids.

## B. Fix every `path="res://data/…"` string

After the moves, update the `path=` of each `ext_resource` that points at a moved file. Known places (verify with grep, there may be no others):

- Inside the moved `.tres` files themselves: cards → units and spells; units → unit frames; heroes → hero frames; spells → spell frames.
- `scenes/arena/ui/CardHand.tscn` (cards)
- `scenes/arena/player.tscn`, `scenes/menu/MainMenu.tscn` (`frames_zeus.tres`)
- `scenes/arena/hero_dummy.tscn` (`frames_poseidon.tres`)
- `scenes/arena/units/melee_unit.tscn` (`frames_greek_hoplite.tres`)
- `scenes/arena/units/ranged_unit.tscn` (`frames_greek_toxotes.tres`)

The eight cards already in `data/cards/greek/` point at `res://data/units/greek_<name>.tres` — those become `res://data/units/greek/greek_<name>.tres`.

## C. Card ids

The three moved spell cards change id (in their own `.tres`): `card_storm` → `card_greek_storm`, `card_stun` → `card_greek_stun`, `card_ensnaring_net` → `card_greek_ensnaring_net`. Spell data ids (`spell_storm` etc.), unit ids and hero ids do **not** change.

The deck everywhere becomes these 11 ids, in this order:

```
card_greek_hoplite, card_greek_toxotes, card_greek_peltast, card_greek_sphendonetes,
card_greek_hippeus, card_greek_phalanx, card_greek_priestess, card_greek_gastraphetes,
card_greek_storm, card_greek_stun, card_greek_ensnaring_net
```

- `scenes/arena/ui/CardHand.tscn`: replace the twelve card `ext_resource` lines and the exported `deck` array with these 11 cards. The eight unit cards have no uid — reference them by `path=` only.
- `scripts/arena/enemy_card_ai.gd`: replace the `deck_card_ids` default (lines 36–40) with the same 11 ids. Keep the surrounding comments.
- `scripts/arena/arena.gd`: the debug keys **Y** and **P** (around lines 164–169) use `card_05` in three places, one of them inside a print string — change all three to `card_greek_hoplite`.

## D. `scripts/CardDB.gd` — recursive scan

`_scan_into()` currently skips directories. Change it to recurse into subdirectories, **except** any directory named `frames` (those hold `SpriteFrames`, which have no `id` and would trigger the "failed to load resource" error). Keep the existing `.remap` suffix handling and the duplicate-id guard untouched. The four `*_PATH` constants stay as they are.

Sketch (adapt to the existing loop, do not restructure the function beyond this):

```gdscript
		if dir.current_is_dir():
			# rekurzia do podpriecinkov (napr. cards/greek/); "frames" drzi
			# SpriteFrames bez `id` — tie CardDB nenacitava
			if file_name != "frames" and not file_name.begins_with("."):
				_scan_into(dir_path + file_name + "/", target)
		else:
			...existing file branch...
```

Also update the stale header comment at the top of `CardDB.gd` to say it scans cards, units, heroes and spells recursively.

## E. Field rename: faction = pantheon, domain = grouping

Order matters — rename `faction` → `domain` first, then `era` → `faction`.

`scripts/arena/ui/card_data.gd` — final state of the Scrolls block:

```gdscript
# Panteon karty (greek, norse, ...). Karty roznych panteonov sa nemiesaju.
@export var faction: StringName = &"greek"
# Domena naprieč panteonmi (olympus/sky, sea, underworld). &"" = common pool.
# Pouzije sa pre synergy bonus boha v neskorsom kroku.
@export var domain: StringName
```

`scripts/arena/hero_data.gd` — same two fields with the same meaning (`faction` default `&"greek"`, `domain` no default); update the `synergy_bonuses` comment so it says the bonus applies to units of the same **domain** as the god.

`.tres` values:

- `data/heroes/greek/hero_zeus.tres`: `faction = &"olympus"` → `domain = &"olympus"`
- `data/heroes/greek/hero_poseidon.tres`: `faction = &"sea"` → `domain = &"sea"`
- Remove any explicit `era = …` line from any `.tres` (the new `faction` default covers it).
- No card sets `domain` yet.

`rarity`, `obtain_source`, `synergy_bonuses` and `LevelCurve` are unchanged.

## DO NOT TOUCH

- `scripts/BattleManager.gd`, `scripts/EnergySystem.gd`, `scripts/MapDB.gd`, `scripts/AudioManager.gd`, `scripts/MatchConfig.gd` (its `local_faction` / `opponent_faction` display strings stay).
- `scripts/arena/unit.gd`, `player.gd`, `hero_dummy.gd`, `unit_data.gd`, `spell_data.gd`, `scripts/arena/ui/card_hand.gd`, `scripts/arena/ui/card.gd`, `scripts/level_curve.gd`.
- `data/maps/`, `data/sounds/`, `data/tilesets/`, `data/progression/`.
- Stats, costs, regions or any other value inside the moved `.tres` files — only `path=` strings, the three spell-card ids and the renamed fields change.
- Anything under `assets/`, `project.godot`, `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.
- Scenes other than the six listed in section B.

## OUT OF SCOPE

- Shrinking the deck to 7 cards, `PlayerProfile`, starter grant, sharing one deck source between hand and AI.
- Folders by rarity or by domain; a `norse` folder; moving maps, sounds or assets.
- Any use of `faction`, `domain`, `synergy_bonuses` or levels in gameplay.
- Validation of the new folders or fields.
- Rebalancing or re-tagging cards.

## VERIFY

Static checks (run and report output):

1. `grep -rn "res://data/units/greek_\|res://data/units/frames\|res://data/heroes/hero_\|res://data/heroes/frames\|res://data/spells/frames\|res://data/cards/card_" --include=*.tres --include=*.tscn --include=*.gd .` — no match.
2. `grep -rn "card_0[0-9]\|&\"card_storm\"\|&\"card_stun\"\|&\"card_ensnaring_net\"" --include=*.gd --include=*.tscn --include=*.tres .` — no match.
3. `ls data/cards/greek | wc -l` → 11; `ls data/units/greek/*.tres | wc -l` → 20; `ls data/cards/*.tres` → none.
4. `grep -rhn "^id = " data/cards/greek` — 11 distinct ids, all starting `card_greek_`.
5. `grep -rn "era" scripts/arena/ui/card_data.gd scripts/arena/hero_data.gd data/` — no `era` field or assignment left.
6. `grep -rn "domain = " data/heroes/greek` — exactly two lines (olympus, sea).
7. Every `path="res://data/…"` in `.tres` / `.tscn` points at a file that exists (list any that do not).
8. `git status --short` — only moves, the nine deletions and the files named above.

Runtime checks (I run these in the Godot editor — list them for me, do not claim them as done):

1. Project opens with no missing-dependency dialog and no `CardDB` `push_error`.
2. F5: the hand shows named cards; each of the eight unit cards deploys the right unit (new ones use hoplite/toxotes placeholder sprites; Priestess uses the Hoplite scroll art as a placeholder), and the three spells cast.
3. The enemy AI plays cards.
4. Debug keys **Y** and **P** print the Hoplite card cost / spend result without errors.
5. Main menu Zeus animation and both heroes' sprites still show.
