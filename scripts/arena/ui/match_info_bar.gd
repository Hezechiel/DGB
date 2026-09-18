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

# Volane z arena.gd, hned po BattleManager.configure_map() — vtedy uz su vsetky
# struktury (turrety) zaregistrovane (self-register vo vlastnom _ready(), ktore
# bezi PRED _ready() rodica, teda uz pred timto bodom). MatchInfoBar._ready() sa
# na to spolahnut NEMOZE — HUD je uz v arena.tscn od zaciatku, takze jeho _ready()
# bezi PRED _ready() arena.gd (teda PRED instanciovanim mapy) — rovnaky dovod ako
# presun Minimap.configure_map() volania v arena.gd.
func wire_tower_icons() -> void:
	_wire_team_towers("player", player_towers)
	_wire_team_towers("enemy", enemy_towers)

# Tower1/2/3 su fixne UI sloty (vizualne poradie v bare), NIE index do
# BattleManager.get_turrets() — to pole je zoradene podla lane-bucketu (top
# potom bot) a poradie v ramci "bot" bucketu zavisi od poradia registracie v
# map scene, ktore sa REALNE LISI medzi player a enemy stranou na existujucich
# mapach (over v GreekPlateauMap.tscn / NordPlainsMap.tscn). Identita slotu preto
# ide cez meno node-u ("Top"/"Base"/"Bot" substring) — rovnaky princip ako
# HealingPod.owning_side (architecture.md) — nie cez poziciu v poli.
func _wire_team_towers(team: String, towers_container: HBoxContainer) -> void:
	var slot_icons := {
		"Top": towers_container.get_node("Tower1") as Panel,
		"Base": towers_container.get_node("Tower2") as Panel,
		"Bot": towers_container.get_node("Tower3") as Panel,
	}
	for turret in BattleManager.get_turrets(team):
		for slot_name in slot_icons.keys():
			if slot_name in turret.name:
				var icon: Panel = slot_icons[slot_name]
				turret.destroyed.connect(_on_tower_destroyed.bind(icon), CONNECT_ONE_SHOT)
				break

# Tower1/2/3 v ramci jedneho timu zdielaju JEDEN StyleBoxFlat sub_resource
# (StyleBoxFlat_towerBlue / _towerRed) — priamo prepisat jeho bg_color by
# zosedivelo VSETKY veze naraz. Preto duplicate() + per-Panel override, rovnaky
# princip ktory uz raz sposobil problem pri Card cost labeli (zdielany
# StyleBoxEmpty_cost).
func _on_tower_destroyed(icon: Panel) -> void:
	var style: StyleBoxFlat = (icon.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	style.bg_color = Minimap.COLOR_DESTROYED  # rovnaky odtien ako minimapa — vizualna konzistencia
	icon.add_theme_stylebox_override("panel", style)
