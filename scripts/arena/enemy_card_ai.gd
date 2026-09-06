extends Node
class_name EnemyCardAI

# Card-play AI pre enemy hrdinu — minimalna politika: v ramci decision ticku sa
# zahra KAZDY slot v ruke ktory je zaroven dostupny AJ ma platnu (jitterovanu)
# deploy poziciu. Ziadne taktiky, ziadny scoring — to je buduca Utility AI vec.
#
# ZAMERNE SAMOSTATNY SKRIPT, nie refaktor card_hand.gd: ten je Panel s drag/
# touch vstupom a vizualnymi Card nodmi a ma "player" zadratovany na 5
# miestach. Zrkadlime mechaniku, nezdielame kod — rovnaky tradeoff ako
# status efekty duplikovane v unit.gd/player.gd/hero_dummy.gd
# (architecture.md §6).
#
# TENTO NODE NEDRZI ZIADNY PER-MATCH AUTOLOAD STAV — vytvara ho arena.gd v
# _ready() a zanikne spolu s arenou, takze sa NETYKA reset_match_state()
# pastce z architecture.md §6.
#
# RNG v rozhodovani (shuffle balicka, jitter deploy pozicie) je OK aj pre
# buduci multiplayer: tento node je autoritativny decision-maker (ako
# CpuOpponent), produkuje spravu {card_id, pos, team} — downstream
# spawn_unit/cast_spell su uz deterministicke. Jitter je ekvivalent
# lubovolneho tapu hraca na mapu.

const TEAM := "enemy"

# Human-ish pacing placeholder — rovnaky "cisla su placeholder" status ako
# ceny kariet inde v projekte. @export aby sa dal ladit bez zasahu do skriptu
# (dnes sa node vytvara cez EnemyCardAI.new() v arena.gd, takze sa pouzije
# default; @export je priprava na buducu .tscn / per-match config).
@export var decision_interval: float = 1.75

# Zrkadli exportovany `deck` array z CardHand.tscn.
# POZOR: medzi tymto zoznamom a CardHand.tscn NEEXISTUJE zdielany zdroj
# pravdy — rovnaky duplication-by-design tradeoff ako status efekty
# (architecture.md §6). Ked sa zmeni balicek hraca, uprav aj tento zoznam.
@export var deck_card_ids: Array[StringName] = [
	&"card_01", &"card_02", &"card_03", &"card_04", &"card_05", &"card_06",
	&"card_storm", &"card_stun", &"card_ensnaring_net",
]

# Rozptyl deploy pozicie (world units, polovica sirky pasu do kazdej osi).
# Unit karty: okolo enemy hrdinu. Spell karty: okolo najblizsej hracovej
# struktury. Placeholder cisla — rovnaky status ako DECISION_INTERVAL.
const UNIT_JITTER := Vector2(60.0, 120.0)
const SPELL_JITTER := Vector2(40.0, 40.0)

var _cycle: Array[CardData] = []   # fronta — zahrana karta ide na koniec
# 3 aktivne sloty, rovnako ako CardHand. ZIADNY next-card preview slot —
# ten je v CardHand cisto UI zalezitost, neovplyvnuje ani spravodlivost
# cyklu ani energiu. Vedoma simplifikacia, nie odchylka od mechaniky.
var _hand: Array[CardData] = []
var _decision_timer: float = 0.0

func _ready() -> void:
	var deck: Array[CardData] = []
	for id in deck_card_ids:
		var card := CardDB.get_card(id)
		if card == null:
			# CardDB.get_card uz push_error-uje samo; nepokracuj s null kartou
			continue
		deck.append(card)

	_cycle = deck.duplicate()
	randomize()
	_cycle.shuffle()

	for i in 3:
		_hand.append(_cycle.pop_front())

func _process(delta: float) -> void:
	if not EnergySystem.is_running():
		return
	_decision_timer -= delta
	if _decision_timer > 0.0:
		return
	_decision_timer = decision_interval
	_try_play_cards()

# Prejde vsetky 3 sloty a zahra KAZDY ktory je zaroven dostupny AJ ma platnu
# poziciu. Doplnena karta caka do dalsieho ticku — jeden prechod je prirodzeny
# strop (ziadne riziko nekonecnej slucky pri karte s cenou 0).
func _try_play_cards() -> void:
	for i in _hand.size():
		var card: CardData = _hand[i]
		if card == null:
			continue
		if not EnergySystem.can_afford(TEAM, card.id):
			continue
		var pos = _resolve_play_position(card)
		if pos == null:
			continue
		if not BattleManager.is_card_target_valid(card, pos, TEAM):
			continue

		# Atomicky check+spend — rovnaky belt-and-suspenders pattern ako
		# card_hand.gd::play_card(). can_afford vyssie ho NENAHRADZA.
		if not EnergySystem.try_spend(TEAM, card.id):
			continue

		# payload polia su navzajom vylucne (CardDB guard)
		if card.unit_data != null:
			BattleManager.spawn_unit(card.id, pos, TEAM)
		elif card.spell_data != null:
			BattleManager.cast_spell(card.id, pos, TEAM)

		_cycle.push_back(card)
		_hand[i] = _cycle.pop_front()

	# Ziadny return v slucke — kazdy dostupny slot s platnou poziciou sa zahra
	# v tomto ticku. Nepokryty slot caka na dalsi tick (ocakavane pri nizkej
	# energii, nie chyba).

# Vrati Vector2 alebo null ("tento tick nemam kam"). Volajuci slot preskoci.
func _resolve_play_position(card):
	if card.unit_data != null:
		# okolo enemy hrdinu, drzane na vlastnej polovici — "bezpecny default"
		# minimalnej politiky, len rozptyleny
		return _jittered_deploy_pos(_enemy_hero_pos(), UNIT_JITTER, true)
	if card.spell_data != null:
		var target := BattleManager.get_nearest_structure("player", _enemy_hero_pos())
		if target == null:
			return null   # nic zive — radsej necast nez castit do prazdna
		return _jittered_deploy_pos(target.global_position, SPELL_JITTER, false)
	return null

# Nahodny offset okolo base, orezany do DEPLOY_BOUNDS (s rezervou aby
# Rect2.has_point na hornej hrane nezlyhal). enemy_half_only=true drzi x > 0
# pre unit karty; spell karty smu aj na hracovu polovicu (mieria na jej
# struktury). is_card_target_valid je aj tak posledny gate — toto len zvysuje
# sancu ze pozicia prejde.
func _jittered_deploy_pos(base: Vector2, jitter: Vector2, enemy_half_only: bool) -> Vector2:
	var b: Rect2 = BattleManager.DEPLOY_BOUNDS
	var p := base + Vector2(
		randf_range(-jitter.x, jitter.x),
		randf_range(-jitter.y, jitter.y))
	var min_x: float = 20.0 if enemy_half_only else b.position.x + 10.0
	p.x = clampf(p.x, min_x, b.end.x - 10.0)
	p.y = clampf(p.y, b.position.y + 10.0, b.end.y - 10.0)
	return p

func _enemy_hero_pos() -> Vector2:
	var hero = BattleManager.heroes.get(TEAM)
	if hero != null and is_instance_valid(hero):
		return hero.global_position
	return Vector2.ZERO
