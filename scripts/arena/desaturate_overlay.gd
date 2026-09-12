extends ColorRect
class_name DesaturateOverlay

@export var fade_time: float = 0.3

var _desaturation: float = 0.0
var _tween: Tween = null

func _ready() -> void:
	material.set_shader_parameter("desaturation", 0.0)
	BattleManager.hero_died.connect(_on_hero_died)
	BattleManager.hero_respawned.connect(_on_hero_respawned)

func _on_hero_died(team: String, _respawn_seconds: int) -> void:
	if team != "player":
		return
	_animate_desaturation(1.0)

func _on_hero_respawned(team: String) -> void:
	if team != "player":
		return
	_animate_desaturation(0.0)

func _animate_desaturation(target: float) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_desaturation, _desaturation, target, fade_time)

func _set_desaturation(value: float) -> void:
	_desaturation = value
	material.set_shader_parameter("desaturation", value)
