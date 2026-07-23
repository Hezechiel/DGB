extends Node2D

@onready var hud: HUD = $HUD
@onready var move_marker: Node2D = $MoveMarker
@onready var deploy_ghost: Node2D = $DeployGhost
@onready var arena_camera: Camera2D = $ArenaCamera
var player: CharacterBody2D = null

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

# TEMP: kym nepride realny hero-select/network flow, oba hrdinovia pouzivaju
# rovnaky test HeroData
const PLAYER_HERO_ID := &"hero_test"
const ENEMY_HERO_ID := &"hero_test"

@export var hero_spawn_player: Vector2 = Vector2(-250, 0)  # == povodna bakovana pozicia Playera
@export var hero_spawn_enemy: Vector2 = Vector2(250, 0)    # zrkadlovy offset od EnemyBase

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

func _ready() -> void:
	hud.exit_requested.connect(_on_hud_exit_requested)
	hud.recenter_camera_requested.connect(_on_recenter_camera_requested)
	hud.card_hand.deploy_preview_updated.connect(_on_deploy_preview_updated)
	hud.card_hand.deploy_preview_ended.connect(_on_deploy_preview_ended)
	BattleManager.match_ended.connect(_on_match_ended)
	# 2D object picking je defaultne vypnute — bez neho Area2D.input_event
	# (tap na enemy/turret/base hurtbox) nikdy nevystreli
	get_viewport().physics_object_picking = true
	get_viewport().physics_object_picking_sort = true

	var player_hero := BattleManager.spawn_hero(PLAYER_HERO_ID, "player", true)
	player_hero.global_position = hero_spawn_player
	player = player_hero as CharacterBody2D
	BattleManager.hero_spawn_positions["player"] = hero_spawn_player

	var enemy_hero := BattleManager.spawn_hero(ENEMY_HERO_ID, "enemy", false)
	enemy_hero.global_position = hero_spawn_enemy
	BattleManager.hero_spawn_positions["enemy"] = hero_spawn_enemy

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

func _on_deploy_preview_updated(world_pos: Vector2, is_valid: bool) -> void:
	deploy_ghost.show_at(world_pos, is_valid)

func _on_deploy_preview_ended() -> void:
	deploy_ghost.hide_ghost()

func _on_match_ended(_winner: String) -> void:
	EnergySystem.stop()
	get_tree().change_scene_to_file("res://scenes/menu/MatchEndScreen.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_T:
			$Turret.take_damage(80)
		if event.keycode == KEY_Y:
			$PlayerBase.take_damage(500)
		# --- DEBUG energia (docasne, kym nie je energy bar — krok 2) ---
		if event.keycode == KEY_U:
			EnergySystem.add_modifier("player", EnergySystem.ModType.REGEN_MULT, 2.0, 5.0, &"debug_boost")
			print("[energy] boost 2x na 5s")
		if event.keycode == KEY_I:
			EnergySystem.add_modifier("player", EnergySystem.ModType.COST_REDUCE, 1.0, 5.0, &"debug_bloodlust")
			print("[energy] bloodlust -1 cena na 5s")
		if event.keycode == KEY_O:
			print("[energy] player=%.2f enemy=%.2f | regen=%.2f/s | card_05 cost=%d" % [
				EnergySystem.get_energy("player"), EnergySystem.get_energy("enemy"),
				EnergySystem.get_regen_rate("player"),
				EnergySystem.resolve_cost("player", &"card_05")])
		if event.keycode == KEY_P:
			print("[energy] try_spend card_05 -> ", EnergySystem.try_spend("player", &"card_05"))
