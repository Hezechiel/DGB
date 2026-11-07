extends RefCounted
class_name OfferRoller

# OfferRoller — cista matematika, ziadne nody ani autoloady (rovnaky kontrakt
# ako PackRoller). Pool prichadza ako argument (rarity kod -> zoradene pole
# id-ciek, rovnaky format ako drop pool pre PackRoller), RNG tiez — server neskor zavola presne toto.
# Ponuka NEMA duplikaty. Bohovia (rarity 4) sa ignoruju. Rarita s vahou 0 sa
# nikdy neponukne. Malo kariet -> vrati co existuje.

const RARITY_COUNT := 4

static func roll(chart: CardOfferChart, rng: RandomNumberGenerator, pool: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	# lokalna kopia — vstupny pool sa nemeni
	var remaining: Dictionary = {}
	for r in RARITY_COUNT:
		if pool.has(r) and pool[r] is Array:
			remaining[r] = (pool[r] as Array).duplicate()
	for i in chart.offer_count:
		var rarity := _pick_rarity(chart.rarity_weights, remaining, rng)
		if rarity < 0:
			break
		var ids: Array = remaining[rarity]
		var pick := rng.randi_range(0, ids.size() - 1)
		result.append(StringName(ids[pick]))
		ids.remove_at(pick)
	return result

# Vazeny vyber spomedzi rarit, ktore este maju id-cka a vahu > 0. -1 = nic.
static func _pick_rarity(weights: PackedFloat32Array, remaining: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for r in RARITY_COUNT:
		total += _live_weight(weights, remaining, r)
	if total <= 0.0:
		return -1
	var roll_value := rng.randf() * total
	var last := -1
	for r in RARITY_COUNT:
		var w := _live_weight(weights, remaining, r)
		if w <= 0.0:
			continue
		last = r
		roll_value -= w
		if roll_value <= 0.0:
			return r
	return last

static func _live_weight(weights: PackedFloat32Array, remaining: Dictionary, rarity: int) -> float:
	if not remaining.has(rarity) or (remaining[rarity] as Array).is_empty():
		return 0.0
	return maxf(weights[rarity], 0.0) if rarity < weights.size() else 0.0
