extends CharacterBody2D

# Placeholder enemy hero avatar — staticky hurtbox/vizualny ciel.
# ZIADNA AI, ZIADNY pohyb, ZIADNE utocenie. AI controller pride neskor.

const PLAYER_HURTBOX_LAYER := 8   # zodpoveda layer_4 "player_hurtbox"
const ENEMY_HURTBOX_LAYER := 16   # zodpoveda layer_5 "enemy_hurtbox"

@export var team: String = "enemy"
var hero_data: HeroData = null
var hp: int
var max_hp: int = 500
var is_dead := false

@onready var health_bar: Control = $HealthBar

# Nastavi hrdinu podla HeroData PRED vstupom do stromu (spawn flow:
# instantiate → configure → add_child). Pouziva $NodePath priamo, nie
# @onready vary — tie sa priradia az pri _ready(), ktory tu este neprebehol.
func configure(data: HeroData, new_team: String) -> void:
	hero_data = data
	team = new_team
	max_hp = data.max_hp
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

	$AnimatedSprite2D.play("new_front_left")

func _apply_hurtbox_layer() -> void:
	$Hurtbox.collision_layer = PLAYER_HURTBOX_LAYER if team == "player" else ENEMY_HURTBOX_LAYER

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
