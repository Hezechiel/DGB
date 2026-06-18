extends CharacterBody2D

# bojove vlastnosti hraca
@export var speed: float = 70.0
@export var max_hp: int = 500
var health_points: int

@export var invuln_time: float = 0.25 # (invulnerability window)
var invuln_left: float = 0.0

# vlastnosti Lightning projektilu
@export var bolt_scene: PackedScene
@export var fire_cooldown: float = 0.5
@export var attack_range: float = 80.0
# leash: ak sa ciel vzdiali nad tento nasobok attack_range, lock sa zrusi
@export var leash_multiplier: float = 4.0
@export var projectile_damage: int = 25
var fire_left: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var health_bar: Control = $HealthBar


var last_direction := Vector2.DOWN #default pozera dole

var primary_target: Node2D = null

func _ready() -> void:
	health_points = max_hp
	health_bar.init(max_hp, "player")
	add_to_group("team_player")
	BattleManager.register(self, "player")
	hurtbox.add_to_group("player_hurtbox")
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	InputR.clear_move_target() # zmaz stary ciel po reloade sceny

func _physics_process(delta):
	invuln_left = max(invuln_left - delta, 0.0)
	fire_left = max(fire_left - delta, 0.0)

	# 1) pohyb — vzdy z tap-to-move, chase len ak hrac nema vlastny prikaz
	var move_dir := get_move_input()

	# 2) bojova logika — primary_target ma prednost, fallback na najblizsiho
	if primary_target != null and is_instance_valid(primary_target):
		var to_target := primary_target.global_position - global_position
		var dist_sq := to_target.length_squared()
		var leash_sq := (attack_range * leash_multiplier) * (attack_range * leash_multiplier)
		if dist_sq > leash_sq:
			# prilis daleko — zrus lock
			_clear_primary_target()
		else:
			if dist_sq <= attack_range * attack_range:
				# v dosahu — strielaj
				_try_fire(primary_target)
			elif move_dir == Vector2.ZERO:
				# mimo dosahu a hrac nekaze ist inam — chase
				move_dir = to_target.normalized()
	else:
		primary_target = null
		var nearest := find_nearest_enemy()
		if nearest != null:
			_try_fire(nearest)

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
	# Tap-to-move (autoload InputRouter)
	if InputR.has_move_target:
		var to_target := InputR.move_target - global_position
		if to_target.length() <= 8.0:
			InputR.clear_move_target() # sme dost blizko, stop
			return Vector2.ZERO
		return to_target.normalized()

	return Vector2.ZERO

# =========================
# FIGHTING LOGIC
# =========================

func set_primary_target(node: Node2D) -> void:
	# skry marker na stary ciel
	if primary_target != null and is_instance_valid(primary_target):
		if primary_target.has_method("set_targeted"):
			primary_target.set_targeted(false)
	primary_target = node
	# novy lock zrusi tap-to-move ciel — hrac zacne pristupovat k cielu
	InputR.clear_move_target()
	# ukaz marker na novy ciel
	if node.has_method("set_targeted"):
		node.set_targeted(true)
	# ked ciel zomrie / zmizne zo stromu, automaticky vymaz referenciu
	if not node.tree_exited.is_connected(_on_primary_target_removed):
		node.tree_exited.connect(_on_primary_target_removed)

func _on_primary_target_removed() -> void:
	# node uz neexistuje — marker zanikol spolu s nim, len vymaz referenciu
	primary_target = null

func _clear_primary_target() -> void:
	# skry marker a zrus lock (napr. ked hrac tapne na zem)
	if primary_target != null and is_instance_valid(primary_target):
		if primary_target.has_method("set_targeted"):
			primary_target.set_targeted(false)
	primary_target = null

func _try_fire(target: Node2D) -> void:
	if fire_left <= 0.0:
		last_direction = (target.global_position - global_position).normalized()
		fire_bolt(target)
		fire_left = fire_cooldown

func find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_d2 := attack_range * attack_range
	for child in get_parent().get_children():
		if child == self:
			continue
		if child is Node2D and child.is_in_group("team_enemy"):
			var d2: float = child.global_position.distance_squared_to(global_position)
			if d2 <= nearest_d2:
				nearest_d2 = d2
				nearest = child
	return nearest

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

	health_bar.set_health(health_points)

	if health_points <= 0:
		print("PLAYER DEAD")
		get_tree().reload_current_scene()

func fire_bolt(target: Node2D) -> void:
	if bolt_scene == null:
		push_error("Player: bolt_scene nie je nastavene!")
		return

	var bolt := bolt_scene.instantiate()
	bolt.set("damage", projectile_damage)
	get_parent().add_child.call_deferred(bolt)
	bolt.call_deferred("setup", global_position, target)


# Tato funkcia sa zavola ked nieco vstupi do Hurtboxu
# V nasom modeli ale damage bide "tahat" enemy cez cooldown,
# takze tu zatial nemusis nic riesit.
func _on_hurtbox_area_entered(_area: Area2D) -> void:
	pass

# =========================
# ANIMATION LOGIC
# =========================

func update_animation(direction: Vector2) -> void:
	# Porovname absolutne hodnoty osi
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			sprite.play("new_back_right") #RIGHT
		else:
			sprite.play("new_front_left") #LEFT
	else:
		if direction.y > 0:
			sprite.play("new_front_left") #DOWN
		else:
			sprite.play("new_back_right") #UP

func update_idle_animation() -> void:
	if abs(last_direction.x) > abs(last_direction.y):
		if last_direction.x > 0:
			sprite.play("new_back_right") #RIGHT
		else:
			sprite.play("new_front_left") #LEFT
	else:
		if last_direction.y > 0:
			sprite.play("new_front_left") #DOWN
		else:
			sprite.play("new_back_right") #UP
