class_name DashMeter
extends RefCounted

# Dash meter — CISTY stav + matematika (ziadne nody, autoloady ani signaly),
# rovnaky "pure logic" princip ako energy/healing autoloady: buduci server ho spusti bez zmeny.
#
# Segment model: jedna spojita hodnota `value` v [0, max_charges]. Kazdy
# naboj = jeden segment; segmenty sa plnia JEDEN PO DRUHOM rychlostou
# 1.0 / recharge_time za sekundu. Napr. Hermes 3 charges = 3 segmenty, kazdy
# 2.5 s — dalsi sa zacne plnit az ked je predchadzajuci plny. Viac nabojov
# NEZNAMENA rychlejsie dopnanie (3 prazdne segmenty = 7.5 s).
#
# Jeden dash spotrebuje min(value, 1.0) — ciastocne naplneny segment da kratsi
# dash (distance = FULL_DISTANCE * amount), rychlost je vzdy SPEED, takze
# ciastocny dash je kratsi, nikdy pomalsi. Pod MIN_FILL je dash odmietnuty.

const FULL_DISTANCE := 48.0
const SPEED := 320.0
const MIN_FILL := 0.25

var max_charges: int
var recharge_time: float
var value: float

func _init(charges: int = 1, recharge: float = 2.5) -> void:
	max_charges = maxi(charges, 1)
	recharge_time = maxf(recharge, 0.05)
	value = float(max_charges)

func tick(delta: float) -> void:
	value = minf(value + delta / recharge_time, float(max_charges))

func can_dash() -> bool:
	return value >= MIN_FILL

# Vrati spotrebovane mnozstvo (0.0 = odmietnute, value sa nemeni).
func consume() -> float:
	if not can_dash():
		return 0.0
	var amount := minf(value, 1.0)
	value -= amount
	return amount

func refill() -> void:
	value = float(max_charges)
