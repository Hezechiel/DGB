extends StaticBody2D

# Vezicka — staticka obrana. Strazi okolie (DetectionRange) a strieli
# LightningBolty na enemy v dosahu.
#
# Pozn.: AnimatedSprite2D.frame indexuje len v ramci AKTUALNEJ animacie,
# nie cely spritesheet. Damage stavy (riadok 1 sheetu) su preto 4 frames
# v animacii "damaged" a vyberaju sa cez .frame (0..3).
const FRAME_DESTROYED := 3 # row 1 col 3 — znicena vezicka (0% hp wreck)

# Emitovany raz z _on_destroyed() — LaneWaypoint strazeny touto vezickou si
# na tento signal navesi listener a stane sa neaktivnym (jednotky ho preskocia)
signal destroyed

@export var max_hp: int = 300
@export var aggro_range: float = 120.0        # detection radius in pixels
@export var fire_cooldown: float = 1.5      # seconds between shots
@export var projectile_damage: int = 20
@export var armor: float = 0.0              # flat damage reduction (0 = no armor)
@export var bolt_scene: PackedScene         # assign LightningBolt.tscn in Inspector
@export var target_group: String = "team_enemy" # which group this turret shoots at
@export var owner_team: String = "player"        # "player" or "enemy" — for BattleManager registration
@export var lane: String = "top"   # "top" alebo "bot" — pre BattleManager sledovanie pruhu

var hp: int
var fire_left: float = 0.0
var current_target: Node2D = null
var is_stunned: bool = false
var stun_timer: float = 0.0
var restore_hp_per_sec: float = 0.0         # set by repair abilities; 0 = no regen
var regen_buffer: float = 0.0               # zbiera zlomky HP (int heal by ich kazdy frame zahodil)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_range: Area2D = $AttackRange
@onready var attack_range_shape: CollisionShape2D = $AttackRange/CollisionShape2D
@onready var hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D

@onready var health_bar: Control = $HealthBar
@onready var target_marker: Sprite2D = $TargetMarker



func _ready() -> void:
	hp = max_hp
	health_bar.init(max_hp, owner_team)
	add_to_group("turrets")
	BattleManager.register(self, owner_team)
	BattleManager.register_turret(self, owner_team, lane)

	# tim podla vlastnika — pre targeting (find_nearest_enemy / detection groups)
	if owner_team == "player":
		add_to_group("team_player")
	else:
		add_to_group("team_enemy")

	# polomer detekcie podla exportu — duplicate, aby viac veziciek
	# nezdielalo jeden CircleShape2D resource
	var circle := attack_range_shape.shape.duplicate() as CircleShape2D
	circle.radius = aggro_range
	attack_range_shape.shape = circle

	attack_range.body_entered.connect(_on_body_entered)
	attack_range.body_exited.connect(_on_body_exited)

	# tap-to-target: len enemy struktury su tapable
	if owner_team == "enemy":
		$Hurtbox.input_pickable = true
		$Hurtbox.input_event.connect(_on_hurtbox_input_event)

	# priradenie hurtbox groupy pre dynamicky targeting filter v unit.gd
	$Hurtbox.add_to_group(owner_team + "_turret_hurtbox")

	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false
		return

	# regen (repair ability)
	if restore_hp_per_sec > 0.0:
		regen_buffer += restore_hp_per_sec * delta
		if regen_buffer >= 1.0:
			var whole := floorf(regen_buffer)
			regen_buffer -= whole
			heal(whole)

	fire_left = max(fire_left - delta, 0.0)

	# ciel mohol medzitym umriet / zmiznut zo stromu
	if current_target != null and not is_instance_valid(current_target):
		current_target = null

	if current_target != null and fire_left <= 0.0:
		_fire_at(current_target)
		fire_left = fire_cooldown


# =========================
# DAMAGE / HEAL / STUN
# =========================

func take_damage(amount: int) -> void:
	if hp <= 0:
		return # uz je to vrak

	var effective := maxi(1, amount - int(armor))
	hp -= effective

	health_bar.set_health(hp)

	if hp <= 0:
		_on_destroyed()
	else:
		_update_damage_visual()


func heal(amount: float) -> void:
	if hp <= 0:
		return # vrak sa regenom neopravuje (revive bude riesit ability)

	hp = mini(max_hp, hp + int(amount))
	health_bar.set_health(hp)
	_update_damage_visual()


func apply_stun(duration: float) -> void:
	is_stunned = true
	stun_timer = max(stun_timer, duration) # dlhsi stun vyhrava


# Vstupny bod pre nasilne prepisanie aggra (napr. buduci enemy hero pulluje
# aggro z vezicky): ked hero poskodi unit zatial co stoji v AttackRange danej
# vezicky, jeho attack-resolution kod zavola turret.taunt(self). Ziadny enemy
# hero zatial neexistuje — hook je len pripraveny.
func taunt(new_target: Node2D) -> void:
	# nasilu prepise aktualny aggro, aj ked uz mal vezicka zamknuty iny ciel
	current_target = new_target


# =========================
# FIRING
# =========================

func _fire_at(target: Node2D) -> void:
	if bolt_scene == null:
		push_error("Turret: bolt_scene nie je nastavene!")
		return

	var bolt := bolt_scene.instantiate()
	bolt.set("damage", projectile_damage)
	get_parent().add_child.call_deferred(bolt)
	bolt.call_deferred("setup", global_position, target)


# =========================
# TARGETING (tap-to-target)
# =========================

func set_targeted(state: bool) -> void:
	target_marker.visible = state

func _on_hurtbox_input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var players := get_tree().get_nodes_in_group("team_player")
			for p in players:
				if p.has_method("set_primary_target"):
					p.set_primary_target(self)
			# nasledujuci release toho isteho tapnutia nesmie spustit tap-to-move v arena.gd
			InputR.suppress_release_of_touch(event.index)
		# spotrebuj press AJ release — inak release nad turretom spusti tap-to-move v arena.gd
		get_viewport().set_input_as_handled()


# =========================
# VISUALS
# =========================

func _update_damage_visual() -> void:
	var ratio := float(hp) / float(max_hp)

	if ratio > 0.75:
		if sprite.animation != &"idle" or not sprite.is_playing():
			sprite.play("idle")
		return

	# staticky damage frame z riadku 1 (animacia "damaged")
	var col := 0
	if ratio <= 0.25:
		col = 2
	elif ratio <= 0.5:
		col = 1

	sprite.stop()
	sprite.animation = &"damaged"
	sprite.frame = col


func _on_destroyed() -> void:
	hp = 0
	health_bar.visible = false
	target_marker.visible = false
	# destroyed turret cannot remain targeted
	current_target = null

	sprite.stop()
	sprite.animation = &"damaged"
	sprite.frame = FRAME_DESTROYED

	# vrak ostava na mape len ako vizual — bez kolizie a detekcie
	$CollisionBody.set_deferred("disabled", true)
	attack_range_shape.set_deferred("disabled", true)
	# hurtbox tiez vypnut — inak unit v ENGAGING nikdy nedostane area_exited
	# a zostane navzdy zamknuty na vraku (ktory beztak neprijima damage)
	hurtbox_shape.set_deferred("disabled", true)
	remove_from_group("turrets")
	BattleManager.on_turret_destroyed(owner_team, lane)
	set_physics_process(false)
	destroyed.emit()


# =========================
# TARGETING
# =========================

func _on_body_entered(body: Node2D) -> void:
	if current_target == null and body.is_in_group(target_group):
		current_target = body

func _on_body_exited(body: Node2D) -> void:
	# ciel skutocne opustil AttackRange (podla fyziky, nie priblizneho vypoctu
	# vzdialenosti) — pusti ho, aby vezicka mohla zamknut dalsie telo v dosahu
	if body == current_target:
		current_target = null
