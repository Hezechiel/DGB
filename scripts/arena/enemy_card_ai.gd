extends Node
class_name EnemyCardAI

# Card-play AI pre enemy hrdinu — minimalna politika: prva dostupna karta v
# ruke, na bezpecnu default poziciu, jedna karta za decision tick.
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

const TEAM := "enemy"

# Human-ish pacing placeholder — rovnaky "cisla su placeholder" status ako
# ceny kariet inde v projekte.
const DECISION_INTERVAL := 1.75

# Zrkadli exportovany `deck` array z CardHand.tscn PRESNE.
# POZOR: medzi tymto zoznamom a CardHand.tscn NEEXISTUJE zdielany zdroj
# pravdy — rovnaky duplication-by-design tradeoff ako status efekty
# (architecture.md §6). Ked sa zmeni balicek hraca, uprav aj tento zoznam.
const DECK_CARD_IDS: Array[StringName] = [
	&"card_01", &"card_02", &"card_03", &"card_04", &"card_05", &"card_06",
	&"card_storm", &"card_stun", &"card_ensnaring_net",
]

var _cycle: Array[CardData] = []   # fronta — zahrana karta ide na koniec
# 3 aktivne sloty, rovnako ako CardHand. ZIADNY next-card preview slot —
# ten je v CardHand cisto UI zalezitost, neovplyvnuje ani spravodlivost
# cyklu ani energiu. Vedoma simplifikacia, nie odchylka od mechaniky.
var _hand: Array[CardData] = []
var _decision_timer: float = 0.0

func _ready() -> void:
	var deck: Array[CardData] = []
	for id in DECK_CARD_IDS:
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
	_decision_timer = DECISION_INTERVAL
	_try_play_a_card()

func _try_play_a_card() -> void:
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

		# DOCASNY debug vypis na overenie pipeline — rovnaky styl ako
		# existujuce debug printy v arena.gd (KEY_O a spol.)
		print("[enemy_ai] played %s at %s" % [card.id, pos])

		# jedna karta za tick — placeholder pacing, nie tvrde pravidlo
		return

	# Ziadny slot nie je zaroven dostupny AJ s platnou poziciou — necham tick
	# prejst naprazdno. Toto je ocakavane spravanie pri nizkej energii, nie chyba.

# Vrati Vector2 alebo null ("tento tick nemam kam"). Volajuci slot preskoci.
func _resolve_play_position(card: CardData):
	if card.unit_data != null:
		# vlastny spawn point — vzdy platny (vlastna polovica, v DEPLOY_BOUNDS);
		# toto je ten "bezpecny default" minimalnej politiky
		return BattleManager.hero_spawn_positions.get(TEAM, _enemy_hero_pos())
	if card.spell_data != null:
		var target := BattleManager.get_nearest_structure("player", _enemy_hero_pos())
		if target == null:
			return null   # nic zive — radsej necast nez castit do prazdna
		return target.global_position
	return null

func _enemy_hero_pos() -> Vector2:
	var hero = BattleManager.heroes.get(TEAM)
	if hero != null and is_instance_valid(hero):
		return hero.global_position
	return Vector2.ZERO
