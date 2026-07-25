extends CharacterBody2D

# bojove vlastnosti hraca
@export var speed: float = 70.0
@export var max_hp: int = 500
var health_points: int

@export var invuln_time: float = 0.25 # (invulnerability window)
var invuln_left: float = 0.0

const PLAYER_HURTBOX_LAYER := 8   # zodpoveda layer_4 "player_hurtbox"
var is_dead := false

# vlastnosti Lightning projektilu
@export var bolt_scene: PackedScene
@export var fire_cooldown: float = 0.5
@export var attack_range: float = 80.0
@export var projectile_damage: int = 25
var fire_left: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var health_bar: Control = $HealthBar


var last_direction := Vector2.DOWN #default pozera dole

var primary_target: Node2D = null # manualny ciel (tap na enemy/turret/base)
var auto_target: Node2D = null # fallback ciel (najblizsi nepriatel v dosahu) — len na strielanie, bez chase

# HeroData pouzita pri configure() — zdielany resource, nikdy sa doň
# nezapisuje runtime stav (health_points a pod.)
var hero_data: HeroData = null

# Nastavi hrdinu podla HeroData PRED vstupom do stromu (spawn flow:
# instantiate → configure → add_child). Pouziva $AnimatedSprite2D priamo
# (nie @onready var sprite) — onready vary sa priradia az pri _ready().
func configure(data: HeroData, _new_team: String) -> void:
	hero_data = data
	# team ostava efektivne "player" pre lokalneho hrdinu — hardcoded team
	# stringy v _ready() (BattleManager.register(self, "player") atd.)
	# TODO: nahradit premennou team, ked pride multiplayer/sidekick
	max_hp = data.max_hp
	speed = data.speed
	attack_range = data.attack_range
	fire_cooldown = data.fire_cooldown
	projectile_damage = data.projectile_damage
	bolt_scene = data.projectile_scene
	if data.sprite_frames != null:
		$AnimatedSprite2D.sprite_frames = data.sprite_frames

func _ready() -> void:
	health_points = max_hp
	health_bar.init(max_hp, "player")
	add_to_group("team_player")
	add_to_group("heroes")
	BattleManager.register(self, "player")
	hurtbox.add_to_group("player_hurtbox")
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	HealingSystem.heal_instant.connect(_on_heal_instant)
	HealingSystem.heal_tick.connect(_on_heal_tick)
	HealingSystem.heal_ended.connect(_on_heal_ended)
	InputR.clear_move_target() # zmaz stary ciel po reloade sceny

func _physics_process(delta):
	invuln_left = max(invuln_left - delta, 0.0)
	fire_left = max(fire_left - delta, 0.0)

	# 1) pohyb — vzdy z tap-to-move; manualny ciel mimo dosahu prepise chase smerom k nemu
	var move_dir := get_move_input()

	# ciel ktory zomrel ale ostal v strome (hrdina caka na respawn, veza/baza
	# je vrak) nikdy nevystreli tree_exited — disengage treba rucne
	if primary_target != null and is_instance_valid(primary_target) \
			and "hp" in primary_target and primary_target.hp <= 0:
		_clear_primary_target()

	# 2) bojova logika — manualny ciel ma prednost, fallback na auto-target (bez chase)
	if primary_target != null and is_instance_valid(primary_target):
		var to_target := primary_target.global_position - global_position
		var dist_sq := to_target.length_squared()
		if dist_sq <= attack_range * attack_range:
			# v dosahu — strielaj
			_try_fire(primary_target)
		else:
			# mimo dosahu — chase (manualny ciel ma prioritu pred tap-to-move)
			move_dir = to_target.normalized()
	else:
		# ziadny manualny ciel — auto-target: strielaj na najblizsieho v dosahu, ale bez chase
		var nearest := find_nearest_enemy()
		_update_auto_target(nearest)
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
	# manualny a auto-target sa nesmu prekryvat — skry marker na auto-target, ak bezi
	if auto_target != null and is_instance_valid(auto_target) and auto_target.has_method("set_targeted"):
		auto_target.set_targeted(false)
	auto_target = null
	# skry marker na stary manualny ciel
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

func on_new_move_command() -> void:
	# hrac zadal novy tap-to-move — explicitny disengage od manualneho ciela
	_clear_primary_target()

func _update_auto_target(nearest: Node2D) -> void:
	# bez flickeru — marker sa prepne len ked sa auto-target skutocne zmeni
	if nearest == auto_target:
		return
	if auto_target != null and is_instance_valid(auto_target) and auto_target.has_method("set_targeted"):
		auto_target.set_targeted(false)
	auto_target = nearest
	if auto_target != null and auto_target.has_method("set_targeted"):
		auto_target.set_targeted(true)

func _try_fire(target: Node2D) -> void:
	if fire_left <= 0.0:
		last_direction = (target.global_position - global_position).normalized()
		fire_bolt(target)
		fire_left = fire_cooldown

func find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_d2 := attack_range * attack_range
	for child in get_tree().get_nodes_in_group("team_enemy"):
		if child == self:
			continue
		# vraky (znicene veze/zakladne) zostavaju v groupe, ale uz nie su ciel
		if "hp" in child and child.hp <= 0:
			continue
		if child is Node2D:
			var d2: float = child.global_position.distance_squared_to(global_position)
			if d2 <= nearest_d2:
				nearest_d2 = d2
				nearest = child
	return nearest

func take_damage(amount: int) -> void:
	if is_dead:
		return
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
		die()

# =========================
# HEALING (pody — HealingSystem)
# =========================

# HoT ticky su float zlomky (~0.33 HP/frame) a HP je int — bez akumulacie
# by sa kazdy tick zaokruhlil na nulu a HoT by nevyliecil NIC. Preto zvysok.
var _heal_accum: float = 0.0

func _on_heal_instant(heal_team: String, amount: float) -> void:
	if heal_team != "player" or is_dead:
		return
	health_points = clampi(health_points + int(round(amount)), 0, max_hp)
	health_bar.set_health(health_points)

func _on_heal_tick(heal_team: String, amount: float, remaining: float) -> void:
	if heal_team != "player" or is_dead:
		return
	_heal_accum += amount
	var whole := floori(_heal_accum)
	if whole > 0:
		_heal_accum -= float(whole)
		health_points = clampi(health_points + whole, 0, max_hp)
		health_bar.set_health(health_points)
	health_bar.set_pending_heal(remaining)

func _on_heal_ended(heal_team: String) -> void:
	if heal_team != "player":
		return
	_heal_accum = 0.0
	health_bar.set_pending_heal(0.0)

func die() -> void:
	if is_dead:
		return
	is_dead = true

	InputR.clear_move_target()
	_clear_primary_target()
	if auto_target != null and is_instance_valid(auto_target) and auto_target.has_method("set_targeted"):
		auto_target.set_targeted(false)
	auto_target = null

	set_physics_process(false)
	$CollisionBody.set_deferred("disabled", true)
	hurtbox.set_deferred("monitorable", false)
	hurtbox.set_deferred("collision_layer", 0)
	remove_from_group("team_player")

	BattleManager.unregister(self, "player")
	BattleManager.on_hero_died(self, "player")
	# smrt rusi aktivny HoT — heal_ended zhasne pending pas cez _on_heal_ended
	HealingSystem.cancel_heal("player")

	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("death"):
		sprite.play("death")
		await sprite.animation_finished
		if not is_dead:
			return  # revive() medzitym uz prebehlo
	visible = false

func revive() -> void:
	is_dead = false
	health_points = max_hp
	health_bar.set_health(health_points)
	visible = true
	$CollisionBody.set_deferred("disabled", false)
	hurtbox.set_deferred("monitorable", true)
	hurtbox.set_deferred("collision_layer", PLAYER_HURTBOX_LAYER)
	add_to_group("team_player")
	BattleManager.register(self, "player")
	set_physics_process(true)
	invuln_left = 1.0

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
