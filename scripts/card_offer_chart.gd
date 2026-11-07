extends Resource
class_name CardOfferChart

# CardOfferChart — ponuka kariet v Shope: kolko ponuk, ako sa losuju, ceny podla rarity.
# Index poli = rarity kod (0 COMMON, 1 RARE, 2 EPIC, 3 LEGENDARY). Bohovia (4) sa NEponukaju.
# TODO(server): chart aj losovanie neskor drzi server.

@export var offer_count: int = 5
# relativne vahy losovania rarity, dlzka 4
@export var rarity_weights: PackedFloat32Array
# &"gold" / &"crystals", dlzka 4
@export var currencies: Array[StringName]
# cena za ponuku, dlzka 4
@export var prices: PackedInt32Array
# kolko kopii ponuka da, dlzka 4
@export var copies: PackedInt32Array

func currency_for(rarity: int) -> StringName:
	var i := _index(rarity, currencies.size(), "currencies")
	return currencies[i] if i >= 0 else &"gold"

func price_for(rarity: int) -> int:
	var i := _index(rarity, prices.size(), "prices")
	return maxi(prices[i], 0) if i >= 0 else 0

func copies_for(rarity: int) -> int:
	var i := _index(rarity, copies.size(), "copies")
	return maxi(copies[i], 1) if i >= 0 else 1

# Rarita mimo pola -> warning + posledny platny index. Prazdne pole -> -1 (volajuci da default).
func _index(rarity: int, size: int, field: String) -> int:
	if size <= 0:
		push_warning("CardOfferChart: pole '%s' je prazdne — pouzivam default" % field)
		return -1
	if rarity < 0 or rarity >= size:
		push_warning("CardOfferChart: rarita %d mimo pola '%s' (dlzka %d) — pouzivam posledny index" % [rarity, field, size])
		return size - 1
	return rarity
