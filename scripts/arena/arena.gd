extends Node2D

@onready var hud: HUD = $HUD
@onready var map_root: Node2D = $MapRoot
@onready var move_marker: Node2D = $MoveMarker
@onready var deploy_ghost: Node2D = $DeployGhost
@onready var denial_zone_overlay: Node2D = $DenialZoneOverlay
@onready var arena_camera: ArenaCamera = $ArenaCamera
@onready var result_banner: MatchResultBanner = $MatchResultBanner
var player: CharacterBody2D = null

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

# Dlzka zaverecnej sekvencie po padnuti zakladne — zhruba dlzka base_destroyed zvuku.
const END_SEQUENCE_SECONDS := 3.5
var _match_over := false

# Resolvuje sa za behu z MapDB.get_map(MatchConfig.map_id) na zaciatku _ready().
# Ak sa arena.tscn otvori priamo (F6) bez PreMatchFlow, map_id je &"" a nizsie
# null-guardy to zachytia — znama limitacia. Rovnako F6 necha prazdne aj
# MatchConfig hero id-cka a balicky (plni ich PreMatchFlow z PlayerProfile).
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

func _exit_tree() -> void:
	# ziadna hlaska zapasu nesmie dohravat do menu / MatchEndScreen
	AudioManager.stop_announcer()

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
	hud.match_info_bar.wire_tower_icons()

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

	# Match manifest — raz na zaciatku, pred spawnom hrdinov (levely bohov).
	BattleManager.set_team_manifest("player", MatchConfig.local_hero_id,
		MatchConfig.local_hero_level, MatchConfig.local_card_levels)
	BattleManager.set_team_manifest("enemy", MatchConfig.opponent_hero_id,
		MatchConfig.opponent_hero_level, MatchConfig.opponent_card_levels)
	# Synergy efekt na energiu — nekonecny modifikator na cely zapas.
	# EnergySystem.reset_match_state() v _enter_tree() ho pri dalsom zapase zmaze.
	for team in ["player", "enemy"]:
		var regen := BattleManager.get_synergy_energy_regen(team)
		if not is_equal_approx(regen, 1.0):
			EnergySystem.add_modifier(team, EnergySystem.ModType.REGEN_MULT, regen,
				EnergySystem.INFINITE_DURATION, &"synergy")
	hud.synergy_icon.configure("player")

	var player_hero := BattleManager.spawn_hero(MatchConfig.local_hero_id, "player", true)
	player_hero.global_position = map_data.hero_spawn_player
	player = player_hero as CharacterBody2D
	BattleManager.hero_spawn_positions["player"] = map_data.hero_spawn_player

	var enemy_hero := BattleManager.spawn_hero(MatchConfig.opponent_hero_id, "enemy", false)
	enemy_hero.global_position = map_data.hero_spawn_enemy
	BattleManager.hero_spawn_positions["enemy"] = map_data.hero_spawn_enemy

	hud.minimap.configure_map(map_data)

	add_child(EnemyCardAI.new())
	add_child(MatchAnnouncer.new())

	BattleManager.start_match_timer()
	EnergySystem.start()
	AudioManager.play_music(&"battle")

func _unhandled_input(event: InputEvent) -> void:
	if _match_over:
		return
	# Tap-to-move: tap mimo UI (UI eventy sem nedojdu, su handled v _gui_input)
	if event is InputEventScreenTouch and not event.pressed:
		# release tapnutia ktoreho press bol pouzity na vyber primary_target sa ignoruje
		if InputR.is_release_suppressed(event.index):
			return
		var world_pos: Vector2 = get_canvas_transform().affine_inverse() * event.position
		world_pos = BattleManager.snap_to_navigation(world_pos) # prisun tap mimo navmesh (prekazka/hranica) na najblizsi platny bod
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

func _on_match_ended(winner: String) -> void:
	_match_over = true
	EnergySystem.stop()
	if winner == "draw":
		# ziadna budova nepadla — nie je co ukazat, rovno na vysledok
		get_tree().change_scene_to_file("res://scenes/menu/MatchEndScreen.tscn")
		return
	_play_end_sequence(winner)

# Presentation-only: BattleManager uz vysledok rozhodol, tu ho len "ukazeme".
func _play_end_sequence(winner: String) -> void:
	# znicena je zakladna PORAZENEHO timu
	var fallen: Node2D = BattleManager.enemy_base if winner == "player" else BattleManager.player_base
	_on_deploy_preview_ended()          # zrus pripadny rozbehnuty drag karty (ghost, edge-pan)
	hud.visible = false                 # karty, pauza, timer — nic uz nejde stlacit
	$DesaturateRect.visible = false     # ak hrdina prave mrtvy, vitazny/prehrany zaber nema byt sedy
	result_banner.show_result(winner, END_SEQUENCE_SECONDS)
	AudioManager.stop_announcer()
	AudioManager.stop_music(1.0)        # nech je rucanie zakladne pocut; stinger pride na MatchEndScreen
	if fallen != null and is_instance_valid(fallen):
		arena_camera.play_focus(fallen.global_position)
	await get_tree().create_timer(END_SEQUENCE_SECONDS).timeout
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://scenes/menu/MatchEndScreen.tscn")

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed:
		# --- DEBUG energia (len debug build) ---
		if event.keycode == KEY_U:
			EnergySystem.add_modifier("player", EnergySystem.ModType.REGEN_MULT, 2.0, 5.0, &"debug_boost")
			print("[energy] boost 2x na 5s")
		if event.keycode == KEY_I:
			EnergySystem.add_modifier("player", EnergySystem.ModType.COST_REDUCE, 1.0, 5.0, &"debug_bloodlust")
			print("[energy] bloodlust -1 cena na 5s")
		if event.keycode == KEY_Y:
			print("[energy] player=%.2f enemy=%.2f | regen=%.2f/s | card_greek_hoplite cost=%d" % [
				EnergySystem.get_energy("player"), EnergySystem.get_energy("enemy"),
				EnergySystem.get_regen_rate("player"),
				EnergySystem.resolve_cost("player", &"card_greek_hoplite")])
		if event.keycode == KEY_P:
			print("[energy] try_spend card_greek_hoplite -> ", EnergySystem.try_spend("player", &"card_greek_hoplite"))
		# --- DEBUG smrt (len debug build, na testovanie respawn/lock/telegraph) ---
		if event.keycode == KEY_H:
			var dmg := roundi(player.max_hp / 3.0)
			player.take_damage(dmg)
			print("[debug] hurt player for %d (1/3 max_hp)" % dmg)
		# --- DEBUG audio (len debug build) — 10x sword_hit v jednom frame pri hracovi:
		# ma byt pocut max 3 (max_instances) a min_interval ich este preriedi ---
		if event.keycode == KEY_J:
			for _i in 10:
				AudioManager.play_sfx(&"sword_hit", player.global_position)
			print("[audio] 10x sword_hit spam")
