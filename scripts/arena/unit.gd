extends CharacterBody2D

# === TIM A CIELENIE ===
# team: "player" alebo "enemy" — riadi groupy, BattleManager registraciu a farbu health baru
@export var team: String = "enemy"

# Filter kto sa pocita ako platny ciel pri vstupe do attack range
# ALL = utoci na vsetky nepriatelske ciele (heroes, units, turrets, bases)
# UNITS_ONLY = utoci len na heroes a units (ignoruje struktury — napr. melee minion)
# STRUCTURES_ONLY = utoci len na turrety a bazy (napr. baranidlo / battering ram)
enum TargetFilter { ALL, UNITS_ONLY, STRUCTURES_ONLY }
@export var target_filter: TargetFilter = TargetFilter.ALL

# Pohyb enemy po mape
@export var speed: float = 35.0
@export var separation_radius: float = 5.0
@export var separation_strength: float = 1.3
@export var separation_update_interval: float = 0.10
var sep_timer: float = 0.0
var cached_sep: Vector2 = Vector2.ZERO
# Ak sa budú “rozliezať” príliš do strán, zníž separation_strength.
# Ak sa stále zlepia, zvýš separation_radius (10.0 az 14.0) alebo strength (1.0 až 2.0).
@export var seek_strength: float = 1.0
@export var max_neighbors: int = 8

# bojove vlastnosti nepriatela
@export var damage: int = 10
@export var attack_cooldown: float = 1.2
@export var aggro_range: float = 11.0
var attack_left: float = 0.0
var hurtbox_in_range: Area2D = null
var target: Node2D
@onready var attack_range: Area2D = $AttackRange
@onready var attack_range_shape: CollisionShape2D = $AttackRange/CollisionShape2D
# TODO: separation pouziva enemy-only manager. Ked vzniknu allied unity,
#       bude treba per-team separation manager (player units vs enemy units).
var enemy_manager: Node = null
@export var max_hp: int = 50
var hp: int

# animacia enemy
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: Control = $HealthBar
@onready var target_marker: Sprite2D = $TargetMarker
var last_direction := Vector2.DOWN

func _ready() -> void:
	hp = max_hp
	health_bar.init(max_hp, team)
	add_to_group("team_" + team)   # "team_player" alebo "team_enemy"
	BattleManager.register(self, team)
	attack_range.area_entered.connect(_on_attack_range_area_entered)
	attack_range.area_exited.connect(_on_attack_range_area_exited)

	var circle := attack_range_shape.shape.duplicate() as CircleShape2D
	circle.radius = aggro_range
	attack_range_shape.shape = circle

	# tap-to-target len pre enemy unity — hrac nesmie targetovat svojho ally
	if team == "enemy":
		$Hurtbox.input_pickable = true
		$Hurtbox.input_event.connect(_on_hurtbox_input_event)
		$Hurtbox.add_to_group("enemy_hurtbox")
	else:
		$Hurtbox.add_to_group("player_hurtbox")

# funkcie enemy
func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	attack_left = max(attack_left - delta , 0.0)

	if hurtbox_in_range != null and not is_instance_valid(hurtbox_in_range):
		hurtbox_in_range = null  # ciel bol freed bez area_exited — vycisti referenciu
	if hurtbox_in_range != null:
		# In melee range: stop moving. Attack tick still runs below.
		velocity = Vector2.ZERO
		update_idle_animation()   # ← drz poslednu smer animaciu pocas boja
	else:
		# 1) SEEK toward target
		var to_target: Vector2 = target.global_position - global_position
		var seek_dir: Vector2 = to_target.normalized()

		# 2) SEPARATION from other enemies
		sep_timer -= delta
		if sep_timer <= 0.0:
			sep_timer = separation_update_interval
			cached_sep = compute_separation()
		var sep: Vector2 = cached_sep

		# 3) Combine
		var steer: Vector2 = (seek_dir * seek_strength) + (sep * separation_strength)

		# fallback so they don't stop when steer is zero
		if steer.length() < 0.001:
			steer = seek_dir

		var direction: Vector2 = steer.normalized()

		last_direction = direction
		update_animation(direction)   # ← animuj pohyb

		velocity = direction * speed
		move_and_slide()

	if hurtbox_in_range != null and attack_left <= 0.0:
		if target != null and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(damage)
		attack_left = attack_cooldown

func compute_separation() -> Vector2:
	var result := Vector2.ZERO
	var count := 0
	var r2 := separation_radius * separation_radius
	
	# POZOR: toto je stale drahe, ale uz menej
	for e in enemy_manager.enemies:
		if e == self:
			continue
		var other := e as Node2D
		var diff := global_position - other.global_position
		var d2 := diff.length_squared()
		
		if d2 > 0.0 and d2 < r2:
			# 1/sqrt(d2) je stale sqrt; da sa zjednodusit
			# pre prototyp staci 1/d2 (lacnejsie), bude to trochu "tvrdsie"
			result += diff / d2
			count += 1
			if count >= max_neighbors:
				break
	
	if count > 0:
		result /= float(count)
	
	return result

func update_animation(direction: Vector2) -> void:
	# Rovnaka logika ako player.gd — 2 animacie podla dominantnej osi
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			sprite.play("new_back_right")  # pohyb vpravo
		else:
			sprite.play("new_front_left")  # pohyb vlavo
	else:
		if direction.y > 0:
			sprite.play("new_front_left")  # pohyb dole
		else:
			sprite.play("new_back_right")  # pohyb hore
			
func update_idle_animation() -> void:
	# Drz poslednu smer animaciu — rovnaka logika ako player.gd
	if abs(last_direction.x) > abs(last_direction.y):
		if last_direction.x > 0:
			sprite.play("new_back_right")
		else:
			sprite.play("new_front_left")
	else:
		if last_direction.y > 0:
			sprite.play("new_front_left")
		else:
			sprite.play("new_back_right")

func _on_attack_range_area_entered(area: Area2D) -> void:
	if hurtbox_in_range != null:
		return  # first contact wins — uz mam ciel

	# Postav nazvy nepriatelskych groupov dynamicky podla teamu
	var enemy_team := "player" if team == "enemy" else "enemy"
	var unit_group := enemy_team + "_hurtbox"
	var turret_group := enemy_team + "_turret_hurtbox"
	var base_group := enemy_team + "_base_hurtbox"

	var is_valid := false
	match target_filter:
		TargetFilter.ALL:
			is_valid = area.is_in_group(unit_group) or area.is_in_group(turret_group) or area.is_in_group(base_group)
		TargetFilter.UNITS_ONLY:
			is_valid = area.is_in_group(unit_group)
		TargetFilter.STRUCTURES_ONLY:
			is_valid = area.is_in_group(turret_group) or area.is_in_group(base_group)

	if is_valid:
		hurtbox_in_range = area

func _on_attack_range_area_exited(area: Area2D) -> void:
	if area == hurtbox_in_range or not is_instance_valid(hurtbox_in_range):
		hurtbox_in_range = null

# TODO: rovnaky pattern doplnit do turret.gd a base.gd ked dostanu svoje
#       hurtbox group assignments — tap na turret/base = set_primary_target
func _on_hurtbox_input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# najdi hraca v groupe a nastav primary_target
			var players := get_tree().get_nodes_in_group("team_player")
			for p in players:
				if p.has_method("set_primary_target"):
					p.set_primary_target(self)
			# nasledujuci release toho isteho tapnutia nesmie spustit tap-to-move v arena.gd
			InputR.suppress_release_of_touch(event.index)
		# spotrebuj press AJ release — inak release nad enemy spusti tap-to-move v arena.gd
		get_viewport().set_input_as_handled()

func set_targeted(state: bool) -> void:
	target_marker.visible = state

func take_damage(amount: int) -> void:
	hp -= amount
	health_bar.set_health(hp)
	if hp <= 0:
		queue_free()
