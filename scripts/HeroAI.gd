extends Node

# AI hrdinu — POZOR, len ciste stavove rozhodovanie (hp hysteresis).
# TVRDE PRAVIDLO (rovnake ako EnergySystem/HealingSystem): ziadne sceny,
# nody, pozicie. Odpoveda len na otazku "je tento hrdina v uzkych" —
# kde su pody a kam ist vie hero_dummy.gd.

enum State { NORMAL, LOW_HP }

const LOW_HP_PCT := 0.20      # pod tuto hranicu -> LOW_HP
const RECOVER_HP_PCT := 0.50  # navrat do NORMAL az nad touto (hysteresis pas)

var _low_hp: Dictionary = {}  # team -> bool

func get_hp_state(team: String, hp_pct: float) -> State:
	var low: bool = _low_hp.get(team, false)
	if low:
		if hp_pct > RECOVER_HP_PCT:
			low = false
	elif hp_pct < LOW_HP_PCT:
		low = true
	_low_hp[team] = low
	return State.LOW_HP if low else State.NORMAL

# Volane z arena._enter_tree() — rovnaka pastca ako ostatne autoloady.
func reset_match_state() -> void:
	_low_hp.clear()
