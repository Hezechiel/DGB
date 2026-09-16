extends Panel
class_name Minimap

# Minimapa — struktury a hrdinovia ako farebne body, plna viditelnost
# (ziadny fog of war, viz herny navrh — SWFA/Clash-Royale styl, nie
# LoL/Dota). Panel VLASTNU velkost pocita z MapData.bounds pomeru strany
# pri kazdom configure_map() — nie je to fixny rozmer v scene, takze
# buduca mapa s inym pomerom stran sa zobrazi spravne, nezoseparuje sa
# do zle-tvarovaneho panelu. Tap-to-navigate pride v dalsom kroku.

const MAX_SIZE := Vector2(170, 170)
const ICON_TURRET_SIZE := Vector2(4, 4)
const ICON_BASE_SIZE := Vector2(6, 6)
const ICON_HERO_SIZE := Vector2(6, 6)
const COLOR_PLAYER := Color(0.3, 0.55, 1, 1)   # rovnaka modra ako MatchInfoBar tower-pips
const COLOR_ENEMY := Color(1, 0.35, 0.3, 1)    # rovnaka cervena ako MatchInfoBar tower-pips
const COLOR_DESTROYED := Color(0.4, 0.4, 0.4, 0.6)

var _map_bounds: Rect2
# Zakladne nemaju vlastny "destroyed" signal (len turret.gd) — pre 2
# zakladne je pollovanie hp v _process() dost lacne na to aby nestalo
# za pridavanie signalu do base.gd len kvoli minimape.
var _poll_icons: Dictionary = {}   # icon (ColorRect) -> structure (Node2D)
var _hero_icons: Dictionary = {}   # team (String) -> icon (ColorRect)

func configure_map(map_data: MapData) -> void:
	_map_bounds = map_data.bounds
	_resize_to_match_bounds()
	_spawn_structure_icons()
	_spawn_hero_icons()

func _process(_delta: float) -> void:
	_update_poll_icons()
	_update_hero_icons()

# Panel velkost = MapData.bounds pomer stran, vpisana do MAX_SIZE boxu
# (rovnaky "fit, never stretch" princip ako AspectRatioContainer pre
# karty — tu rucne, lebo mena sa cela velkost containera, nie len jeho
# ditata).
func _resize_to_match_bounds() -> void:
	var aspect := _map_bounds.size.x / _map_bounds.size.y
	var target: Vector2
	if aspect >= 1.0:
		target = Vector2(MAX_SIZE.x, MAX_SIZE.x / aspect)
	else:
		target = Vector2(MAX_SIZE.y * aspect, MAX_SIZE.y)
	size = target

func _world_to_local(world_pos: Vector2) -> Vector2:
	var normalized := (world_pos - _map_bounds.position) / _map_bounds.size
	return normalized * size

func _spawn_structure_icons() -> void:
	for team in ["player", "enemy"]:
		var color: Color = COLOR_PLAYER if team == "player" else COLOR_ENEMY
		for turret in BattleManager.get_turrets(team):
			_add_structure_icon(turret, color, ICON_TURRET_SIZE)
		var base: Node2D = BattleManager.player_base if team == "player" else BattleManager.enemy_base
		if base != null:
			_add_structure_icon(base, color, ICON_BASE_SIZE)

func _add_structure_icon(structure: Node2D, color: Color, icon_size: Vector2) -> void:
	var icon := ColorRect.new()
	icon.color = color
	icon.size = icon_size
	icon.position = _world_to_local(structure.global_position) - icon_size / 2.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	if structure.has_signal("destroyed"):
		structure.destroyed.connect(func(): icon.color = COLOR_DESTROYED, CONNECT_ONE_SHOT)
	else:
		_poll_icons[icon] = structure

func _update_poll_icons() -> void:
	if _poll_icons.is_empty():
		return
	for icon in _poll_icons.keys():
		var structure = _poll_icons[icon]
		if not is_instance_valid(structure) or structure.hp <= 0:
			if is_instance_valid(icon):
				icon.color = COLOR_DESTROYED
			_poll_icons.erase(icon)

# Volane raz z configure_map() — v tomto bode uz arena.gd spawlo oboch
# hrdinov (volanie configure_map() sa presunulo za spawn_hero() volania,
# viz arena.gd nizsie), takze BattleManager.heroes uz nie je prazdny.
func _spawn_hero_icons() -> void:
	for team in ["player", "enemy"]:
		var hero: Node2D = BattleManager.heroes.get(team)
		if hero == null:
			continue
		var icon := ColorRect.new()
		icon.color = COLOR_PLAYER if team == "player" else COLOR_ENEMY
		icon.size = ICON_HERO_SIZE
		icon.rotation = PI / 4.0   # otoceny stvorec = lacny diamant, odlisi hrdinov od struktur
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		_hero_icons[team] = icon

func _update_hero_icons() -> void:
	for team in _hero_icons.keys():
		var hero: Node2D = BattleManager.heroes.get(team)
		var icon: ColorRect = _hero_icons[team]
		if hero == null or not is_instance_valid(hero):
			icon.visible = false
			continue
		icon.visible = not BattleManager.is_hero_dead(team)
		icon.position = _world_to_local(hero.global_position) - ICON_HERO_SIZE / 2.0
