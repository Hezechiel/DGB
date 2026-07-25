extends CharacterBody2D

# AI hero avatar — pohyb/targeting/heal-seek (karty/energia AI pride neskor).
# March k najblizsej nepriatelskej strukture; pri nizkom HP (HeroAI hysteresis)
# hlada ready healing pod (vlastna strana ma prednost), inak ustupuje k spawnu.
# Strelba na najblizsi ciel v attack_range bezi nezavisle od stavu.

const PLAYER_HURTBOX_LAYER := 8   # zodpoveda layer_4 "player_hurtbox"
const ENEMY_HURTBOX_LAYER := 16   # zodpoveda layer_5 "enemy_hurtbox"

@export var team: String = "enemy"
var hero_data: HeroData = null
var hp: int
var max_hp: int = 500
var is_dead := false

# bojove vlastnosti — portovane z player.gd, generalizovane pre oba timy
@export var speed: float = 70.0
@export var attack_range: float = 80.0
@export var fire_cooldown: float = 0.5
@export var projectile_damage: int = 25
@export var bolt_scene: PackedScene
var fire_left: float = 0.0
var last_direction := Vector2.DOWN

# Pohybove ciele — refresh v intervale (unit.gd pattern), nie kazdy frame
var structure_target: Node2D = null  # NORMAL stav
var heal_target: Node2D = null       # LOW_HP stav
var target_check_timer: float = 0.0
const TARGET_CHECK_INTERVAL := 0.4
# int, nie HeroAI.State — autoload meno nie je class_name, takze sa neda
# pouzit v type anotacii (enum hodnoty su aj tak int)
var _prev_hp_state: int = HeroAI.State.NORMAL

@onready var health_bar: Control = $HealthBar
@onready var target_marker: Sprite2D = $TargetMarker

# Nastavi hrdinu podla HeroData PRED vstupom do stromu (spawn flow:
# instantiate → configure → add_child). Pouziva $NodePath priamo, nie
# @onready vary — tie sa priradia az pri _ready(), ktory tu este neprebehol.
func configure(data: HeroData, new_team: String) -> void:
	hero_data = data
	team = new_team
	max_hp = data.max_hp
	speed = data.speed
	attack_range = data.attack_range
	fire_cooldown = data.fire_cooldown
	projectile_damage = data.projectile_damage
	bolt_scene = data.projectile_scene
	if data.sprite_frames != null:
		$AnimatedSprite2D.sprite_frames = data.sprite_frames

func _ready() -> void:
	hp = max_hp
	health_bar.init(max_hp, team)
	add_to_group("team_" + team)
	add_to_group("heroes")
	BattleManager.register(self, team)

	_apply_hurtbox_layer()
	if team == "enemy":
		$Hurtbox.input_pickable = true
		$Hurtbox.input_event.connect(_on_hurtbox_input_event)
		$Hurtbox.add_to_group("enemy_hurtbox")
	else:
		$Hurtbox.add_to_group("player_hurtbox")

	HealingSystem.heal_instant.connect(_on_heal_instant)
	HealingSystem.heal_tick.connect(_on_heal_tick)
	HealingSystem.heal_ended.connect(_on_heal_ended)

	# melee_unit.tscn skryva marker priamo v scene (visible = false);
	# hero_dummy.tscn to nema, tak ho skryjeme tu
	target_marker.visible = false

	$AnimatedSprite2D.play("new_front_left")

func _apply_hurtbox_layer() -> void:
	$Hurtbox.collision_layer = PLAYER_HURTBOX_LAYER if team == "player" else ENEMY_HURTBOX_LAYER

# =========================
# AI POHYB A CIELENIE
# =========================

func _physics_process(delta: float) -> void:
	fire_left = maxf(fire_left - delta, 0.0)

	var hp_pct := float(hp) / float(max_hp)
	var hp_state := HeroAI.get_hp_state(team, hp_pct)
	if hp_state != _prev_hp_state:
		_prev_hp_state = hp_state
		target_check_timer = 0.0  # novy stav = okamzity re-query ciela

	# if/elif namiesto match — HeroAI.State.X cez autoload instanciu nie je
	# konstantny vyraz pre match pattern (autoload nema class_name)
	if hp_state == HeroAI.State.LOW_HP:
		structure_target = null  # zahod staru NORMAL cache
		_update_heal_target(delta)
		if heal_target != null and is_instance_valid(heal_target):
			# dojdenie na pod spusti existujuci area_entered heal
			# automaticky — ziadne explicitne "use pod" volanie
			_steer_towards(heal_target.global_position)
		else:
			# ziadny ready pod nikde — ustup k vlastnemu spawnu
			var retreat: Vector2 = BattleManager.hero_spawn_positions.get(team, global_position)
			if global_position.distance_squared_to(retreat) <= 8.0 * 8.0:
				_stand_idle()
			else:
				_steer_towards(retreat)
	else:
		heal_target = null  # zahod staru LOW_HP cache
		_update_structure_target(delta)
		if structure_target != null:
			# zrkadli player.gd primary-target logiku — v dosahu stoj
			# a strielaj (fire krok nizsie), mimo dosahu chase
			var d2 := global_position.distance_squared_to(structure_target.global_position)
			if d2 <= attack_range * attack_range:
				_stand_idle()
			else:
				_steer_towards(structure_target.global_position)
		else:
			_stand_idle()

	# strelba NEZAVISLE od hp stavu (zrkadli player.gd auto_target fallback)
	var nearest := find_nearest_enemy()
	if nearest != null:
		_try_fire(nearest)

# Prekontroluje/refreshne march ciel v pravidelnom intervale (unit.gd pattern).
# Ak je aktualny ciel stale ziva platna struktura, ponecha ho.
func _update_structure_target(delta: float) -> void:
	target_check_timer -= delta
	if target_check_timer > 0.0:
		return
	target_check_timer = TARGET_CHECK_INTERVAL

	if structure_target != null and is_instance_valid(structure_target) and structure_target.hp > 0:
		return

	var enemy_team := "player" if team == "enemy" else "enemy"
	structure_target = BattleManager.get_nearest_structure(enemy_team, global_position)

# Rovnaky interval gate — ready pod drzi az kym nie je pouzity/freed
# (ziadne prepinanie cielov v polovici cesty).
func _update_heal_target(delta: float) -> void:
	target_check_timer -= delta
	if target_check_timer > 0.0:
		return
	target_check_timer = TARGET_CHECK_INTERVAL

	if heal_target != null and is_instance_valid(heal_target) \
			and HealingSystem.is_pod_ready(StringName(heal_target.name)):
		return

	heal_target = BattleManager.get_nearest_ready_healing_pod(team, global_position)

# Single-hero steering — ZIADNA separation/neighbor logika (to je unit.gd
# vec pre squady, nie pre osamoteneho hrdinu)
func _steer_towards(target_pos: Vector2) -> void:
	var dir := (target_pos - global_position).normalized()
	last_direction = dir
	update_animation(dir)
	velocity = dir * speed
	move_and_slide()

func _stand_idle() -> void:
	velocity = Vector2.ZERO
	update_idle_animation()

# =========================
# FIGHTING LOGIC (port z player.gd, generalizovany team)
# =========================

func find_nearest_enemy() -> Node2D:
	var enemy_team := "player" if team == "enemy" else "enemy"
	var nearest: Node2D = null
	var nearest_d2 := attack_range * attack_range
	for child in get_tree().get_nodes_in_group("team_" + enemy_team):
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

func _try_fire(target: Node2D) -> void:
	if fire_left <= 0.0:
		last_direction = (target.global_position - global_position).normalized()
		fire_bolt(target)
		fire_left = fire_cooldown

func fire_bolt(target: Node2D) -> void:
	if bolt_scene == null:
		push_error("HeroDummy: bolt_scene nie je nastavene!")
		return

	var bolt := bolt_scene.instantiate()
	bolt.set("damage", projectile_damage)
	get_parent().add_child.call_deferred(bolt)
	bolt.call_deferred("setup", global_position, target)

# =========================
# ANIMATION LOGIC (port z player.gd)
# =========================

func update_animation(direction: Vector2) -> void:
	# Porovname absolutne hodnoty osi
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			$AnimatedSprite2D.play("new_back_right") #RIGHT
		else:
			$AnimatedSprite2D.play("new_front_left") #LEFT
	else:
		if direction.y > 0:
			$AnimatedSprite2D.play("new_front_left") #DOWN
		else:
			$AnimatedSprite2D.play("new_back_right") #UP

func update_idle_animation() -> void:
	if abs(last_direction.x) > abs(last_direction.y):
		if last_direction.x > 0:
			$AnimatedSprite2D.play("new_back_right") #RIGHT
		else:
			$AnimatedSprite2D.play("new_front_left") #LEFT
	else:
		if last_direction.y > 0:
			$AnimatedSprite2D.play("new_front_left") #DOWN
		else:
			$AnimatedSprite2D.play("new_back_right") #UP

# Rovnaky pattern ako unit.gd — player.gd vola set_targeted(true/false)
# pri zamknuti/odomknuti primary_target
func set_targeted(state: bool) -> void:
	target_marker.visible = state

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	health_bar.set_health(hp)
	if hp <= 0:
		die()

# HoT ticky su float zlomky (~0.33 HP/frame) a HP je int — bez akumulacie
# by sa kazdy tick zaokruhlil na nulu a HoT by nevyliecil NIC. Preto zvysok.
# (heal_team, nie team — parameter by tienil clenskú premennu team)
var _heal_accum: float = 0.0

func _on_heal_instant(heal_team: String, amount: float) -> void:
	if heal_team != team or is_dead:
		return
	hp = clampi(hp + int(round(amount)), 0, max_hp)
	health_bar.set_health(hp)

func _on_heal_tick(heal_team: String, amount: float, remaining: float) -> void:
	if heal_team != team or is_dead:
		return
	_heal_accum += amount
	var whole := floori(_heal_accum)
	if whole > 0:
		_heal_accum -= float(whole)
		hp = clampi(hp + whole, 0, max_hp)
		health_bar.set_health(hp)
	health_bar.set_pending_heal(remaining)

func _on_heal_ended(heal_team: String) -> void:
	if heal_team != team:
		return
	_heal_accum = 0.0
	health_bar.set_pending_heal(0.0)

func die() -> void:
	if is_dead:
		return
	is_dead = true

	set_physics_process(false)
	target_marker.visible = false  # mrtvy hrdina nesmie drzat viditelny marker
	$CollisionBody.set_deferred("disabled", true)
	$Hurtbox.set_deferred("monitorable", false)
	$Hurtbox.set_deferred("collision_layer", 0)
	remove_from_group("team_" + team)

	BattleManager.unregister(self, team)
	BattleManager.on_hero_died(self, team)
	# smrt rusi aktivny HoT — heal_ended zhasne pending pas cez _on_heal_ended
	HealingSystem.cancel_heal(team)

	if $AnimatedSprite2D.sprite_frames != null and $AnimatedSprite2D.sprite_frames.has_animation("death"):
		$AnimatedSprite2D.play("death")
		await $AnimatedSprite2D.animation_finished
		if not is_dead:
			return  # revive() medzitym uz prebehlo
	visible = false

func revive() -> void:
	is_dead = false
	hp = max_hp
	health_bar.set_health(hp)
	visible = true
	$CollisionBody.set_deferred("disabled", false)
	$Hurtbox.set_deferred("monitorable", true)
	_apply_hurtbox_layer()
	add_to_group("team_" + team)
	BattleManager.register(self, team)
	set_physics_process(true)
	# cerstvy spawn nesmie mierit na staru cache
	last_direction = Vector2.DOWN
	structure_target = null
	heal_target = null
	$AnimatedSprite2D.play("new_front_left")

func _on_hurtbox_input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var players := get_tree().get_nodes_in_group("team_player")
			for p in players:
				if p.has_method("set_primary_target"):
					p.set_primary_target(self)
			InputR.suppress_release_of_touch(event.index)
		get_viewport().set_input_as_handled()
