extends Node

# Projektovy register jednotiek/struktur podla timu — jediny zdroj pravdy
# o tom, kto patri ktoremu timu (single source of team membership).
# Sluzi systemom: win/lose podmienky, allied minion AI, minimapa...

# Emitovany ked zakladna jedneho timu je znicena — arena.gd pocuva a zmeni scenu
signal match_ended(winner_team: String)

# Respawn — MatchInfoBar pocuva tieto signaly a zobrazuje countdown
signal hero_died(team: String, respawn_seconds: int)
signal hero_respawn_tick(team: String, seconds_left: int)
signal hero_respawned(team: String)

# Match timer — MatchInfoBar pocuva a zobrazuje odpocet
signal match_time_tick(seconds_left: int)

const MATCH_DURATION := 180.0
var _match_time_left: float = 0.0
var _match_running: bool = false
var _match_ended: bool = false   # zdielany guard pre match_ended (timer aj base destroy)

# Jednotky podla timu (hrdinovia + sumonovane jednotky)
var team_player: Array[Node2D] = []
var team_enemy: Array[Node2D] = []

var heroes: Dictionary = {}                # team -> hero Node, nastavuje sa v spawn_hero
var hero_spawn_positions: Dictionary = {}  # team -> Vector2, nastavuje arena.gd
var _hero_deaths: Dictionary = {}          # team -> int, pretrvava cely zapas
var _respawn_left: Dictionary = {}         # team -> float, len pocas respawnu

# Zakladne
var player_base: Node2D = null
var enemy_base: Node2D = null

# Healing pody — registrovane z healing_pod._ready() (rovnaky self-register
# pattern ako turrety/zakladne). Untyped Array ako candidates v
# get_nearest_structure() — pristup k pod.owning_side je dynamicky.
var _healing_pods: Array = []

# Veze podla timu a pruhu — na vyhodnotenie ked je pruh vycisteny
# Struktura: { "player": { "top": [...], "bot": [...] }, "enemy": { ... } }
var _turrets: Dictionary = {
	"player": {"top": [], "bot": []},
	"enemy":  {"top": [], "bot": []}
}

# Ulozit vysledok zapasu pre MatchEndScreen
var last_winner: String = ""

# Arena root nastavuje arena.gd vo svojom _ready() — BattleManager je autoload
# bez vlastnej scenografie, takze potrebuje referenciu kam pridat spawnute uzly.
var arena_root: Node = null

# --- Registracia jednotiek ---

func register(unit: Node2D, team: String) -> void:
	var list := team_player if team == "player" else team_enemy
	if not list.has(unit):
		list.append(unit)
		unit.tree_exited.connect(func(): unregister(unit, team), CONNECT_ONE_SHOT)

func unregister(unit: Node2D, team: String) -> void:
	# Array.erase() na hodnotu ktora uz v poli nie je (napr. neskoro-vystrelena
	# tree_exited lambda z predchadzajucej, uz resetnutej areny) je bezpecny
	# no-op — nikdy nesposobi chybu.
	var list := team_player if team == "player" else team_enemy
	list.erase(unit)

func is_team_alive(team: String) -> bool:
	var list := team_player if team == "player" else team_enemy
	return list.size() > 0

# --- Registracia vez ---

func register_turret(turret: Node2D, team: String, lane: String) -> void:
	if _turrets.has(team) and _turrets[team].has(lane):
		_turrets[team][lane].append(turret)

# Volane z turret._on_destroyed()
func on_turret_destroyed(turret_team: String, lane: String) -> void:
	# Ak je pruh timu vycisteny, ich vlastna zakladna sa stane zranitelnou
	if _is_lane_cleared(turret_team, lane):
		_set_base_vulnerable(turret_team)

func _is_lane_cleared(team: String, lane: String) -> bool:
	# Pruh je vycisteny ak nemaju ziadnu zivu vezu v nom
	var lane_turrets: Array = _turrets[team][lane]
	for t in lane_turrets:
		if is_instance_valid(t) and t.hp > 0:
			return false
	return true

func _set_base_vulnerable(team: String) -> void:
	var base := player_base if team == "player" else enemy_base
	if base and is_instance_valid(base):
		base.set_vulnerable()

# --- Registracia zakladni ---

func register_base(base: Node2D, team: String) -> void:
	if team == "player":
		player_base = base
	else:
		enemy_base = base

# Volane z base._on_destroyed()
func on_base_destroyed(destroyed_team: String) -> void:
	if _match_ended:
		return
	_match_ended = true
	_match_running = false
	last_winner = "enemy" if destroyed_team == "player" else "player"
	match_ended.emit(last_winner)

# --- Registracia healing podov ---

func register_healing_pod(pod: Node2D) -> void:
	if not _healing_pods.has(pod):
		_healing_pods.append(pod)
		# single_use pody sa queue_free-uju (na rozdiel od vezi ktore ostavaju
		# vrakmi) — bez cleanup by pole akumulovalo freed referencie
		pod.tree_exited.connect(func(): _healing_pods.erase(pod), CONNECT_ONE_SHOT)

# Najblizsi READY pod pre AI heal-seek. Strict own-side-first: cudzia strana
# sa zvazuje len ak vlastna strana nema ziadny ready pod.
func get_nearest_ready_healing_pod(team: String, from_pos: Vector2) -> Node2D:
	var own := _nearest_ready_pod_for_side(team, from_pos)
	if own != null:
		return own
	var enemy_team := "player" if team == "enemy" else "enemy"
	return _nearest_ready_pod_for_side(enemy_team, from_pos)

func _nearest_ready_pod_for_side(side: String, from_pos: Vector2) -> Node2D:
	var nearest: Node2D = null
	var nearest_d2 := INF
	for pod in _healing_pods:
		if not is_instance_valid(pod):
			continue
		if pod.owning_side != side:
			continue
		if not HealingSystem.is_pod_ready(StringName(pod.name)):
			continue
		var d2: float = from_pos.distance_squared_to(pod.global_position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = pod
	return nearest

# --- Match timer ---

# Volane z arena.gd _ready() — NIE z BattleManager _ready(), autoload prezije
# medzi zapasmi, takze timer sa musi resetovat pri kazdom novom zapase.
func start_match_timer() -> void:
	_match_time_left = MATCH_DURATION
	_match_running = true
	_match_ended = false
	match_time_tick.emit(ceili(_match_time_left))

# --- Reset stavu zapasu ---

# Volane z arena._enter_tree() PRED _ready() detí (turrety/zakladne sa
# registruju vo svojom _ready(), ktore bezi PRED _ready() rodica) —
# zarucuje ze nova arena nezdedi ziadny stav (vratane FREED referencii)
# z predchadzajuceho zapasu.
func reset_match_state() -> void:
	team_player.clear()
	team_enemy.clear()

	heroes.clear()
	_hero_deaths.clear()
	_respawn_left.clear()
	hero_spawn_positions.clear()  # arena.gd ich znovu nastavi

	player_base = null
	enemy_base = null
	_healing_pods.clear()  # pody sa znovu registruju vo svojom _ready()

	# Turrety nemaju ziadny tree_exited/unregister mechanizmus (nikdy sa
	# nequeue_free-uju, len sa stavaju vrakmi) — cisty literal je jednoduchsi
	# a bezpecnejsi nez rucne clear() na 4 vnorenych poliach.
	_turrets = {
		"player": {"top": [], "bot": []},
		"enemy":  {"top": [], "bot": []}
	}

	last_winner = ""
	arena_root = null  # arena._enter_tree() ho hned nato nastavi znova

	_match_time_left = 0.0
	_match_running = false
	_match_ended = false

# --- March ciel pre jednotky ---

# Vrati najblizsiu zivu strukturu (veza z ktorejkolvek lany alebo baza)
# patriacu defending_team, meranu od from_pos. Ziadna lane logika ani
# priorita — cisto najblizsia ziva struktura. Null ak nic nezije
# (nemalo by nastat, znicenie bazy konci zapas, ale osetrene pre istotu).
func get_nearest_structure(defending_team: String, from_pos: Vector2) -> Node2D:
	var candidates: Array = []
	if _turrets.has(defending_team):
		candidates.append_array(_turrets[defending_team]["top"])
		candidates.append_array(_turrets[defending_team]["bot"])
	var base := player_base if defending_team == "player" else enemy_base
	if base != null:
		candidates.append(base)

	var nearest: Node2D = null
	var nearest_dist := INF
	for structure in candidates:
		if not is_instance_valid(structure) or structure.hp <= 0:
			continue
		var d: float = from_pos.distance_squared_to(structure.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = structure
	return nearest

# --- Deploy zone ---
# Hranice mapy kde sa da deployovat. TODO: neskor by mali prist z areny/mapy,
# nie z konstanty v autoloade.
const DEPLOY_BOUNDS := Rect2(-450.0, -350.0, 900.0, 700.0)

# Jediny zdroj pravdy pre "da sa sem deployovat?". Vola ho aj live preview
# (farba kruhu) aj spawn na release — nikdy nesmu rozhodnut rozdielne.
# Buduce dalsie pravidla sa pridavaju SEM, nie na volajucich:
#   - rozsirenie zony po zniceni enemy veze (lane-based)
#   - prekazky a struktury na mape
func is_deploy_position_valid(pos: Vector2, team: String) -> bool:
	if not DEPLOY_BOUNDS.has_point(pos):
		return false
	# vlastna polovica mapy — stredova ciara je x = 0
	if team == "player":
		return pos.x < 0.0
	return pos.x > 0.0

# Jediny zdroj pravdy pre "da sa sem zahrat TUTO kartu" — vetvi podla typu
# karty. Unit karty: existujuce pravidlo (vlastna polovica + bounds).
# Spell karty: kdekolvek na mape (bez ohladu na stred) — rozsirenie zony
# per lane sa ich netyka.
func is_card_target_valid(card: CardData, pos: Vector2, team: String) -> bool:
	if card.spell_data != null:
		return DEPLOY_BOUNDS.has_point(pos)
	return is_deploy_position_valid(pos, team)

# --- Spawn (jediny vstupny bod pre vytvaranie jednotiek) ---

# Jediny spawn entry point pre jednotky. Resolvne CardData → UnitData cez
# CardDB, instancuje archetype scenu, nakonfiguruje ju PRED vstupom do stromu
# (instantiate → configure → add_child). Buduci network handler a
# drag-to-deploy volaju tuto funkciu — ziadne ine miesto uz jednotky
# neinstancuje priamo. Karta moze sumonovat squad (unit_count > 1) —
# vrati vsetky spawnute jednotky.
func spawn_unit(card_id: StringName, pos: Vector2, team: String) -> Array[Node]:
	if arena_root == null:
		push_error("BattleManager.spawn_unit: arena_root nie je nastaveny")
		return []

	var card := CardDB.get_card(card_id)
	if card == null or card.unit_data == null:
		push_error("BattleManager.spawn_unit: card '%s' nema priradene unit_data" % card_id)
		return []

	var unit_data := card.unit_data
	if unit_data.archetype_scene == null:
		push_error("BattleManager.spawn_unit: unit_data '%s' nema archetype_scene" % unit_data.id)
		return []

	var spawned: Array[Node] = []
	var count: int = maxi(1, card.unit_count)
	for i in range(count):
		var unit := unit_data.archetype_scene.instantiate()
		unit.configure(unit_data, team)
		unit.global_position = pos + _formation_offset(i, count, card.formation_radius)
		arena_root.add_child.call_deferred(unit)
		spawned.append(unit)
	return spawned

# Deterministicke rozmiestnenie squadu do kruhu — ZIADNY random, oba klienti
# musia z rovnakej {card_id, pos, team} spravy dostat rovnaku formaciu.
func _formation_offset(index: int, count: int, radius: float) -> Vector2:
	if count <= 1:
		return Vector2.ZERO
	var angle := TAU * float(index) / float(count)
	return Vector2(cos(angle), sin(angle)) * radius

# Vsetky jednotky/hrdinovia PATRIACE affected_team, v danom polomere od
# pozicie. team_player/team_enemy uz obsahuju hrdinov aj jednotky (obaja
# sa registruju cez register()); veze su tiez v tychto poliach (register()
# sa vola aj z turret.gd) — takze veza chytena v Storm polomere DOSTANE
# damage (ma take_damage) a STUN na nu plati tiez (turret.gd ma vlastny
# apply_stun z repair/stun mechaniky). apply_root/apply_slow veza nema,
# takze tie na nu jednoducho neplatia (has_method guard nizsie). Vraky
# vezi ostavaju v poliach s hp<=0 — ich take_damage/apply_stun su no-op,
# ziadny filter tu netreba. Zakladne (base.gd) sa do tychto poli vobec
# neregistruju — spelly na ne teda nikdy nedosahnu, rovnaka asymetria ako
# uz existuje v hre, nie chyba tohto kroku.
#
# ZAMERNE team-scoped, NIE vsetci v okruhu — ziadny friendly fire pre
# spelly ani buduce AoE jednotky, ktore tuto funkciu budu tiez volat.
func _get_targets_in_radius(pos: Vector2, radius: float, affected_team: String) -> Array:
	var result: Array = []
	var r2 := radius * radius
	var pool := team_player if affected_team == "player" else team_enemy
	for n in pool:
		if not is_instance_valid(n):
			continue
		if pos.distance_squared_to(n.global_position) <= r2:
			result.append(n)
	return result

# Jediny cast entry point pre spell karty (rovnaky princip ako
# spawn_unit/spawn_hero). spell_type konvencia (viz spell_data.gd):
# 0 = STORM, 1 = STUN, 2 = NET. `team` je caster (kto kartu zahral) —
# efekt vzdy zasiahne LEN opacny tim, bez ohladu na to kam presne na
# mape bola karta zahrana.
func cast_spell(card_id: StringName, pos: Vector2, team: String) -> void:
	var card := CardDB.get_card(card_id)
	if card == null or card.spell_data == null:
		push_error("BattleManager.cast_spell: card '%s' nema priradene spell_data" % card_id)
		return

	var spell := card.spell_data
	var enemy_team := "player" if team == "enemy" else "enemy"
	var targets := _get_targets_in_radius(pos, spell.radius, enemy_team)

	match spell.spell_type:
		0:  # STORM — instant burst + DoT ticky + slow po cely duration
			for n in targets:
				if is_instance_valid(n) and n.has_method("take_damage"):
					n.take_damage(spell.damage)
				if is_instance_valid(n) and n.has_method("apply_slow"):
					n.apply_slow(0.5, spell.duration)  # 50% spomalenie, placeholder
			_run_storm_ticks(targets, spell)
		1:  # STUN
			for n in targets:
				if is_instance_valid(n) and n.has_method("apply_stun"):
					n.apply_stun(spell.duration)
		2:  # NET (root)
			for n in targets:
				if is_instance_valid(n) and n.has_method("apply_root"):
					n.apply_root(spell.duration)
		_:
			push_error("BattleManager.cast_spell: neznamy spell_type %d na karte '%s'" % [spell.spell_type, card_id])

# Storm DoT — snapshot cielov z casu castu (NIE persistentna zona; jednotky
# ktore vojdu do oblasti neskor sa nechytia, to je zamerne zjednodusenie
# tohto kroku). is_instance_valid() na kazdom ticku odchytava jednotky
# ktore medzitym zomreli/zmizli zo stromu.
func _run_storm_ticks(targets: Array, spell: SpellData) -> void:
	var ticks := int(spell.duration / spell.tick_interval)
	for i in range(ticks):
		await get_tree().create_timer(spell.tick_interval).timeout
		for n in targets:
			if is_instance_valid(n) and n.has_method("take_damage"):
				n.take_damage(spell.damage)

# --- Spawn (hrdinovia) ---

const PLAYER_SCENE: PackedScene = preload("res://scenes/arena/player.tscn")
const HERO_DUMMY_SCENE: PackedScene = preload("res://scenes/arena/hero_dummy.tscn")

# hero_id pride od (buduceho) remote hraca cez network; "controlled" sa
# rozhoduje vzdy lokalne (je toto moj hrdina, alebo cudzi/AI?)
func spawn_hero(hero_id: StringName, team: String, controlled: bool) -> Node:
	if arena_root == null:
		push_error("BattleManager.spawn_hero: arena_root nie je nastaveny")
		return null

	var data := CardDB.get_hero(hero_id)
	if data == null:
		push_error("BattleManager.spawn_hero: neznamy hero_id '%s'" % hero_id)
		return null

	var scene: PackedScene = PLAYER_SCENE if controlled else HERO_DUMMY_SCENE
	var hero := scene.instantiate()
	hero.configure(data, team)
	heroes[team] = hero
	arena_root.add_child.call_deferred(hero)
	return hero

# --- Respawn ---

func on_hero_died(_hero: Node2D, team: String) -> void:
	if _respawn_left.has(team):
		return  # uz respawnuje — guard proti dvojitemu volaniu
	_hero_deaths[team] = _hero_deaths.get(team, 0) + 1
	var respawn_seconds: int = clampi(3 + _hero_deaths[team] - 1, 3, 10)
	_respawn_left[team] = float(respawn_seconds)
	hero_died.emit(team, respawn_seconds)

func _process(delta: float) -> void:
	for team in _respawn_left.keys():
		var before := ceili(_respawn_left[team])
		_respawn_left[team] -= delta
		var after := ceili(_respawn_left[team])
		if after != before and after > 0:
			hero_respawn_tick.emit(team, after)
		if _respawn_left[team] <= 0.0:
			_respawn_hero(team)

	if _match_running:
		var before_t := ceili(_match_time_left)
		_match_time_left -= delta
		var after_t := ceili(_match_time_left)
		if after_t != before_t and after_t > 0:
			match_time_tick.emit(after_t)
		if _match_time_left <= 0.0:
			_match_running = false
			if not _match_ended:
				_match_ended = true
				last_winner = "draw"
				# TODO: az pride progress-based rozhodovanie (znicene veze/kille), nahradit "draw"
				match_ended.emit("draw")

# TODO: future hero ability entry point. Spawns a single-use HealingPod at
# pos for owner_team's heroes. Not wired to any hero kit yet — no ability
# calls this today. When implemented, mirror spawn_unit()'s
# instantiate → configure → add_child ordering.
func spawn_healing_pod(_pos: Vector2, _owner_team: String) -> void:
	pass

func _respawn_hero(team: String) -> void:
	# Bez typu — hero mohol byt freed pri zmene sceny (autoload prezije arenu)
	# a typed assign freed instance je error este PRED is_instance_valid checkom.
	var hero = heroes.get(team)
	if hero != null and is_instance_valid(hero):
		hero.global_position = hero_spawn_positions.get(team, hero.global_position)
		hero.revive()
	_respawn_left.erase(team)
	hero_respawned.emit(team)
