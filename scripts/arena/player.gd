extends CharacterBody2D

# bojove vlastnosti hraca
@export var speed: float = 70.0
@export var max_hp: int = 500
var health_points: int

@export var invuln_time: float = 0.25 # (invulnerability window)
var invuln_left: float = 0.0

# === STATUS EFEKTY (spells) === identicke s unit.gd/hero_dummy.gd — ZAMERNA
# duplikacia, ziadna zdielana base class (architecture.md princip). Dlhsie
# trvanie vzdy vyhrava (maxf), nikdy sa nestackuje ani neskracuje.
var stun_left: float = 0.0
var root_left: float = 0.0
var slow_left: float = 0.0
var slow_multiplier: float = 1.0

func apply_stun(duration: float) -> void:
	stun_left = maxf(stun_left, duration)
	if is_attacking:
		_cancel_attack_windup()

func apply_root(duration: float) -> void:
	root_left = maxf(root_left, duration)

func apply_slow(multiplier: float, duration: float) -> void:
	slow_multiplier = multiplier
	slow_left = maxf(slow_left, duration)

const PLAYER_HURTBOX_LAYER := 8   # zodpoveda layer_4 "player_hurtbox"
const ENEMY_HURTBOX_LAYER := 16   # zodpoveda layer_5 "enemy_hurtbox"
var is_dead := false

# vlastnosti Lightning projektilu
@export var bolt_scene: PackedScene
@export var recovery_time: float = 0.4
@export var attack_range: float = 80.0
@export var projectile_damage: int = 25
var fire_left: float = 0.0

var attack_type: HeroData.AttackType = HeroData.AttackType.RANGED
var can_move_while_attacking: bool = false
var is_attacking: bool = false
var damage_point_ratio: float = 0.7
var _attacking_target: Node2D = null
var _attack_id: int = 0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var health_bar: Control = $HealthBar
@onready var attack_range_area: Area2D = $AttackRange


var last_direction := Vector2.DOWN #default pozera dole

var primary_target: Node2D = null # manualny ciel (tap na enemy/turret/base)
var auto_target: Node2D = null # fallback ciel (najblizsi nepriatel v dosahu) — len na strielanie, bez chase

# Hurtbox areas z nepriatelskeho timu prave prekryvajuce AttackRange —
# zdroj pravdy pre "je X v dosahu", nahradza stary center-to-center
# distance check (ktory zlyhaval na velkych cieloch ako veze/zakladne,
# kde kolizia hrdinovi nikdy nedovoli priblizit sa na center-distance
# <= attack_range). Rovnaky vzor ako unit.gd's hurtbox_in_range.
var _range_areas: Array[Area2D] = []

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
	$AttackRange/CollisionShape2D.shape.radius = data.attack_range
	recovery_time = data.recovery_time
	damage_point_ratio = data.damage_point_ratio
	projectile_damage = data.projectile_damage
	bolt_scene = data.projectile_scene
	attack_type = data.attack_type
	can_move_while_attacking = data.can_move_while_attacking
	if data.sprite_frames != null:
		$AnimatedSprite2D.sprite_frames = data.sprite_frames

func _ready() -> void:
	health_points = max_hp
	health_bar.init(max_hp, "player")
	add_to_group("team_player")
	add_to_group("heroes")
	BattleManager.register(self, "player")
	hurtbox.add_to_group("player_hurtbox")
	attack_range_area.collision_mask = ENEMY_HURTBOX_LAYER
	attack_range_area.area_entered.connect(_on_attack_range_area_entered)
	attack_range_area.area_exited.connect(_on_attack_range_area_exited)
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	HealingSystem.heal_instant.connect(_on_heal_instant)
	HealingSystem.heal_tick.connect(_on_heal_tick)
	HealingSystem.heal_ended.connect(_on_heal_ended)
	InputR.clear_move_target() # zmaz stary ciel po reloade sceny
	await play_spawn_animation()

func _physics_process(delta):
	stun_left = maxf(stun_left - delta, 0.0)
	root_left = maxf(root_left - delta, 0.0)
	slow_left = maxf(slow_left - delta, 0.0)
	if slow_left <= 0.0:
		slow_multiplier = 1.0

	# stun = tvrde CC — ziadny pohyb ani strelba; cooldowny (invuln/fire)
	# pocas stunu netikaju (zamerne, rovnako ako unit.gd attack_left)
	if stun_left > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 500 * delta)
		move_and_slide()
		update_idle_animation()
		return

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
		if _is_target_in_attack_range(primary_target):
			# v dosahu — strielaj
			_try_fire(primary_target)
		else:
			# mimo dosahu — chase (manualny ciel ma prioritu pred tap-to-move)
			move_dir = (primary_target.global_position - global_position).normalized()
	else:
		# ziadny manualny ciel — auto-target: strielaj na najblizsieho v dosahu,
		# bez chase. Auto-utok zacne LEN ked hrac prave nezadava pohyb (move_dir
		# je tap-to-move smer z get_move_input() vyssie, este bez chase override) —
		# inak by kazdy nepriatel v dosahu prerusil pohyb hraca.
		var nearest := find_nearest_enemy()
		_update_auto_target(nearest)
		if nearest != null and move_dir == Vector2.ZERO:
			_try_fire(nearest)

	# _perform_attack() spustene tento frame vyplo physics_process a vynulovalo
	# velocity — zvysok tejto funkcie (update_*_animation + move_and_slide) by
	# hned prepisal attack_left spat na idle/walk a klip by sa nikdy nezobrazil.
	# Preskoc ho. Mobilni utocnici (can_move_while_attacking) pohyb zamknuty
	# nemaju, pokracuju normalne.
	if is_attacking and not can_move_while_attacking:
		return

	# root: hrdina moze stale utocit (uz prebehlo vyssie), ale sa nesmie hybat
	if root_left > 0.0:
		move_dir = Vector2.ZERO

	# Normalizacia (aby diagonalna nebola rychlejsia)
	if move_dir != Vector2.ZERO:
		move_dir = move_dir.normalized()
		last_direction = move_dir
		update_animation(move_dir)
	else:
		update_idle_animation()

	var eff_speed := speed * slow_multiplier
	velocity = velocity.move_toward(move_dir * eff_speed, 500 * delta)
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
	if is_attacking and node == _attacking_target:
		return  # rovnaky ciel ako prave utocim — nech swing dobehne
	if is_attacking and node != _attacking_target:
		_cancel_attack_windup()
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
	# hrac zadal novy tap-to-move — zrus rozbehnuty swing aj manualny ciel
	_cancel_attack_windup()
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

# Dlzka attack_left animacie prave teraz (frame_count / speed), 0.0 ak
# animacia chyba/je nevalidna. Pouzivane aj v _try_fire() aj v
# _perform_attack(), aby cyklus vzdy sedel s aktualne nahratou
# animaciou bez ohladu na jej fps/pocet snimkov.
func _current_cast_point() -> float:
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation("attack_left"):
		return 0.0
	var fc := frames.get_frame_count("attack_left")
	var spd := frames.get_animation_speed("attack_left")
	if fc <= 0 or spd <= 0.0:
		return 0.0
	return fc / spd

func _try_fire(target: Node2D) -> void:
	if fire_left <= 0.0 and not is_attacking:
		last_direction = (target.global_position - global_position).normalized()
		fire_left = _current_cast_point() + recovery_time
		_perform_attack(target)

# Najblizsi zo vsetkych, co PRAVE FYZICKY prekryvaju AttackRange (nie
# center-to-center vzdialenostny odhad) — spravne aj pre velke ciele.
func find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_d2 := INF
	for area in _range_areas:
		if not _is_hurtbox_owner_alive(area):
			continue
		var owner_node := area.get_parent() as Node2D
		if owner_node == null:
			continue
		var d2 := global_position.distance_squared_to(owner_node.global_position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = owner_node
	return nearest

func _on_attack_range_area_entered(area: Area2D) -> void:
	if _is_valid_attack_target(area) and not _range_areas.has(area):
		_range_areas.append(area)

func _on_attack_range_area_exited(area: Area2D) -> void:
	_range_areas.erase(area)

# Rovnaka predikat-logika ako unit.gd's _is_valid_attack_target
# (TargetFilter.ALL ekvivalent) — hrac utoci na hociktory nepriatelsky
# hero/unit/vezu/bazu.
func _is_valid_attack_target(area: Area2D) -> bool:
	if not _is_hurtbox_owner_alive(area):
		return false
	return area.is_in_group("enemy_hurtbox") or area.is_in_group("enemy_turret_hurtbox") or area.is_in_group("enemy_base_hurtbox")

# Hurtbox je child bojujuceho nodu — platnost sa hodnoti podla jeho
# vlastnika (rovnaky dovod ako unit.gd's _is_hurtbox_owner_alive).
func _is_hurtbox_owner_alive(area: Area2D) -> bool:
	if area == null or not is_instance_valid(area):
		return false
	var owner_node := area.get_parent()
	if owner_node == null or not is_instance_valid(owner_node):
		return false
	if "is_dead" in owner_node and owner_node.is_dead:
		return false
	if "hp" in owner_node and owner_node.hp <= 0:
		return false
	return true

# Je target fyzicky prekryty s AttackRange prave teraz? Pouzivane pre
# primary_target aj pre MELEE zasah-recheck v _perform_attack().
func _is_target_in_attack_range(target: Node2D) -> bool:
	for area in _range_areas:
		if is_instance_valid(area) and area.get_parent() == target:
			return true
	return false

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

	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("death_left"):
		# rovnaka smerova logika ako update_idle_animation() — flip podla
		# last_direction v momente smrti
		if abs(last_direction.x) > abs(last_direction.y):
			if last_direction.x > 0:
				sprite.flip_h = true  #RIGHT
			else:
				sprite.flip_h = false  #LEFT
		else:
			if last_direction.y > 0:
				sprite.flip_h = false  #DOWN
			else:
				sprite.flip_h = true  #UP
		sprite.play("death_left")
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
	invuln_left = 1.0
	await play_spawn_animation()

func fire_bolt(target: Node2D) -> void:
	if bolt_scene == null:
		push_error("Player: bolt_scene nie je nastavene!")
		return

	var bolt := bolt_scene.instantiate()
	bolt.set("damage", projectile_damage)
	get_parent().add_child.call_deferred(bolt)
	bolt.call_deferred("setup", global_position, target)


# Cast-point utok s moznostou zrusenia. Hraje attack_left (dlzka =
# frame_count/speed, rovnaky vzor ako play_spawn_animation()), zamkne pohyb
# ak !can_move_while_attacking. Az PO damage_point (damage_point_ratio-zlomok
# cast_pointu, viz hero_data.gd) sa svih POVAZUJE ZA COMMITNUTY — dovtedy
# hociaky novy prikaz (_cancel_attack_windup(), volane z on_new_move_command(),
# set_primary_target() pri zmene ciela, apply_stun()) ho zrusi cely bez
# damage a bez cooldownu. _attack_id token detekuje, ci k takemuto zruseniu
# doslo pocas cakania na await — ak ano, tento coroutine uz nema co robit,
# canceller vsetko (physics_process/fire_left/animacia) uz vyriesil. Po
# committnuti zvysny "backswing" (cast_point - damage_point) je uz len
# kozmeticky, pohyb je odomknuty okamzite.
func _perform_attack(target: Node2D) -> void:
	_attack_id += 1
	var my_attack_id := _attack_id
	is_attacking = true
	_attacking_target = target
	if not can_move_while_attacking:
		set_physics_process(false)
		velocity = Vector2.ZERO
	update_attack_animation()

	var cast_point := _current_cast_point()
	var damage_point := cast_point * damage_point_ratio
	if damage_point > 0.0:
		await get_tree().create_timer(damage_point).timeout

	if my_attack_id != _attack_id or is_dead:
		return  # zrusene (novy prikaz/stun) alebo hrdina medzitym zomrel — canceller uz vsetko vyriesil

	is_attacking = false
	_attacking_target = null
	if not can_move_while_attacking:
		# fire_left uz nesie recovery_time zaciname pocitat presne od tohto
		# damage pointu, nie od konca celej animacie
		fire_left = recovery_time
		set_physics_process(true)

	if not is_instance_valid(target):
		return

	match attack_type:
		HeroData.AttackType.MELEE:
			if not _is_target_in_attack_range(target) or not target.has_method("take_damage"):
				return
			if "is_dead" in target and target.is_dead:
				return
			if "hp" in target and target.hp <= 0:
				return
			target.take_damage(projectile_damage)
		_:
			fire_bolt(target)

# Zrusi rozbehnuty windup (pred damage pointom) bez damage a bez cooldown
# penalty — hrdina sa "este nezaviazal". Volane pri novom tap-to-move,
# pri zmene manualneho ciela a pri stune (viz volania vyssie).
func _cancel_attack_windup() -> void:
	if not is_attacking:
		return
	_attack_id += 1
	is_attacking = false
	_attacking_target = null
	fire_left = 0.0
	if not can_move_while_attacking:
		set_physics_process(true)
	update_idle_animation()

func update_attack_animation() -> void:
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("attack_left"):
		if abs(last_direction.x) > abs(last_direction.y):
			sprite.flip_h = last_direction.x > 0
		else:
			sprite.flip_h = last_direction.y < 0
		sprite.play("attack_left")
	_play_attack_sound()

func _play_attack_sound() -> void:
	if hero_data != null and hero_data.attack_sound != null:
		$AttackSfx.stream = hero_data.attack_sound
		$AttackSfx.play()


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
		sprite.flip_h = direction.x > 0 #RIGHT 
	else:
		sprite.flip_h = direction.y < 0 #UP
	sprite.play("walk_left")
		
		#if direction.x > 0:
			#sprite.flip_h = true
			#sprite.play("walk_left") #RIGHT
		#else:
			#sprite.flip_h = false
			#sprite.play("walk_left") #LEFT
	#else:
		#if direction.y > 0:
			#sprite.flip_h = false
			#sprite.play("walk_left") #DOWN
		#else:
			#sprite.flip_h = true
			#sprite.play("walk_left") #UP

func update_idle_animation() -> void:
	if abs(last_direction.x) > abs(last_direction.y):
		sprite.flip_h = last_direction.x > 0 #RIGHT
	else:
		sprite.flip_h = last_direction.y < 0 #UP
	sprite.play("iddle_left")
		
	#if abs(last_direction.x) > abs(last_direction.y):
		#if last_direction.x > 0:
			#sprite.flip_h = true
			#sprite.play("iddle_left") #RIGHT
		#else:
			#sprite.flip_h = false
			#sprite.play("iddle_left") #LEFT
	#else:
		#if last_direction.y > 0:
			#sprite.flip_h = false
			#sprite.play("iddle_left") #DOWN
		#else:
			#sprite.flip_h = true
			#sprite.play("iddle_left") #UP


# Spawn/respawn vizualny efekt — hra sa pri prvom vstupe do zapasu aj po
# kazdom respawne (volane z _ready() aj revive()). Pocas prehravania je
# hrdina zamrznuty (rovnaky vzor ako die() cez set_physics_process), aby
# nemohol hybat/strielat kym sa "materializuje". Chybajuca spawn_left
# animacia degraduje na ziadny efekt — rovnaky guard ako has_animation
# ("death") v die(). Cakame casovacom odvodenym z dlzky klipu (frame_count
# / speed), nie `await animation_finished` — spawn_left moze byt loop=1 a
# ten signal by sa nikdy neozval (architecture.md §6, vzor spell_zone.gd).
func play_spawn_animation() -> void:
	set_physics_process(false)
	velocity = Vector2.ZERO
	var frames := sprite.sprite_frames
	if frames != null and frames.has_animation("spawn_left"):
		sprite.flip_h = false
		sprite.play("spawn_left")
		var fc := frames.get_frame_count("spawn_left")
		var spd := frames.get_animation_speed("spawn_left")
		if fc > 0 and spd > 0.0:
			await get_tree().create_timer(fc / spd).timeout
	if is_dead:
		return  # zomrel pocas spawn klipu — die() uz prebehol, nekriesime physics
	set_physics_process(true)
	update_idle_animation()
