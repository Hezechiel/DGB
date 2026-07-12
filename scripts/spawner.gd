extends Node2D

# EnemySpawner — spawnuje enemy aj ally unity do lan, kazdy tim z vlastnej bazy
# 5 unity na top lanu + 5 unity na bot lanu = 10 unity na vlnu, pre kazdy tim
# Vlna kazde wave_interval sekund
#
# Instanciacia jednotiek ide vzdy cez BattleManager.spawn_unit() — spawner
# uz priamo neinstancuje ziadnu scenu, len vybera kartu a poziciu.

# TEMP: docasne pevne priradenie karty per team, kym nepride realny
# mana/hand draw flow — spawner zatial simuluje "vzdy zahraj tuto kartu"
const PLAYER_TEST_CARD := &"card_01"
const ENEMY_TEST_CARD := &"card_04"

# Cas medzi vlnami v sekundach
@export var wave_interval: float = 10.0

# Pocet unity na lanu na vlnu
@export var units_per_lane: int = 5

# Maly rozptyl pozicie aby sa unity nespawnovali presne na seba (world units)
@export var spawn_scatter: float = 8.0

# Spawn pozicie pri enemy baze (top/bot lana)
@export var spawn_pos_enemy_top: Vector2 = Vector2(275, -50)
@export var spawn_pos_enemy_bot: Vector2 = Vector2(275,  50)

# Spawn pozicie pri player baze (top/bot lana)
@export var spawn_pos_player_top: Vector2 = Vector2(-275, -50)
@export var spawn_pos_player_bot: Vector2 = Vector2(-275,  50)

@onready var wave_timer: Timer = $WaveTimer

func _ready() -> void:
	wave_timer.wait_time = wave_interval
	wave_timer.one_shot = false
	wave_timer.timeout.connect(_on_wave_timer_timeout)
	wave_timer.start()
	# prvá vlna okamzite pri starte pre rychle testovanie
	_spawn_wave()

func _on_wave_timer_timeout() -> void:
	_spawn_wave()

func _spawn_wave() -> void:
	# enemy: 5 top + 5 bot, marsiruju od enemy bazy k player baze
	for i in range(units_per_lane):
		_spawn_unit("enemy", spawn_pos_enemy_top, i)
	for i in range(units_per_lane):
		_spawn_unit("enemy", spawn_pos_enemy_bot, i)

	# ally: 5 top + 5 bot, marsiruju od player bazy k enemy baze
	for i in range(units_per_lane):
		_spawn_unit("player", spawn_pos_player_top, i)
	for i in range(units_per_lane):
		_spawn_unit("player", spawn_pos_player_bot, i)

func _spawn_unit(team: String, base_pos: Vector2, _index: int) -> void:
	var card_id := PLAYER_TEST_CARD if team == "player" else ENEMY_TEST_CARD

	# rozptyl aby sa unity nespawnovali presne na seba
	var scatter := Vector2(
		randf_range(-spawn_scatter, spawn_scatter),
		randf_range(-spawn_scatter, spawn_scatter)
	)
	BattleManager.spawn_unit(card_id, base_pos + scatter, team)
