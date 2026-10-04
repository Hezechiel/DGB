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
