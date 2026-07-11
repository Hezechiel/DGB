extends CharacterBody2D

# Fyzicke vrstvy hurtboxov (project.godot [layer_names]) — melee_unit.tscn je
# zdielany archetyp pre oba timy, takze spravnu vrstvu podla teamu treba
# dopocitat v runtime, nie ju bakovat v scene
const PLAYER_HURTBOX_LAYER := 8   # zodpoveda layer_4 "player_hurtbox"
const ENEMY_HURTBOX_LAYER := 16   # zodpoveda layer_5 "enemy_hurtbox"

# === TIM A CIELENIE ===
# team: "player" alebo "enemy" — riadi groupy, BattleManager registraciu a farbu health baru
@export var team: String = "enemy"

# Filter kto sa pocita ako platny ciel pri vstupe do attack range
# ALL = utoci na vsetky nepriatelske ciele (heroes, units, turrets, bases)
# UNITS_ONLY = utoci len na heroes a units (ignoruje struktury — napr. melee minion)
# STRUCTURES_ONLY = utoci len na turrety a bazy (napr. baranidlo / battering ram)
enum TargetFilter { ALL, UNITS_ONLY, STRUCTURES_ONLY }
@export var target_filter: TargetFilter = TargetFilter.ALL

# Stavovy automat pohybu
enum MarchState { MARCHING, CHASING, ENGAGING }
var march_state: MarchState = MarchState.MARCHING

# March ciel — najblizsia ziva struktura nepriatelskeho timu (veza alebo
# baza), refreshovana periodicky cez BattleManager.get_nearest_structure()
# namiesto pevneho pola waypointov (jednotky teraz mozu byt nasadene
# kdekolvek na mape cez drag-to-deploy)
var structure_target: Node2D = null

# ako casto sa march ciel prekontroluje/refreshne — nie kazdy physics frame
# (rovnaky pattern ako separation_update_interval/sep_timer nizsie)
const TARGET_CHECK_INTERVAL: float = 0.4
var target_check_timer: float = 0.0

# Pohyb enemy po mape
@export var speed: float = 35.0
@export var separation_radius: float = 5.0
@export var separation_strength: float = 1.3
@export var separation_update_interval: float = 0.10
var sep_timer: float = 0.0
var cached_sep: Vector2 = Vector2.ZERO
# Ak sa budú "rozliezať" príliš do strán, zníž separation_strength.
# Ak sa stále zlepia, zvýš separation_radius (10.0 az 14.0) alebo strength (1.0 až 2.0).
@export var seek_strength: float = 1.0
@export var max_neighbors: int = 8

# bojove vlastnosti nepriatela
@export var damage: int = 10
@export var attack_cooldown: float = 1.2
var attack_left: float = 0.0
var hurtbox_in_range: Area2D = null
@onready var attack_range: Area2D = $AttackRange

# AggroRange — sirsia detekcia nez melee AttackRange; vsimne si nepriatelsku
# unit a zacne ju prenasledovat este pred fyzickym kontaktom (CHASING stav)
var combat_target: Node2D = null
@onready var aggro_range: Area2D = $AggroRange
# TODO: separation pouziva vsetky unity rovnakeho timu — compute_separation()
#       bude treba prepnut na get_tree().get_nodes_in_group("team_" + team)
#       namiesto enemy_manager.enemies ked su oba timy aktivne
var _separation_group: String = ""
@export var max_hp: int = 50
var hp: int

# UnitData pouzita pri configure() — zdielany resource, nikdy sa doň
# nezapisuje runtime stav (hp a pod.)
var unit_data: UnitData = null

# animacia enemy
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: Control = $HealthBar
@onready var target_marker: Sprite2D = $TargetMarker
var last_direction := Vector2.DOWN

# Nastavi jednotku podla UnitData PRED vstupom do stromu (spawn flow:
# instantiate → configure → add_child). Pouziva $AnimatedSprite2D priamo
# (nie @onready var sprite) — onready vary sa priradia az pri _ready(),
# ktory v tomto bode este neprebehol.
func configure(data: UnitData, new_team: String) -> void:
	unit_data = data
	team = new_team
	max_hp = data.max_hp
	damage = data.damage
	attack_cooldown = data.attack_cooldown
	speed = data.speed
	target_filter = data.target_filter # int -> enum, hodnoty su zdielane 1:1
	if data.sprite_frames != null:
		$AnimatedSprite2D.sprite_frames = data.sprite_frames

func _ready() -> void:
	hp = max_hp
	health_bar.init(max_hp, team)

	# melee_unit.tscn je zdielany archetyp pre oba timy — spravne fyzicke
	# vrstvy podla teamu treba dopocitat tu, nie spoliehat sa na staticke
	# hodnoty zo sceny
	$Hurtbox.collision_layer = PLAYER_HURTBOX_LAYER if team == "player" else ENEMY_HURTBOX_LAYER
	attack_range.collision_mask = ENEMY_HURTBOX_LAYER if team == "player" else PLAYER_HURTBOX_LAYER

	add_to_group("team_" + team)   # "team_player" alebo "team_enemy"
	BattleManager.register(self, team)
	attack_range.area_entered.connect(_on_attack_range_area_entered)
	attack_range.area_exited.connect(_on_attack_range_area_exited)

	# rovnaky team-podla-masky vypocet ako attack_range vyssie; ziadny
	# area_exited pripojeny — chase je zatial indefinitny (leash pride neskor)
	aggro_range.collision_mask = ENEMY_HURTBOX_LAYER if team == "player" else PLAYER_HURTBOX_LAYER
	aggro_range.area_entered.connect(_on_aggro_range_area_entered)

	# tap-to-target len pre enemy unity — hrac nesmie targetovat svojho ally
	if team == "enemy":
		$Hurtbox.input_pickable = true
		$Hurtbox.input_event.connect(_on_hurtbox_input_event)
		$Hurtbox.add_to_group("enemy_hurtbox")
	else:
		$Hurtbox.add_to_group("player_hurtbox")

func _physics_process(delta: float) -> void:
	attack_left = max(attack_left - delta, 0.0)

	# validacia hurtbox_in_range — area mohla byt freed bez area_exited
	if hurtbox_in_range != null and not is_instance_valid(hurtbox_in_range):
		hurtbox_in_range = null
	# ak ciel prave zomrel/zmizol, preskenuj co uz prekryva AttackRange —
	# first-contact-wins v _on_attack_range_area_entered znamena, ze druha
	# (uz prekryvajuca sa) area nikdy nedostane vlastny signal
	if hurtbox_in_range == null:
		_reacquire_attack_target()

	# validacia combat_target — area_exited nie je pripojeny (indefinitny chase),
	# takze mrtvy/freed ciel treba odchytit rucne
	if combat_target != null and not is_instance_valid(combat_target):
		combat_target = null
	# rovnaky dovod ako vyssie — dalsia unit uz stojaca v AggroRange sa inak
	# nikdy nezachyti a jednotka by sa vratila rovno do MARCHING
	if combat_target == null:
		_reacquire_combat_target()

	# priorita stavu: melee kontakt > chase na dialku > march k strukture
	if hurtbox_in_range != null:
		march_state = MarchState.ENGAGING
	elif combat_target != null:
		march_state = MarchState.CHASING
	else:
		march_state = MarchState.MARCHING

	match march_state:
		MarchState.MARCHING:
			_process_marching(delta)
		MarchState.CHASING:
			_process_chasing(delta)
		MarchState.ENGAGING:
			_process_engaging()

func _process_marching(delta: float) -> void:
	_update_structure_target(delta)

	if structure_target == null:
		velocity = Vector2.ZERO
		update_idle_animation()
		return

	_steer_towards(structure_target.global_position, delta)


# Prekontroluje/refreshne march ciel v pravidelnom intervale namiesto kazdy
# frame (rovnaky pattern ako sep_timer/cached_sep v _steer_towards nizsie).
# Ak je aktualny ciel stale ziva platna struktura, ponecha ho — inak sa
# spyta BattleManager na najblizsiu zivu strukturu nepriatelskeho timu.
func _update_structure_target(delta: float) -> void:
	target_check_timer -= delta
	if target_check_timer > 0.0:
		return
	target_check_timer = TARGET_CHECK_INTERVAL

	if structure_target != null and is_instance_valid(structure_target) and structure_target.hp > 0:
		return

	var enemy_team := "player" if team == "enemy" else "enemy"
	structure_target = BattleManager.get_nearest_structure(enemy_team, global_position)


# CHASING — unit si vsimla nepriatelsku unit v AggroRange, prenasleduje ju
# rovnakym steeringom ako march (bez samostatnej logiky navyse)
func _process_chasing(delta: float) -> void:
	_steer_towards(combat_target.global_position, delta)


# Spolocny seek+separation steering krok — pouzity pre march k waypointu
# aj pre march priamo k final targetu (fallback ked nezostanu waypointy)
func _steer_towards(target_pos: Vector2, delta: float) -> void:
	var to_target: Vector2 = target_pos - global_position

	# separation od rovnakych unity (zachovana z povodneho kodu)
	sep_timer -= delta
	if sep_timer <= 0.0:
		sep_timer = separation_update_interval
		cached_sep = compute_separation()

	var seek_dir: Vector2 = to_target.normalized()
	var steer: Vector2 = (seek_dir * seek_strength) + (cached_sep * separation_strength)
	if steer.length() < 0.001:
		steer = seek_dir

	var direction: Vector2 = steer.normalized()
	last_direction = direction
	update_animation(direction)
	velocity = direction * speed
	move_and_slide()

func _process_engaging() -> void:
	# stoj a utocaj — pohyb zastaveny
	velocity = Vector2.ZERO
	update_idle_animation()
	move_and_slide()

	if attack_left <= 0.0:
		# ziskaj rodicovsky node z hurtboxu — hurtbox je child bojujuceho nodu
		var attack_target := hurtbox_in_range.get_parent() as Node2D
		if attack_target != null and is_instance_valid(attack_target) and attack_target.has_method("take_damage"):
			attack_target.take_damage(damage)
		attack_left = attack_cooldown

func compute_separation() -> Vector2:
	var result := Vector2.ZERO
	var count := 0
	var r2 := separation_radius * separation_radius
	# pouzij group namiesto enemy_manager pre kompatibilitu s oboma timami
	for e in get_tree().get_nodes_in_group("team_" + team):
		if e == self:
			continue
		var other := e as Node2D
		if other == null:
			continue
		var diff := global_position - other.global_position
		var d2 := diff.length_squared()
		if d2 > 0.0 and d2 < r2:
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
			sprite.play("idle")  # pohyb vpravo
			sprite.flip_h = true
		else:
			sprite.play("idle")  # pohyb vlavo
			sprite.flip_h = false
	else:
		if direction.y > 0:
			sprite.play("idle")  # pohyb dole
			sprite.flip_h = false
		else:
			sprite.play("idle")  # pohyb hore
			sprite.flip_h = true

func update_idle_animation() -> void:
	# Drz poslednu smer animaciu — rovnaka logika ako player.gd
	if abs(last_direction.x) > abs(last_direction.y):
		if last_direction.x > 0:
			sprite.play("idle")  # pohyb vpravo
			sprite.flip_h = true
		else:
			sprite.play("idle")  # pohyb vlavo
			sprite.flip_h = false
	else:
		if last_direction.y > 0:
			sprite.play("idle")  # pohyb dole
			sprite.flip_h = false
		else:
			sprite.play("idle")  # pohyb hore
			sprite.flip_h = true

# Zdielana predikat-logika pre AttackRange — pouzita v _on_attack_range_area_entered
# aj v _reacquire_attack_target(), aby obe cesty zhodnotili area rovnako
func _is_valid_attack_target(area: Area2D) -> bool:
	# Postav nazvy nepriatelskych groupov dynamicky podla teamu
	var enemy_team := "player" if team == "enemy" else "enemy"
	var unit_group := enemy_team + "_hurtbox"
	var turret_group := enemy_team + "_turret_hurtbox"
	var base_group := enemy_team + "_base_hurtbox"

	match target_filter:
		TargetFilter.ALL:
			return area.is_in_group(unit_group) or area.is_in_group(turret_group) or area.is_in_group(base_group)
		TargetFilter.UNITS_ONLY:
			return area.is_in_group(unit_group)
		TargetFilter.STRUCTURES_ONLY:
			return area.is_in_group(turret_group) or area.is_in_group(base_group)
	return false

func _on_attack_range_area_entered(area: Area2D) -> void:
	if hurtbox_in_range != null:
		return  # first contact wins — uz mam ciel
	if _is_valid_attack_target(area):
		hurtbox_in_range = area

func _on_attack_range_area_exited(area: Area2D) -> void:
	if area == hurtbox_in_range or not is_instance_valid(hurtbox_in_range):
		hurtbox_in_range = null

# Preskenuje aktualne prekryvy AttackRange ked hurtbox_in_range zostane null
# (napr. predchadzajuci ciel prave zomrel) — first-contact-wins v entered
# handleri inak necha uz prekryvajuce sa arey navzdy nepovsimnute
func _reacquire_attack_target() -> void:
	for area in attack_range.get_overlapping_areas():
		if _is_valid_attack_target(area):
			hurtbox_in_range = area
			return

# AggroRange ignoruje struktury uplne (bez ohladu na target_filter) — len
# nepriatelske unit hurtboxy spustaju chase.
func _is_valid_aggro_target(area: Area2D) -> bool:
	var enemy_team := "player" if team == "enemy" else "enemy"
	return area.is_in_group(enemy_team + "_hurtbox")

# Ziadny area_exited handler: raz zamknuty ciel sa neopusti (leash pride
# az so summon-from-hand poolom)
func _on_aggro_range_area_entered(area: Area2D) -> void:
	if combat_target != null:
		return  # first contact wins — uz mam ciel
	if _is_valid_aggro_target(area):
		combat_target = area.get_parent() as Node2D

# Rovnaky dovod ako _reacquire_attack_target() — ked predchadzajuci
# combat_target zomrie, dalsia unit uz stojaca v AggroRange sa inak nikdy
# nezachyti (nedostane vlastny area_entered) a jednotka by spadla do MARCHING
func _reacquire_combat_target() -> void:
	for area in aggro_range.get_overlapping_areas():
		if _is_valid_aggro_target(area):
			combat_target = area.get_parent() as Node2D
			return

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
