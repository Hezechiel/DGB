extends Node2D

# EnemySpawner — spawnuje enemy unity do lan pri enemy baze
# 5 unity na top lanu + 5 unity na bot lanu = 10 unity na vlnu
# Vlna kazde wave_interval sekund

@export var unit_scene: PackedScene

# Cas medzi vlnami v sekundach
@export var wave_interval: float = 10.0

# Pocet unity na lanu na vlnu
@export var units_per_lane: int = 5

# Maly rozptyl pozicie aby sa unity nespawnovali presne na seba (world units)
@export var spawn_scatter: float = 8.0

# Spawn pozicie pri enemy baze — blizko prveho waypointu enemy_top / enemy_bot
# Zodpoveda LaneManager enemy_top[0] = Vector2(280, -100)
#                         enemy_bot[0] = Vector2(280,  100)
@export var spawn_pos_top: Vector2 = Vector2(300, -100)
@export var spawn_pos_bot: Vector2 = Vector2(300,  100)

@onready var wave_timer: Timer = $WaveTimer

func _ready() -> void:
	if unit_scene == null:
		push_error("EnemySpawner: unit_scene nie je nastavene!")
		return
	wave_timer.wait_time = wave_interval
	wave_timer.one_shot = false
	wave_timer.timeout.connect(_on_wave_timer_timeout)
	wave_timer.start()
	# prvá vlna okamzite pri starte pre rychle testovanie
	_spawn_wave()

func _on_wave_timer_timeout() -> void:
	_spawn_wave()

func _spawn_wave() -> void:
	# 5 unity na top lanu
	for i in range(units_per_lane):
		_spawn_unit("top", spawn_pos_top, i)
	# 5 unity na bot lanu
	for i in range(units_per_lane):
		_spawn_unit("bot", spawn_pos_bot, i)

func _spawn_unit(lane: String, base_pos: Vector2, index: int) -> void:
	var unit := unit_scene.instantiate()

	# nastav team a lanu pred pridanim do stromu
	unit.team = "enemy"
	unit.lane = lane

	# rozptyl aby sa unity nespawnovali presne na seba
	var scatter := Vector2(
		randf_range(-spawn_scatter, spawn_scatter),
		randf_range(-spawn_scatter, spawn_scatter)
	)
	unit.global_position = base_pos + scatter

	# pridaj ako subrat areny (spawner je child areny)
	get_parent().add_child.call_deferred(unit)
