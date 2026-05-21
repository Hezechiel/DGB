extends CharacterBody2D

# bojove vlastnosti hraca
@export var speed: float = 100.0
@export var max_hp: int = 500
var health_points: int

@export var invuln_time: float = 0.25 # (invulnerability window)
var invuln_left: float = 0.0

# vlastnosti Lightning projektilu
@export var bolt_scene: PackedScene
@export var fire_cooldown: float = 0.5
var fire_left: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox


var last_direction := Vector2.DOWN #default pozera dole

func _ready() -> void:
	health_points = max_hp
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	
func _physics_process(delta):
	invuln_left = max(invuln_left - delta, 0.0)
	fire_left = max(fire_left - delta, 0.0)
	
	# 1) HYBRID MOVE INPUT
	var move_dir : Vector2 = get_move_input()
	var aim_dir : Vector2 = get_aim_input()
	
	# 2) HYBRID ATTACK INPUT
	if aim_dir.length() > 0.15 and fire_left <= 0.0:
		fire_left = fire_cooldown
		fire_bolt(aim_dir.normalized())
	
	# Normalizacia (aby diagonalna nebola rychlejsia)
	if move_dir != Vector2.ZERO:
		move_dir = move_dir.normalized()
		last_direction = move_dir
		update_animation(move_dir)
	else:
		update_idle_animation()
	
	velocity = velocity.move_toward(move_dir * speed, 500 * delta)
	move_and_slide()

func get_move_input() -> Vector2:
	# PC / gamepad (Input Map)
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# Mobile joystick (autoload InputRouter)
	# deadzone aby to "neplavalo"
	if InputR.move_vector.length() > 0.10:
		v = InputR.move_vector
	
	return v

func get_aim_input() -> Vector2:
	var v: Vector2 = Vector2.ZERO
	
	# Desktop fallback - attack + last movement direction, alebo myš neskôr
	if Input.is_action_pressed("attack"):
		v = last_direction
	
	# Mobile aim jyostick
	if InputR.aim_vector.length() > 0.10:
		v = InputR.aim_vector
	
	return v
	
# =========================
# FIGHTING LOGIC
# =========================

func is_attack_pressed() -> bool:
	# PC (Input Map)
	if Input.is_action_pressed("attack"):
		return true
	
	# Mobile button (autoload InputRouter "InputR")
	return InputR.attack_pressed

func take_damage(amount: int) -> void:
	if invuln_left > 0.0:
		return
	
	health_points -= amount
	invuln_left = invuln_time
	
	# vizualny feedback (zatial jednoduchy)
	sprite.modulate.a = 0.4
	await get_tree().create_timer(0.08).timeout
	sprite.modulate.a = 1.0
	
	#print(health_points)
	
	if health_points <= 0:
		print("PLAYER DEAD")
		get_tree().reload_current_scene()

func fire_bolt(dir: Vector2) -> void:
	if bolt_scene == null:
		push_error("Player: bolt_scene nie je nastavene!")
		return

	if dir == Vector2.ZERO:
		dir = last_direction
	
	var bolt := bolt_scene.instantiate()
		# bezpecne pridaj do sceny (niekedy sa hodi deferred)
	get_parent().add_child.call_deferred(bolt)
	
	# po pridani nastav poziciu/direction
	var start_pos = global_position + dir * 12.0
	bolt.call_deferred("setup", start_pos, dir)
	

# Tato funkcia sa zavola ked nieco vstupi do Hurtboxu
# V nasom modeli ale damage bide "tahat" enemy cez cooldown,
# takze tu zazial nemusis nic riesit.
func _on_hurtbox_area_entered(_area: Area2D) -> void:
	pass

# =========================
# ANIMATION LOGIC
# =========================

func update_animation(direction: Vector2) -> void:
	# Porovname absolutne hodnoty osi
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			sprite.play("right")
		else:
			sprite.play("left")
	else:
		if direction.y > 0:
			sprite.play("down")
		else:
			sprite.play("up")

func update_idle_animation() -> void:
	if abs(last_direction.x) > abs(last_direction.y):
		if last_direction.x > 0:
			sprite.play("right")
		else:
			sprite.play("left")
	else:
		if last_direction.y > 0:
			sprite.play("down")
		else:
			sprite.play("up")
