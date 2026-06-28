extends StaticBody2D

# Command Post — hlavny ciel zapasu. Nezranitelna kym aspon jeden pruh
# vlastnych vez nie je plne vycisteny. Po zniceni emituje (cez BattleManager)
# koniec zapasu. Vrak (jako veze) sa neodstranuje — len vizual + vypnuta kolizia.

@export var max_hp: int = 3000
@export var owner_team: String = "player"

# Zakladna je nezranitelna kym nie je aspon jeden pruh plne vycisteny
var is_vulnerable: bool = false
var hp: int

# Snimky z riadku 1 spritesheet-u (animacia "damaged")
# riadok 0 = idle (4 snimky), riadok 1 = poskodenie (4 snimky)
const FRAME_DAMAGED_90 := 0  # pod 90% HP
const FRAME_DAMAGED_75 := 1  # pod 75% HP
const FRAME_DAMAGED_50 := 2  # pod 50% HP
const FRAME_DAMAGED_25 := 3  # pod 25% HP
const FRAME_DESTROYED  := 4  # znicena zakladna

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: Control = $HealthBar
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var target_marker: Sprite2D = $TargetMarker


func _ready() -> void:
	hp = max_hp
	health_bar.init(max_hp, owner_team)
	# Zakladna je vzdy viditelna — hlavny ciel zapasu
	health_bar.always_visible = true
	BattleManager.register_base(self, owner_team)
	add_to_group(owner_team + "_base")   # "player_base" alebo "enemy_base"
	# tap-to-target: len enemy zakladna je tapable
	if owner_team == "enemy":
		$Hurtbox.input_pickable = true
		$Hurtbox.input_event.connect(_on_hurtbox_input_event)

	# priradenie hurtbox groupy pre dynamicky targeting filter v unit.gd
	$Hurtbox.add_to_group(owner_team + "_base_hurtbox")

	sprite.play(&"idle")


func take_damage(amount: int) -> void:
	if not is_vulnerable:
		return
	hp = maxi(hp - amount, 0)
	health_bar.set_health(hp)
	_update_damage_visual()
	if hp <= 0:
		_on_destroyed()


func set_vulnerable() -> void:
	is_vulnerable = true
	# TODO: pridat vizualny signal ze zakladna je teraz zranitelna (bliknutie, efekt)


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
		# spotrebuj press AJ release — inak release nad bazou spusti tap-to-move v arena.gd
		get_viewport().set_input_as_handled()


func _update_damage_visual() -> void:
	var ratio := float(hp) / float(max_hp)
	if ratio > 0.90:
		return   # idle animacia pokracuje normalne
	sprite.stop()
	sprite.animation = &"damaged"
	if ratio > 0.75:
		sprite.frame = FRAME_DAMAGED_90
	elif ratio > 0.50:
		sprite.frame = FRAME_DAMAGED_75
	elif ratio > 0.25:
		sprite.frame = FRAME_DAMAGED_50
	else:
		sprite.frame = FRAME_DAMAGED_25


func _on_destroyed() -> void:
	hp = 0
	health_bar.visible = false
	target_marker.visible = false
	sprite.stop()
	sprite.animation = &"damaged"
	sprite.frame = FRAME_DESTROYED
	collision_shape.set_deferred("disabled", true)
	hurtbox_shape.set_deferred("disabled", true)
	BattleManager.on_base_destroyed(owner_team)
