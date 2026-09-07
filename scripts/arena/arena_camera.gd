extends Camera2D
class_name ArenaCamera

# Hranice kamery — nastav podla mapy, zmenitelne cez Inspector pre kazdu mapu
@export var bounds_min: Vector2 = Vector2(-450, -350)
@export var bounds_max: Vector2 = Vector2(450, 350)

# Edge-pan pocas drag-to-deploy (tahanie karty z ruky). Cim blizsie prst k
# okraju obrazovky, tym rychlejsi pan — bezi bez ohladu na Settings.lock_camera.
@export var edge_margin: float = 100.0        # px (viewport space) — sirka pasma pri okraji obrazovky, kde zacina pan
@export var edge_pan_speed_max: float = 650.0 # world px/s — rychlost panu ked prst je presne na okraji

# Minimalna vzdialenost prstu pred zacatim dragu (ochrana proti nahodnym tapom)
@export var drag_threshold: float = 8.0

# Rychlost sledovania hraca v lock rezimu (0.0–1.0, nizsie = plynulejsie)
@export var follow_smoothing: float = 0.1

# Soft-follow: aj v lock rezime sa da panovat. Pocas dragu kamera nesleduje,
# po pusteni prsta pocka return_delay (hrac moze zretazit dalsi pan) a potom
# sa zacne vracat k hrdinovi so stupajucou rychlostou (ramp od nuly).
@export var return_delay: float = 0.8      # grace period po dragu, sekundy
@export var return_ramp_time: float = 1.2  # za kolko sekund dosiahne navrat plnu silu

# Referencia na hraca — nastavena v _ready() cez skupina team_player
var _player: Node2D = null

# Stav dragu
var _touch_id := -1
var _drag_anchor_world: Vector2
var _touch_start_screen: Vector2
var _is_dragging := false

# Stav drag-to-deploy edge-panu (riadene z arena.gd cez deploy_preview_* signaly)
var _is_deploy_dragging := false
var _deploy_drag_screen_pos: Vector2
var _has_deploy_pos := false

# Stav soft-follow navratu (len lock rezim)
var _return_timer := 0.0  # odpocitava grace period po skonceni dragu
var _return_ramp := 1.0   # 0..1 sila navratu; 1 = plne sledovanie, po dragu od 0

func _ready() -> void:
	# odpoj kameru od pohybu hraca — kamera je samostatny node, nie child Playera
	# (v scene je Camera2D presunuty pod Arena root, nie pod Player)
	# reaguj na zmenu nastaveni live (bez reloadu sceny)
	Settings.settings_changed.connect(_on_settings_changed)
	# Vypni nativny Camera2D limit — pouzivame len vlastny bounds_min/bounds_max
	# clamp (_clamp_to_bounds). Bez tohto by hocijake stare/zabudnute
	# limit_left/right/top/bottom hodnoty ulozene v .tscn scene ticho
	# obmedzovali kameru navyse, nezavisle od nasho skriptu.
	limit_left = -10000000
	limit_top = -10000000
	limit_right = 10000000
	limit_bottom = 10000000
	# odloz hladanie hraca o jeden frame — player.gd _ready() este nebezal
	call_deferred("_deferred_init")

func _deferred_init() -> void:
	_find_player()
	_apply_mode()

func _find_player() -> void:
	# nepouzivaj team_player skupinu — obsahuje aj sumonovane jednotky (tiez
	# CharacterBody2D), takze prvy najdeny nemusi byt hrdina. BattleManager.heroes
	# je autoritativny zdroj, nastavuje sa v spawn_hero().
	var hero: Node2D = BattleManager.heroes.get("player")
	if hero != null and is_instance_valid(hero):
		_player = hero

func _physics_process(delta: float) -> void:
	# edge-pan pocas tahania karty ma prednost a bezi v OBOCH lock rezimoch —
	# preto pred kontrolou Settings.lock_camera
	if _is_deploy_dragging:
		_process_edge_pan(delta)
		return
	if not Settings.lock_camera:
		return
	if _player == null or not is_instance_valid(_player):
		_find_player()
		return
	# pocas dragu kamera nesleduje — hrac si obzera mapu; timer drzime nabity,
	# takze grace period zacina az od pustenia prsta
	if _is_dragging:
		_return_timer = return_delay
		_return_ramp = 0.0
		return
	# grace period po dragu — kamera stoji, hrac stiha zretazit dalsi pan
	if _return_timer > 0.0:
		_return_timer -= delta
		return
	# navrat / sledovanie so stupajucou silou — po dragu zacina od nuly, plynulo
	# zrychluje az na plne follow_smoothing. Obycajny tap (move/attack) drag
	# nespusti, takze bezne sledovanie bezi neprerusene s ramp = 1.
	_return_ramp = minf(_return_ramp + delta / return_ramp_time, 1.0)
	var target_pos := _player.global_position
	position = position.lerp(target_pos, follow_smoothing * _return_ramp)
	_clamp_to_bounds()

# Drag funguje v OBOCH rezimoch — v lock rezime len docasne pozastavi
# sledovanie (soft-follow, pozri _physics_process).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_touch_start_screen = event.position
			_drag_anchor_world = _screen_to_world(event.position)
			_is_dragging = false
		elif not event.pressed and event.index == _touch_id:
			if _is_dragging:
				# drag prave skoncil — spotrebuj event aby arena.gd nespustil tap-to-move
				get_viewport().set_input_as_handled()
			_touch_id = -1
			_is_dragging = false

	elif event is InputEventScreenDrag and event.index == _touch_id:
		if not _is_dragging:
			if event.position.distance_to(_touch_start_screen) >= drag_threshold:
				_is_dragging = true
		if _is_dragging:
			var current_world := _screen_to_world(event.position)
			position -= current_world - _drag_anchor_world
			_clamp_to_bounds()
			# spotrebuj event — drag nesmie spustit tap-to-move v arena.gd
			get_viewport().set_input_as_handled()

func _clamp_to_bounds() -> void:
	position.x = clampf(position.x, bounds_min.x, bounds_max.x)
	position.y = clampf(position.y, bounds_min.y, bounds_max.y)

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos

func _on_settings_changed() -> void:
	_apply_mode()

func _apply_mode() -> void:
	if Settings.lock_camera:
		# okamzite snapni na hraca pri prepnuti do lock rezimu
		if _player != null and is_instance_valid(_player):
			position = _player.global_position
			_clamp_to_bounds()
		# vymaz drag aj soft-follow stav — zacina sa plnym sledovanim
		_touch_id = -1
		_is_dragging = false
		_return_timer = 0.0
		_return_ramp = 1.0

# Volane z arena.gd pri starte zapasu — nastavi mapovo-zavisle hodnoty.
# Predtym boli bounds_min/max/edge_margin/edge_pan_speed_max len
# per-scene Inspector hodnoty s nulovym prepojenim na
# BattleManager.deploy_bounds (§6) — teraz oboje cita z rovnakeho MapData.
func configure_map(map_data: MapData) -> void:
	bounds_min = map_data.bounds.position
	bounds_max = map_data.bounds.position + map_data.bounds.size
	edge_margin = map_data.camera_edge_margin
	edge_pan_speed_max = map_data.camera_edge_pan_speed_max

# Volane z arena.gd pri deploy_preview_started — zaciatok drag-to-deploy gesta.
func begin_deploy_pan() -> void:
	_is_deploy_dragging = true
	_has_deploy_pos = false

# Volane z arena.gd pri kazdom deploy_preview_updated — nova screen pozicia prsta.
func update_deploy_pan(screen_pos: Vector2) -> void:
	_deploy_drag_screen_pos = screen_pos
	_has_deploy_pos = true

# Volane z arena.gd pri deploy_preview_ended — koniec drag-to-deploy gesta.
func end_deploy_pan() -> void:
	_is_deploy_dragging = false
	if Settings.lock_camera:
		_return_timer = return_delay
		_return_ramp = 0.0
	# ak je lock vypnuty, kamera ostava tam kde ju edge-pan nechal —
	# rovnake spravanie ako bezny unlocked pan

# Kamera sleduje prst s "rezervou" pri okraji obrazovky — cim blizsie k
# okraju, tym rychlejsi pan. Bezi bez ohladu na Settings.lock_camera.
func _process_edge_pan(delta: float) -> void:
	if not _has_deploy_pos:
		return
	var vp_size := get_viewport_rect().size
	var vel := Vector2.ZERO
	if _deploy_drag_screen_pos.x < edge_margin:
		var t := 1.0 - (_deploy_drag_screen_pos.x / edge_margin)
		vel.x -= edge_pan_speed_max * clampf(t, 0.0, 1.0)
	elif _deploy_drag_screen_pos.x > vp_size.x - edge_margin:
		var t := (_deploy_drag_screen_pos.x - (vp_size.x - edge_margin)) / edge_margin
		vel.x += edge_pan_speed_max * clampf(t, 0.0, 1.0)
	if _deploy_drag_screen_pos.y < edge_margin:
		var ty := 1.0 - (_deploy_drag_screen_pos.y / edge_margin)
		vel.y -= edge_pan_speed_max * clampf(ty, 0.0, 1.0)
	elif _deploy_drag_screen_pos.y > vp_size.y - edge_margin:
		var ty := (_deploy_drag_screen_pos.y - (vp_size.y - edge_margin)) / edge_margin
		vel.y += edge_pan_speed_max * clampf(ty, 0.0, 1.0)
	if vel.length() > edge_pan_speed_max:
		vel = vel.normalized() * edge_pan_speed_max
	position += vel * delta
	_clamp_to_bounds()

# Smooth pan kamery na hraca — pouzite ked hrac stlaci PlayerCharacter button v HUD
# Po stlaceni button, kamera sa plynulo vrati na hraca aj v unlocked rezime
var _recenter_tween: Tween = null

func recenter_on_player(duration: float = 0.4) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return
	# zrus existujuci tween ak prebieha — uzivatel mohol stlacit button viackrat
	if _recenter_tween != null and _recenter_tween.is_valid():
		_recenter_tween.kill()
	# vypocitaj cielovu poziciu s respektovanim hranic mapy
	var target_pos := _player.global_position
	target_pos.x = clampf(target_pos.x, bounds_min.x, bounds_max.x)
	target_pos.y = clampf(target_pos.y, bounds_min.y, bounds_max.y)
	# plynuly prechod cez tween
	_recenter_tween = create_tween()
	_recenter_tween.set_ease(Tween.EASE_OUT)
	_recenter_tween.set_trans(Tween.TRANS_QUART)
	_recenter_tween.tween_property(self, "position", target_pos, duration)
	# vymaz drag stav aby prebiehajuci drag neprerusil tween
	_touch_id = -1
	_is_dragging = false
