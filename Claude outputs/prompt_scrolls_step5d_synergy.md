# Claude Code prompt — Scrolls step 5d: synergy rework (deck threshold → pantheon bonus)

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 5c is merged (`scripts/deck_rules.gd` with `DeckRules.card_tags()` exists). If not, stop and tell me.

## Goal

Replace the synergy built in step 3 (a unit gets the bonus when its `domain` equals the god's, always on) with the new model:

- **Condition — one threshold per god, no tiers:** the 7-card deck contains at least `synergy_count` cards that carry the god's `synergy_tag` **and** belong to the god's pantheon. Units **and spells** count. A card's tags are `DeckRules.card_tags()` (its `tags` + faction + domain).
- **Beneficiaries:** cards of the god's own pantheon (`card.faction == hero.faction`). A foreign-pantheon card neither counts toward the threshold nor receives the bonus.
- **Effect — per god, from `synergy_bonuses`:** unit stats, spell damage, energy regeneration.

The condition depends only on the deck, so it is decided **once at match start** and never changes during the match. Spawn messages stay `{card_id, position, team}`. Code comments: the project's mixed Slovak/English style, no diacritics.

Example the data must express: *Zeus — four Olympus cards → all Greek units get +10 % HP and +10 % damage.*

## 1. `scripts/arena/hero_data.gd`

Add above `synergy_bonuses`, and replace the stale comment block on `synergy_bonuses` (the four lines starting `# Synergy bonus pre jednotky ROVNAKEJ domain ako boh.`):

```gdscript
# --- Synergy: PODMIENKA (zlozenie balicka) -> BONUS pre vlastny panteon ---
# Podmienka: balicek obsahuje aspon synergy_count kariet so znackou
# synergy_tag, ktore su zaroven z panteonu boha. Rataju sa jednotky AJ
# spelly. Jeden prah na boha, ziadne stupne. Prazdny tag alebo count <= 0
# = boh nema synergy.
@export var synergy_tag: StringName
@export var synergy_count: int = 4
# Bonus pre karty z panteonu boha, ked je podmienka splnena. Kluc = efekt,
# hodnota = nasobic (1.1 = +10 %). Povolene kluce:
#   &"max_hp", &"damage", &"speed", &"attack_speed"  -> jednotky
#   &"spell_damage"                                  -> spelly
#   &"energy_regen"                                  -> regeneracia energie timu
# Chybajuci kluc = 1.0. Karty cudzieho panteonu bonus NEDOSTANU.
@export var synergy_bonuses: Dictionary = {}
```

`synergy_bonuses` keeps its name and type — do not rename it.

## 2. `data/heroes/greek/hero_zeus.tres` and `hero_poseidon.tres`

Add one line to each `[resource]` block (the existing `synergy_bonuses` stay as they are; `synergy_count = 4` is the default, do not write it):

- `hero_zeus.tres`: `synergy_tag = &"olympus"`
- `hero_poseidon.tres`: `synergy_tag = &"sea"`

## 3. `scripts/deck_rules.gd` — pure synergy helpers

Append (keep everything already in the file):

```gdscript
# --- Synergy ---

# Kolko kariet v balicku nesie tag A je z panteonu boha. Karty cudzieho
# panteonu sa NErataju — miesanie panteonov tak stoji synergy.
static func count_synergy_cards(hero: HeroData, cards: Array[CardData]) -> int:
	if hero.synergy_tag == &"":
		return 0
	var count := 0
	for card in cards:
		if card.faction == hero.faction and card_tags(card).has(hero.synergy_tag):
			count += 1
	return count

static func is_synergy_active(hero: HeroData, cards: Array[CardData]) -> bool:
	if hero.synergy_tag == &"" or hero.synergy_count <= 0:
		return false
	return count_synergy_cards(hero, cards) >= hero.synergy_count

# Dostane tato karta bonus? (len vlastny panteon boha)
static func is_synergy_beneficiary(hero: HeroData, card: CardData) -> bool:
	return card.faction == hero.faction
```

Update the header comment of the file to mention the synergy helpers.

## 4. `scripts/BattleManager.gd` — evaluate once, apply at the entry points

**`set_team_manifest()` (lines 76–81):** the signature does not change. The deck is the key set of `card_levels` (the pre-match flow fills exactly the 7 deck cards). After building the manifest entry, evaluate synergy once and store it:

```gdscript
	# Synergy sa vyhodnoti RAZ tu — zavisi len od zlozenia balicka, pocas
	# zapasu sa nemeni. Balicek = kluce card_levels (7 kariet z manifestu).
	var hero_data: HeroData = CardDB.get_hero(hero_id) if CardDB.has_hero(hero_id) else null
	var deck_cards: Array[CardData] = []
	for card_id in card_levels.keys():
		if CardDB.has_card(card_id):
			deck_cards.append(CardDB.get_card(card_id))
	var have := 0
	var active := false
	if hero_data != null:
		have = DeckRules.count_synergy_cards(hero_data, deck_cards)
		active = DeckRules.is_synergy_active(hero_data, deck_cards)
	_manifests[team]["synergy_have"] = have
	_manifests[team]["synergy_active"] = active
	print("[synergy] team=%s hero=%s tag=%s %d/%d active=%s" % [team, hero_id,
		hero_data.synergy_tag if hero_data != null else &"",
		have, hero_data.synergy_count if hero_data != null else 0, active])
```

Update the manifest comment (lines 70–73) to list the two new keys.

**New read helpers** next to `get_hero_level()`:

```gdscript
func is_synergy_active(team: String) -> bool:
	return _manifests.has(team) and _manifests[team].get("synergy_active", false)

# Pre HUD (dalsi krok): {"tag", "have", "need", "active", "bonuses"}.
# Prazdny dictionary = tim nema manifest alebo boh nema synergy.
func get_synergy_status(team: String) -> Dictionary:
	if not _manifests.has(team):
		return {}
	var hero_id: StringName = _manifests[team]["hero_id"]
	if not CardDB.has_hero(hero_id):
		return {}
	var hero_data := CardDB.get_hero(hero_id)
	if hero_data.synergy_tag == &"" or hero_data.synergy_count <= 0:
		return {}
	return {
		"tag": hero_data.synergy_tag,
		"have": _manifests[team].get("synergy_have", 0),
		"need": hero_data.synergy_count,
		"active": is_synergy_active(team),
		"bonuses": hero_data.synergy_bonuses.duplicate(),
	}

# Nasobic jedneho synergy efektu pre danu kartu. 1.0 ked synergy nie je
# aktivna, karta nie je z panteonu boha, alebo boh ten efekt nema.
func _synergy_mult(team: String, card: CardData, key: StringName) -> float:
	if not is_synergy_active(team):
		return 1.0
	var hero_data := CardDB.get_hero(_manifests[team]["hero_id"])
	if not DeckRules.is_synergy_beneficiary(hero_data, card):
		return 1.0
	return float(hero_data.synergy_bonuses.get(key, 1.0))

# Regeneracia energie timu zo synergy (nezavisi od konkretnej karty).
func get_synergy_energy_regen(team: String) -> float:
	if not is_synergy_active(team):
		return 1.0
	return float(CardDB.get_hero(_manifests[team]["hero_id"]).synergy_bonuses.get(&"energy_regen", 1.0))
```

**`_unit_stat_mods()` (lines 94–110):** replace the whole domain-matching part (lines 100–109) so the function becomes level × synergy via `_synergy_mult`:

```gdscript
func _unit_stat_mods(card: CardData, team: String) -> Dictionary:
	var level_mult := LEVEL_CURVE.get_stat_multiplier(get_card_level(team, card.id))
	var mods := {&"max_hp": level_mult, &"damage": level_mult, &"speed": 1.0, &"attack_speed": 1.0}
	for stat in mods.keys():
		mods[stat] *= _synergy_mult(team, card, stat)
	return mods
```

Rewrite its comment (lines 94–96) to describe the new rule.

**`cast_spell()` (line 493):** the damage multiplier passed to `zone.configure(...)` becomes `LEVEL_CURVE.get_stat_multiplier(get_card_level(team, card_id)) * _synergy_mult(team, card, &"spell_damage")`.

`spawn_hero()` and `_hero_stat_mods()` are unchanged — synergy never buffs the god.

## 5. `scripts/arena/arena.gd` — energy regeneration bonus

Directly after the two `BattleManager.set_team_manifest(...)` calls (lines 73–76):

```gdscript
	# Synergy efekt na energiu — nekonecny modifikator na cely zapas.
	# EnergySystem.reset_match_state() v _enter_tree() ho pri dalsom zapase zmaze.
	for team in ["player", "enemy"]:
		var regen := BattleManager.get_synergy_energy_regen(team)
		if not is_equal_approx(regen, 1.0):
			EnergySystem.add_modifier(team, EnergySystem.ModType.REGEN_MULT, regen,
				EnergySystem.INFINITE_DURATION, &"synergy")
```

Nothing else in `arena.gd` changes.

## 6. `scripts/arena/ui/card_data.gd`

Only the stale comment on `domain` (`# Pouzije sa pre synergy bonus boha v neskorsom kroku.`): say that domain counts as a tag for deck rules and synergy thresholds.

## DO NOT TOUCH

- `scripts/EnergySystem.gd` (use only the existing `add_modifier`, `ModType.REGEN_MULT`, `INFINITE_DURATION`).
- `scripts/arena/unit.gd`, `player.gd`, `hero_dummy.gd`, `spell_zone.gd` — they already accept the multipliers; no change.
- `scripts/PlayerProfile.gd`, `scripts/MatchConfig.gd`, `scripts/ui/prematch_flow.gd`, `scripts/CardDB.gd`, `scripts/level_curve.gd`.
- Existing functions in `deck_rules.gd` (`card_tags`, `is_card_allowed`, `find_forbidden`, `build_default_deck`).
- All UI scripts and every `.tscn` (the HUD icon and any synergy display are the next step).
- `data/cards/`, `data/units/`, `data/spells/` — no `domain` or `tags` are assigned to cards in this step.
- `assets/`, `project.godot`, `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- The HUD synergy icon, tooltip, deck-editor counter, flashcard text.
- Tiers, multiple rules per god, in-match conditions (units on the field, kills, timers), the god passive-ability system.
- Region / "continental" affinity between pantheons.
- New effect kinds beyond the six keys; validation of unknown keys.
- Giving the AI its own deck or god selection.
- Tagging real cards with domains; creating Olympus cards.
- Removing the `[synergy]` / `[spawn]` debug prints.

## VERIFY

Static checks (run and report output):

1. `grep -n "hero_data.domain != card.domain\|card.domain == &\"\"" scripts/BattleManager.gd` — no match (old rule gone).
2. `grep -n "synergy_bonuses" -r scripts/ --include=*.gd` — `hero_data.gd` (declaration) and `BattleManager.gd` only.
3. `grep -n "get_node\|\$\|get_tree\|CardDB\|PlayerProfile\|BattleManager" scripts/deck_rules.gd` — no match (still pure).
4. `grep -n "synergy_tag" data/heroes/greek/*.tres` — two lines: `olympus` (Zeus), `sea` (Poseidon).
5. `grep -n "&\"synergy\"" -r scripts/ --include=*.gd` — one hit, the `add_modifier` call in `arena.gd`.
6. `git diff scripts/arena/unit.gd scripts/arena/player.gd scripts/arena/hero_dummy.gd scripts/arena/spell_zone.gd scripts/EnergySystem.gd scripts/PlayerProfile.gd` — empty.
7. `grep -rn "domain = \|tags = " data/cards/` — no match.
8. `git status --short` — only `hero_data.gd`, the two hero `.tres`, `deck_rules.gd`, `BattleManager.gd`, `arena.gd`, `card_data.gd`.

Runtime checks (I run these in the Godot editor — list them for me, do not claim them as done):

1. Untouched data: start a match. Console shows `[synergy] team=player hero=hero_zeus tag=olympus 0/4 active=false` and the enemy line with `tag=sea 0/4 active=false`. Every `[spawn]` line shows the same mods as before this step.
2. Threshold met: in the Inspector temporarily set `domain = olympus` on four cards of the active deck (e.g. Hoplite, Toxotes, Peltast, Hippeus). Start a match with Zeus: `4/4 active=true`. **Every** Greek unit you deploy — including Gastraphetes, which has no Olympus tag — shows `max_hp` and `damage` × 1.1. The enemy (Poseidon, tag `sea`) stays `active=false` and its units are unbuffed.
3. One short: remove `domain` from one of the four → `3/4 active=false`, no unit is buffed.
4. Spells count: with three Olympus units, set `domain = olympus` on `card_greek_storm.tres` too and put Storm in the deck → `4/4 active=true`.
5. Spell effect: temporarily add `&"spell_damage": 1.5` to Zeus's `synergy_bonuses` (threshold met) → Storm ticks deal 23 instead of 15; Stun's duration is unchanged.
6. Energy effect: temporarily add `&"energy_regen": 2.0` to Zeus → in the match press **Y**: regen prints `0.50/s`. Start another match with the bonus removed: back to `0.25/s`.
7. Foreign pantheon: temporarily set `faction = norse` on one of the four Olympus-tagged cards → `3/4 active=false`. Restore the threshold with another Greek card, keep the Norse one in the deck → Greek units are buffed, the Norse card's unit is not.
8. Revert every temporary `.tres` change (`git status` clean for `data/`).
