extends RefCounted
class_name PackRoller

# PackRoller — cista matematika, ziadne nody ani autoloady. Pool prichadza
# ako argument (rarity kod -> zoradene pole id-ciek), RNG tiez — server
# neskor zavola presne toto. Duplikaty v jednom balicku su povolene.

const RARITY_COUNT := 5

static func roll(pack: PackData, rng: RandomNumberGenerator, pool: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for i in pack.card_count:
		# garancia sedi na POSLEDNOM slote (vyvrcholenie reveal-u)
		var min_rarity := 0
		if i == pack.card_count - 1:
			min_rarity = maxi(0, pack.guaranteed_min_rarity)
		var rarity := _pick_rarity(pack.rarity_weights, min_rarity, rng)
		var ids := _resolve_pool(pool, rarity, pack.rarity_weights)
		if ids.is_empty():
			continue
		result.append(ids[rng.randi_range(0, ids.size() - 1)])
	return result

# Vazeny vyber rarity >= min_rarity. Ak su vsetky take vahy 0, vrati min_rarity
# (o realnom obsahu aj tak rozhodne _resolve_pool).
static func _pick_rarity(weights: PackedFloat32Array, min_rarity: int, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for r in range(min_rarity, RARITY_COUNT):
		total += _weight(weights, r)
	if total <= 0.0:
		return min_rarity
	var roll_value := rng.randf() * total
	for r in range(min_rarity, RARITY_COUNT):
		roll_value -= _weight(weights, r)
		if roll_value <= 0.0:
			return r
	return RARITY_COUNT - 1

# Ak vylosovana rarita nema ziadny obsah, padne na najblizsiu NIZSIU, potom
# na najblizsiu VYSSIU. Rarita s vahou 0 sa NIKDY nepouzije ako nahrada —
# balicek s UNIQUE = 0 tak nikdy nevyda boha, ani ked su ostatne pooly prazdne.
static func _resolve_pool(pool: Dictionary, rarity: int, weights: PackedFloat32Array) -> Array:
	if _usable(pool, rarity, weights):
		return pool[rarity]
	for r in range(rarity - 1, -1, -1):
		if _usable(pool, r, weights):
			return pool[r]
	for r in range(rarity + 1, RARITY_COUNT):
		if _usable(pool, r, weights):
			return pool[r]
	return []

static func _usable(pool: Dictionary, rarity: int, weights: PackedFloat32Array) -> bool:
	return _weight(weights, rarity) > 0.0 and pool.has(rarity) and not pool[rarity].is_empty()

static func _weight(weights: PackedFloat32Array, rarity: int) -> float:
	return weights[rarity] if rarity >= 0 and rarity < weights.size() else 0.0
