extends Node2D

@onready var hud: HUD = $HUD
@onready var map_root: Node2D = $MapRoot
@onready var move_marker: Node2D = $MoveMarker
@onready var deploy_ghost: Node2D = $DeployGhost
@onready var denial_zone_overlay: Node2D = $DenialZoneOverlay
@onready var arena_camera: ArenaCamera = $ArenaCamera
var player: CharacterBody2D = null

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

# TEMP: kym nepride realny hero-select/network flow, hrdinovia su nastaveni
# napevno — player Zeus, enemy Poseidon. Rovnaka kategoria TEMP ako predtym.
const PLAYER_HERO_ID := &"hero_zeus"
const ENEMY_HERO_ID := &"hero_poseidon"

# Resolvuje sa za behu z MapDB.get_map(MatchConfig.map_id) na zaciatku _ready().
# Ak sa arena.tscn otvori priamo (F6) bez PreMatchFlow, map_id je &"" a nizsie
# null-guardy to zachytia — znama limitacia, rovnaka kategoria ako TEMP hero ids.
var map_data: MapData

func _enter_tree() -> void:
	# _enter_tree beží zhora nadol (parent pred childmi) — turrety/zakladne sa
	# registruju vo svojom _ready() (dieta), ktore bezi PRED _ready() rodica.
	# Reset preto MUSI prebehnut tu, nie v _ready(), inak by zmazal
	# registracie ktore uz medzitym stihli prebehnut z novej sceny.
	BattleManager.reset_match_state()
	BattleManager.arena_root = self
	# EnergySystem je samostatny autoload — vlastny reset, nie je v
	# BattleManager.reset_match_state().
	EnergySystem.reset_match_state()
	# HealingSystem tiez — treti autoload, rovnaka pastca (architecture.md §6).
	HealingSystem.reset_match_state()
	# HeroAI tiez — dalsi autoload, rovnaka pastca.
	HeroAI.reset_match_state()

func _ready() -> void:
	map_data = MapDB.get_map(MatchConfig.map_id)
	if map_data == null:
		push_error("Arena: map_data nie je nastaveny")
		return
	if map_data.map_scene == null:
		push_error("Arena: map_data.map_scene nie je nastaveny")
		return
	# Obsah mapy (pozadie/tilemap/prekazky/struktury) sa instancuje az za behu
	# do prazdneho MapRoot — arena.tscn uz nereferencuje konkretnu mapu.
	# Synchronne (nie call_deferred): struktury sa musia stihnut zaregistrovat
	# do BattleManager tu, po _enter_tree() resete a PRED spawnom hrdinov nizsie.
	var map_instance := map_data.map_scene.instantiate()
	map_root.add_child(map_instance)
	BattleManager.configure_map(map_data)
	arena_camera.configure_map(map_data)

	hud.exit_requested.connect(_on_hud_exit_requested)
	hud.recenter_camera_requested.connect(_on_recenter_camera_requested)
	hud.card_hand.deploy_preview_updated.connect(_on_deploy_preview_updated)
	hud.card_hand.deploy_preview_ended.connect(_on_deploy_preview_ended)
	hud.card_hand.deploy_preview_started.connect(_on_deploy_preview_started)
	BattleManager.match_ended.connect(_on_match_ended)
	# 2D object picking je defaultne vypnute — bez neho Area2D.input_event
	# (tap na enemy/turret/base hurtbox) nikdy nevystreli
	get_viewport().physics_object_picking = true
	get_viewport().physics_object_picking_sort = true

	var player_hero := BattleManager.spawn_hero(PLAYER_HERO_ID, "player", true)
	player_hero.global_position = map_data.hero_spawn_player
	player = player_hero as CharacterBody2D
	BattleManager.hero_spawn_positions["player"] = map_data.hero_spawn_player

	var enemy_hero := BattleManager.spawn_hero(ENEMY_HERO_ID, "enemy", false)
	enemy_hero.global_position = map_data.hero_spawn_enemy
	BattleManager.hero_spawn_positions["enemy"] = map_data.hero_spawn_enemy

	add_child(EnemyCardAI.new())

	BattleManager.start_match_timer()
	EnergySystem.start()

func _unhandled_input(event: InputEvent) -> void:
	# Tap-to-move: tap mimo UI (UI eventy sem nedojdu, su handled v _gui_input)
	if event is InputEventScreenTouch and not event.pressed:
		# release tapnutia ktoreho press bol pouzity na vyber primary_target sa ignoruje
		if InputR.is_release_suppressed(event.index):
			return
		var world_pos: Vector2 = get_canvas_transform().affine_inverse() * event.position
		InputR.set_move_target(world_pos)
		player.on_new_move_command() # novy tap-to-move zrusi manualny lock na cieli
		move_marker.show_at(world_pos)

func _on_hud_exit_requested() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_recenter_camera_requested() -> void:
	arena_camera.recenter_on_player()

func _on_deploy_preview_started(card: CardData) -> void:
	deploy_ghost.configure_for_card(card)
	arena_camera.begin_deploy_pan()
	denial_zone_overlay.show_for_card(card)

func _on_deploy_preview_updated(world_pos: Vector2, is_valid: bool, screen_pos: Vector2) -> void:
	deploy_ghost.show_at(world_pos, is_valid)
	arena_camera.update_deploy_pan(screen_pos)

func _on_deploy_preview_ended() -> void:
	deploy_ghost.hide_ghost()
	arena_camera.end_deploy_pan()
	denial_zone_overlay.hide_zones()

func _on_match_ended(_winner: String) -> void:
	EnergySystem.stop()
	get_tree().change_scene_to_file("res://scenes/menu/MatchEndScreen.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# --- DEBUG energia (docasne, kym nie je energy bar — krok 2) ---
		if event.keycode == KEY_U:
			EnergySystem.add_modifier("player", EnergySystem.ModType.REGEN_MULT, 2.0, 5.0, &"debug_boost")
			print("[energy] boost 2x na 5s")
		if event.keycode == KEY_I:
			EnergySystem.add_modifier("player", EnergySystem.ModType.COST_REDUCE, 1.0, 5.0, &"debug_bloodlust")
			print("[energy] bloodlust -1 cena na 5s")
		if event.keycode == KEY_Y:
			print("[energy] player=%.2f enemy=%.2f | regen=%.2f/s | card_05 cost=%d" % [
				EnergySystem.get_energy("player"), EnergySystem.get_energy("enemy"),
				EnergySystem.get_regen_rate("player"),
				EnergySystem.resolve_cost("player", &"card_05")])
		if event.keycode == KEY_P:
			print("[energy] try_spend card_05 -> ", EnergySystem.try_spend("player", &"card_05"))
		# --- DEBUG smrt (docasne, na testovanie respawn/lock/telegraph) ---
		if event.keycode == KEY_H:
			var dmg := roundi(player.max_hp / 3.0)
			player.take_damage(dmg)
			print("[debug] hurt player for %d (1/3 max_hp)" % dmg)
