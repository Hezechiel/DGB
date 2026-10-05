extends RefCounted
class_name DeckRules

# DeckRules — pravidla balicka: boh proti karte. Cista matematika, ziadne
# nody ani autoloady. Ziadne pravidla karta-proti-karte, ziadne obmedzenie
# panteonu (panteony sa mozu miesat). Plus synergy helpery: prah boha
# (pocet kariet so synergy_tag z jeho panteonu) a kto dostane bonus.

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

# --- Synergy: text pre UI (HUD tooltip aj Deck obrazovka) ---

const _SYNERGY_UNIT_LABELS := {
	&"max_hp": "Health", &"damage": "Damage",
	&"speed": "Move speed", &"attack_speed": "Attack speed",
}

# Napr. "4 Olympus scrolls: Greek units +10% Health, +10% Damage".
# Prazdny string = boh nema synergy.
static func describe_synergy(hero: HeroData) -> String:
	if hero.synergy_tag == &"" or hero.synergy_count <= 0:
		return ""
	var pantheon := String(hero.faction).capitalize()
	var parts: Array[String] = []
	var unit_bits: Array[String] = []
	for key in _SYNERGY_UNIT_LABELS:
		if hero.synergy_bonuses.has(key):
			unit_bits.append("%s %s" % [_percent(hero.synergy_bonuses[key]), _SYNERGY_UNIT_LABELS[key]])
	if not unit_bits.is_empty():
		parts.append("%s units %s" % [pantheon, ", ".join(unit_bits)])
	if hero.synergy_bonuses.has(&"spell_damage"):
		parts.append("%s spells %s Damage" % [pantheon, _percent(hero.synergy_bonuses[&"spell_damage"])])
	if hero.synergy_bonuses.has(&"energy_regen"):
		parts.append("Energy regeneration %s" % _percent(hero.synergy_bonuses[&"energy_regen"]))
	return "%d %s scrolls: %s" % [hero.synergy_count, String(hero.synergy_tag).capitalize(), "; ".join(parts)]

static func _percent(mult: Variant) -> String:
	var pct := roundi((float(mult) - 1.0) * 100.0)
	return ("+%d%%" % pct) if pct >= 0 else ("%d%%" % pct)
