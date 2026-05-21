extends Area2D

@export var speed: float = 250.0
@export var lifetime: float = 0.5
@export var damage: int = 25

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var current_anim: String = ""
var direction: Vector2 = Vector2.RIGHT

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# pre istotu zapneme spracovanie (niekedy to byva vypnute)
	#set_process(true)
	
	# prechadza cez enemy -> po zasahu sa neznici
	#body_entered.connect (_on_body_entered)

	pass # Replace with function body.

func setup(start_pos: Vector2, dir: Vector2) -> void:
	global_position = start_pos
	direction = dir.normalized()
	_update_sprite_direction(direction)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# trafi enemy telo (CharacterBody2D)
	if body.has_method("take_damage"):
		body.take_damage(damage)

# =========================
# ANIMATION LOGIC
# =========================

func _update_sprite_direction(dir: Vector2) -> void:
	# 8-smerov
	if dir.length() == 0:
		return
	
	var angle := rad_to_deg(dir.angle())
	var anim := ""
	
	# Godot:
	# 0° = right
	# 90° = down
	# -90° = up
	# 180° / -180° = left
	
#           up
#  up_left       up_right
#
#left                    right
#
#  down_left     down_right
#           down
	
	if angle >= -22.5 and angle < 22.5:
		anim = "right"
	
	elif angle >= 22.5 and angle < 67.5:
		anim = "down_right"
	
	elif angle >= 67.5 and angle < 112.5:
		anim = "down"
	
	elif angle >= 112.5 and angle < 157.5:
		anim = "down_left"
	
	elif angle >= -67.5 and angle < -22.5:
		anim = "up_right"
	
	elif angle >= -112.5 and angle < -67.5:
		anim = "up"
	
	elif angle >= -157.5 and angle < -112.5:
		anim = "up_left"
	
	else:
		anim = "left"
	
	if anim != current_anim:
		current_anim = anim
		sprite.play(anim)
