extends Node2D

@export var human_scene: PackedScene
@export var player: Node2D

# Arena bounds (svetové súradnice)
@export var arena_min: Vector2 = Vector2(-150, -140)
@export var arena_max: Vector2 = Vector2(150, 150)

# Spawn pravidla
@export var min_distance_from_player: float = 160.0
@export var min_distance_between_enemies: float = 10.0
@export var max_spawn_attempts: int = 40
@export var edge_padding: float = 8.0

# Vlny
@export var max_enemies_alive: int = 10
@export var enemies_per_wave: int = 3
@export var time_between_waves: float = 2.0
@export var spawn_interval_inside_wave: float = 0.12

@onready var wave_timer: Timer = $WaveTimer

var _spawning := false
var enemies: Array[Node2D] = []

func _ready() -> void:
	randomize()
	if human_scene == null:
		push_error("EnemySpawner: human_scene nie je nastavene!")
		return
		
	wave_timer.wait_time = time_between_waves
	wave_timer.one_shot = false
	wave_timer.timeout.connect(_on_wave_timer_timeout)
	wave_timer.start()
	
	# pockat frame aby sa nespawnoval prvy nepriatel skor ako je setup ready
	await get_tree().process_frame
	
	# volitelne prva vlna hned
	_on_wave_timer_timeout()

func _on_wave_timer_timeout() -> void:
	if _spawning:
		return
	_spawning = true
	await spawn_wave(enemies_per_wave)
	_spawning = false

func spawn_wave(count: int) -> void:
	var alive := enemies.size()
	if alive >= max_enemies_alive:
		return
	
	var can_spawn: int = min(count, max_enemies_alive - alive)
	for i in range(can_spawn):
		spawn_one_enemy()
		await get_tree().create_timer(spawn_interval_inside_wave).timeout
	
	#print("Enemies on field: ", enemies.size())

func spawn_one_enemy() -> void:
	var pos: Vector2 = find_valid_spawn_position()
	if pos == Vector2.INF:
		# nenaslo sa miesto - radsej spawnuj
		return
	if pos.distance_to(player.global_position) < 5:
		return
	
	# nastav target (tvoj human.gd musi mat: var target: Node2D)
	var human := human_scene.instantiate()
	human.global_position = pos
	human.target = player
	human.tree_exited.connect(func(): enemies.erase(human))
	human.enemy_manager = self
	
	# aby sme vedely rychlo hladat existujucich enemy
	enemies.append(human)
	
	# predpoklad: spawner je pod rootom Game
	get_parent().add_child.call_deferred(human)

func find_valid_spawn_position() -> Vector2:
	for attempt in range(max_spawn_attempts):
		var p: Vector2 = random_point_on_edge()
		
		# 1) min vzdialenost od hraca
		if p.distance_to(player.global_position) < min_distance_from_player:
			continue
		
		# 2) anti-stack: min vzdialenost od existujúcich enemy
		if is_too_close_to_other_enemies(p, min_distance_between_enemies):
			continue
			
		return p
		
	return random_point_on_edge()

func is_too_close_to_other_enemies(p: Vector2, min_dist: float) -> bool:
	for e in enemies:
		if e is Node2D:
			if p.distance_to(e.global_position) < min_dist:
				return true
	return false

func random_point_on_edge() -> Vector2:
	var x_min := arena_min.x
	var y_min := arena_min.y
	var x_max := arena_max.x
	var y_max := arena_max.y
	
	var pad := edge_padding
	
	# veberieme nahodnu stranu: 0=top,1=right,2=bottom,3=left
	var side := randi() % 4
	
	match side:
		0: # top
			return Vector2(randf_range(x_min, x_max), y_min + pad)
		1: # right
			return Vector2(x_max - pad, randf_range(y_min, y_max))
		2: # bottom
			return Vector2(randf_range(x_min, x_max), y_max - pad)
		3: # left
			return Vector2(x_min + pad, randf_range(y_min, y_max))
	
	# fallback
	return Vector2(x_min, y_min)
