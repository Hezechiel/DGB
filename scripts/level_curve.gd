extends Resource
class_name LevelCurve

# LevelCurve — vsetky ladiace cisla progresie kariet na jednom mieste.
# Cista matematika, ziadne nody/sceny — server-portable, rovnaky kontrakt
# ako EnergySystem. Vsetky hodnoty su PLACEHOLDER a ladia sa v .tres.

@export var max_level: int = 10

# Kopie potrebne na prechod z levelu N na N+1. Index 0 = level 1 -> 2.
# Dlzka kazdeho pola musi byt max_level - 1.
@export var copies_common: PackedInt32Array
@export var copies_rare: PackedInt32Array
@export var copies_epic: PackedInt32Array
@export var copies_legendary: PackedInt32Array
@export var copies_unique: PackedInt32Array

# Kumulativny nasobic statov podla levelu. Index 0 = level 1 (1.0).
# Dlzka = max_level. Jednotky: HP + damage. Spelly: len damage. Bohovia:
# HP + damage. CC trvanie sa NIKDY neskaluje.
@export var stat_multiplier: PackedFloat32Array
# Bohovia navyse: nasobic rychlosti utoku podla levelu (mensi strop, lebo
# sa nasobi s damage). Index 0 = level 1 (1.0). Dlzka = max_level.
@export var hero_attack_speed_multiplier: PackedFloat32Array

func copies_to_next(rarity: int, level: int) -> int:
	# Vrati -1 ak je karta na max leveli alebo je vstup mimo rozsah.
	var table := _copies_table(rarity)
	var idx := level - 1
	if level >= max_level or idx < 0 or idx >= table.size():
		return -1
	return table[idx]

func get_stat_multiplier(level: int) -> float:
	return _lookup(stat_multiplier, level)

func get_hero_attack_speed_multiplier(level: int) -> float:
	return _lookup(hero_attack_speed_multiplier, level)

func _copies_table(rarity: int) -> PackedInt32Array:
	match rarity:
		1: return copies_rare
		2: return copies_epic
		3: return copies_legendary
		4: return copies_unique
		_: return copies_common

func _lookup(table: PackedFloat32Array, level: int) -> float:
	# Clamp namiesto chyby — neznamy/poskodeny level nikdy nezhodi zapas.
	if table.is_empty():
		return 1.0
	return table[clampi(level - 1, 0, table.size() - 1)]
