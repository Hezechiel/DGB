extends Panel
class_name MatchInfoBar

# Buduce kroky sem zapoja:
# - odpocet casu zapasu (TimerLabel)
# - ikony znicenych veze (PlayerTowers / EnemyTowers)
# - respawn countdown hrdinu (PlayerRespawnCounter / EnemyRespawnCounter)
# - BattleManager signaly (match_ended, znicenie veze/bazy a pod.)

@onready var timer_label: Label = $MarginContainer/HBoxContainer/TimerLabel
@onready var player_towers: HBoxContainer = $MarginContainer/HBoxContainer/PlayerTowers
@onready var enemy_towers: HBoxContainer = $MarginContainer/HBoxContainer/EnemyTowers
@onready var player_respawn_counter: RespawnCounter = $MarginContainer/HBoxContainer/PlayerRespawnCounter
@onready var enemy_respawn_counter: RespawnCounter = $MarginContainer/HBoxContainer/EnemyRespawnCounter

func _ready() -> void:
	BattleManager.hero_died.connect(_on_hero_died)
	BattleManager.hero_respawn_tick.connect(_on_hero_respawn_tick)
	BattleManager.hero_respawned.connect(_on_hero_respawned)
	BattleManager.match_time_tick.connect(_on_match_time_tick)

func _on_hero_died(team: String, respawn_seconds: int) -> void:
	_counter_for(team).show_countdown(respawn_seconds)

func _on_hero_respawn_tick(team: String, seconds_left: int) -> void:
	_counter_for(team).show_countdown(seconds_left)

func _on_hero_respawned(team: String) -> void:
	_counter_for(team).hide_counter()

func _counter_for(team: String) -> RespawnCounter:
	return player_respawn_counter if team == "player" else enemy_respawn_counter

func _on_match_time_tick(seconds_left: int) -> void:
	@warning_ignore("integer_division")
	timer_label.text = "%d:%02d" % [seconds_left / 60, seconds_left % 60]
