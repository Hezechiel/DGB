extends Node2D

# Vizualny marker pre tap-to-move - jedna instancia, reusuje sa pri kazdom tape
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)

func show_at(pos: Vector2) -> void:
	global_position = pos
	sprite.visible = true
	sprite.stop() # restart aj ked animacia prave bezi
	sprite.frame = 0
	sprite.play("play")

func _on_animation_finished() -> void:
	sprite.visible = false
