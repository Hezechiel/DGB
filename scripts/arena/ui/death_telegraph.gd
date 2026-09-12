extends CanvasLayer
class_name DeathTelegraph

@onready var god_dead_label: Label = $CenterLabel/GodDeadLabel
@onready var countdown_label: Label = $CenterLabel/CountdownLabel

func _ready() -> void:
	visible = false
	BattleManager.hero_died.connect(_on_hero_died)
	BattleManager.hero_respawn_tick.connect(_on_hero_respawn_tick)
	BattleManager.hero_respawned.connect(_on_hero_respawned)

func _on_hero_died(team: String, respawn_seconds: int) -> void:
	if team != "player":
		return
	visible = true
	countdown_label.text = str(respawn_seconds)

func _on_hero_respawn_tick(team: String, seconds_left: int) -> void:
	if team != "player":
		return
	countdown_label.text = str(seconds_left)

func _on_hero_respawned(team: String) -> void:
	if team != "player":
		return
	visible = false
