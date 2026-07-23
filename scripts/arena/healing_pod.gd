extends Area2D

# Healing pod (SWFA styl) — staticky pickup pre HRDINOV oboch timov (ziadny
# team-lock, jednotky nikdy). Casovanie/cooldowny zije v HealingSystem
# (autoload, server-side stav) — tento node je len senzor + vizual.

@export var initial_delay: float = 30.0
@export var respawn_cooldown: float = 20.0
@export var instant_heal_amount: float = 40.0
@export var hot_total_amount: float = 120.0
@export var hot_duration: float = 6.0
@export var single_use: bool = false   # pre buduce prenosne/sumonovane pody

const TEX_ACTIVE := preload("res://assets/world/pod_active.png")
const TEX_INACTIVE := preload("res://assets/world/pod_inactive.png")

@onready var sprite: Sprite2D = $Sprite2D

var _pod_id: StringName

func _ready() -> void:
	_pod_id = StringName(name)  # meno nodu v scene = unikatne id podu
	HealingSystem.register_pod(_pod_id, initial_delay, respawn_cooldown)
	HealingSystem.pod_ready.connect(_on_pod_ready)
	_set_active(false)
	monitoring = false
	area_entered.connect(_on_area_entered)

func _on_pod_ready(pod_id: StringName) -> void:
	if pod_id != _pod_id:
		return
	_set_active(true)
	monitoring = true

func _on_area_entered(area: Area2D) -> void:
	if not HealingSystem.is_pod_ready(_pod_id):
		return
	# team podla group na hurtboxe (nastavuju hero skripty vo svojom _ready()),
	# nie podla layer cisla — pod nemusi vediet o bitoch
	var team := ""
	if area.is_in_group("player_hurtbox"):
		team = "player"
	elif area.is_in_group("enemy_hurtbox"):
		team = "enemy"
	if team == "":
		return  # nie je hero hurtbox — collision_mask by to nemal pustit, guard aj tak

	HealingSystem.trigger_heal(team, instant_heal_amount, hot_total_amount, hot_duration)

	if single_use:
		# TODO(portable pods): buduce hero-sumonovane pody su na jedno pouzitie —
		# queue_free() namiesto cooldownu. Zatial nenapojene na ziadnu ability;
		# BattleManager.spawn_healing_pod() stub existuje.
		queue_free()
		return

	HealingSystem.consume_pod(_pod_id)
	_set_active(false)
	# set_deferred — sme vnutri area_entered (physics flush), priamy zapis
	# do monitoring je v Godot 4 error
	set_deferred("monitoring", false)

func _set_active(is_active: bool) -> void:
	sprite.texture = TEX_ACTIVE if is_active else TEX_INACTIVE
