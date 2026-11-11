extends CharacterBody2D

# AI hero avatar — pohyb/targeting/heal-seek (karty/energia AI pride neskor).
# March k najblizsej nepriatelskej strukture; pri nizkom HP (HeroAI hysteresis)
# hlada ready healing pod (vlastna strana ma prednost), inak ustupuje k spawnu.
# Strelba je volna len ked hrdina stoji (idle) — pocas marchu/ustupu len
# sebaobrana na kratku vzdialenost (SELF_DEFENSE_RANGE_RATIO).

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
@export var recovery_time: float = 0.4
@export var projectile_damage: int = 25
@export var bolt_scene: PackedScene
var fire_left: float = 0.0
var last_direction := Vector2.DOWN

var attack_type: HeroData.AttackType = HeroData.AttackType.RANGED
var can_move_while_attacking: bool = false
var is_attacking: bool = false
var damage_point_ratio: float = 0.7
var _attacking_target: Node2D = null
var _attack_id: int = 0

# === STATUS EFEKTY (spells) === identicke s unit.gd/player.gd — ZAMERNA
# duplikacia, ziadna zdielana base class (architecture.md princip). Dlhsie
# trvanie vzdy vyhrava (maxf), nikdy sa nestackuje ani neskracuje.
var stun_left: float = 0.0
var root_left: float = 0.0
var slow_left: float = 0.0
var slow_multiplier: float = 1.0

func apply_stun(duration: float) -> void:
	_end_dash()  # stun prerusi beziaci dash
	stun_left = maxf(stun_left, duration)
	if is_attacking:
		_cancel_attack_windup()

func apply_root(duration: float) -> void:
	root_left = maxf(root_left, duration)

func apply_slow(multiplier: float, duration: float) -> void:
	slow_multiplier = multiplier
	slow_left = maxf(slow_left, duration)

# Knockback = kratky vynuteny pohyb (Tidal Wave) — ZAMERNA duplikacia s
# unit.gd/player.gd. Novy knockback NAHRADI beziaci (nie maxf). Ignoruje
# root/slow, hybe aj stunnutym hrdinom; prekazky/struktury ho zastavia (mask 4).
var knockback_left: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO

func apply_knockback(direction: Vector2, distance: float, duration: float) -> void:
	_end_dash()  # knockback prerusi beziaci dash
	if is_dead or distance <= 0.0:
		return
	# povinne: zamknuty windup vypina _physics_process — bez cancelu by sa posun nikdy nespustil
	_cancel_attack_windup()
	duration = maxf(duration, 0.05)
	knockback_velocity = direction.normalized() * (distance / duration)
	knockback_left = duration
	_nav_goal = Vector2.INF  # stara cesta po posune neplati

# === DASH === ZAMERNA duplikacia s player.gd (rovnako ako status efekty /
# knockback, ziadna zdielana base class). Kratky rychly vynuteny pohyb platenym
# z DashMeter. Ignoruje slow; stun a knockback ho PRERUSIA, root nie. Pocas
# dashu docasne vypnuty mask bit 2 (unit_body). Ziadne i-frames.
# Enemy dash strip sa NEZOBRAZUJE (rozhodnute) — health bar sa tu nevola.
var dash_meter: DashMeter = DashMeter.new()  # default pre F6 bez HeroData
var dash_left: float = 0.0
var dash_velocity: Vector2 = Vector2.ZERO
var _dash_restore_unit_mask: bool = false
var _is_spawning: bool = false
var last_dash_distance: float = 0.0  # dlzka posledneho spusteneho dashu (px)

func try_dash(world_pos: Vector2) -> bool:
	if is_dead or _is_spawning or BattleManager.is_match_over():
		return false
	if stun_left > 0.0 or root_left > 0.0 or knockback_left > 0.0 or dash_left > 0.0:
		return false
	if global_position.distance_squared_to(world_pos) < 1.0:
		return false
	var amount := dash_meter.consume()
	if amount <= 0.0:
		return false
	last_dash_distance = DashMeter.FULL_DISTANCE * amount
	# zrusi windup a zaroven zapne physics_process spat (zamknuty windup ho vypina)
	_cancel_attack_windup()
	var dir := (world_pos - global_position).normalized()
	dash_velocity = dir * DashMeter.SPEED
	dash_left = DashMeter.FULL_DISTANCE * amount / DashMeter.SPEED
	last_direction = dir
	_dash_restore_unit_mask = get_collision_mask_value(2)
	if _dash_restore_unit_mask:
		set_collision_mask_value(2, false)
	return true

# Bezpecne aj ked ziaden dash nebezi (no-op).
func _end_dash() -> void:
	if dash_left <= 0.0 and not _dash_restore_unit_mask:
		return
	dash_left = 0.0
	velocity = Vector2.ZERO
	if _dash_restore_unit_mask:
		set_collision_mask_value(2, true)
		_dash_restore_unit_mask = false
	_nav_goal = Vector2.INF  # stara cesta po posune neplati (ako knockback)

func get_dash_meter() -> DashMeter:
	return dash_meter

# === AI DASH === rozhodovanie KEDY dashnut. Zije TU (potrebuje pozicie zon,
# hrdinov, spawnu), NIE v HeroAI — HeroAI ostava cisty, bez pozicii.
# Treningove AI: zamerne jednoduche a omylne (reakcny cas, ziadna predikcia).
# Priorita (max jeden pokus za frame): 1) DODGE spell zony, 2) ESCAPE pri
# LOW_HP v boji, 3) CHASE nizkeho-HP nepriatelskeho hrdinu.
const AI_DODGE_DELAY_MIN := 0.25   # reakcny cas — AI nie je neomylne
const AI_DODGE_DELAY_MAX := 0.75
const AI_DASH_MIN_GAP := 0.6       # min. pauza medzi AI dashmi (Hermes nevystreli 3 naraz)
const AI_DASH_FULL_FILL := 1.0     # escape/chase len s plnym nabojom
var _rng := RandomNumberGenerator.new()
var _ai_dash_gap_left: float = 0.0
var _dodge_zone: Node2D = null
var _dodge_delay_left: float = 0.0

# smrt/respawn — ziadny visiaci dodge ani gap zo starej zony
func _reset_ai_dash() -> void:
	_dodge_zone = null
	_dodge_delay_left = 0.0
	_ai_dash_gap_left = 0.0

# hp_state je int (HeroAI.State hodnota) — autoload nema class_name, viz _prev_hp_state.
# steer_dir = smer march/retreat steeringu z tohto framu, zachyteny PRED strelbou
# (sebaobrana _try_fire prepise last_direction smerom K nepriatelovi).
func _update_ai_dash(delta: float, hp_state: int, is_marching_or_retreating: bool, steer_dir: Vector2) -> void:
	_ai_dash_gap_left = maxf(_ai_dash_gap_left - delta, 0.0)
	if _ai_dash_gap_left > 0.0 or dash_left > 0.0:
		return

	# 1) DODGE — nepriatelska zona, v ktorej PRAVE stojim (center-to-center,
	#    rovnako ako BattleManager.get_targets_in_radius)
	var threat: Node2D = null
	for z in get_tree().get_nodes_in_group("spell_zones"):
		if not is_instance_valid(z) or not z.is_threat() or z.get_caster_team() == team:
			continue
		var r: float = z.get_radius()
		if global_position.distance_squared_to(z.global_position) <= r * r:
			threat = z as Node2D
			break
	if threat == null:
		_dodge_zone = null
	else:
		if threat != _dodge_zone:
			_dodge_zone = threat
			_dodge_delay_left = _rng.randf_range(AI_DODGE_DELAY_MIN, AI_DODGE_DELAY_MAX)
		_dodge_delay_left -= delta
		if _dodge_delay_left <= 0.0:
			var away := global_position - threat.global_position
			if away.length_squared() < 1.0:
				# presne v strede — uhni smerom k vlastnemu spawnu
				var spawn: Vector2 = BattleManager.snap_to_navigation(
						BattleManager.hero_spawn_positions.get(team, global_position))
				away = spawn - global_position
			# odmietnuty pokus (malo naboja) skusi znova dalsi frame, kym som vnutri
			if away.length_squared() >= 1.0 and try_dash(global_position + away.normalized() * DashMeter.FULL_DISTANCE):
				_ai_dash_gap_left = AI_DASH_MIN_GAP
				DebugLog.info("dash", "%s AI dodge (delay hotovy) meter=%.2f" % [team, dash_meter.value])
		return  # v hrozbe (aj cakajuci dodge) — escape/chase sa preskocia

	# 2) ESCAPE — LOW_HP (rovnaky prah ako heal-seek), ustupujem a som v boji
	if hp_state == HeroAI.State.LOW_HP:
		if is_marching_or_retreating and find_nearest_enemy() != null \
				and dash_meter.value >= AI_DASH_FULL_FILL and steer_dir != Vector2.ZERO:
			if try_dash(global_position + steer_dir.normalized() * DashMeter.FULL_DISTANCE):
				_ai_dash_gap_left = AI_DASH_MIN_GAP
				DebugLog.info("dash", "%s AI escape meter=%.2f" % [team, dash_meter.value])
		return

	# 3) CHASE — nepriatelsky hrdina pod LOW_HP_PCT tesne za mojim dosahom
	if dash_meter.value < AI_DASH_FULL_FILL:
		return
	var enemy_team := SkillEffects.enemy_team_of(team)
	# validacia PRED typovanim — freed instancia do typovanej premennej = runtime error
	var opp_v: Variant = BattleManager.heroes.get(enemy_team)
	if opp_v == null or not is_instance_valid(opp_v) or BattleManager.is_hero_dead(enemy_team):
		return
	var opp := opp_v as Node2D
	if opp == null:
		return
	var opp_hp: float = float(opp.health_points) if "health_points" in opp else float(opp.hp)
	var opp_max: float = maxf(float(opp.max_hp), 1.0)
	if opp_hp / opp_max >= HeroAI.LOW_HP_PCT:
		return
	var d2 := global_position.distance_squared_to(opp.global_position)
	var reach := attack_range + DashMeter.FULL_DISTANCE
	if d2 > attack_range * attack_range and d2 <= reach * reach:
		if try_dash(opp.global_position):
			_ai_dash_gap_left = AI_DASH_MIN_GAP
			DebugLog.info("dash", "%s AI chase meter=%.2f" % [team, dash_meter.value])

# === SKILL BOHA === cooldown + try_cast — ZAMERNA duplikacia s player.gd
# (rovnako ako status efekty). Samotny efekt je v SkillEffects (jedno miesto).
# Skill zacina na cooldowne (spawn aj revive). Cooldown tika v _process, nie
# v _physics_process — ten je vypnuty pocas zamknuteho windupu a spawn klipu.
var skill: SkillData = null
var skill_cd_left: float = 0.0

func _process(delta: float) -> void:
	# netika pocas smrti, tika aj pocas stunu
	if not is_dead and skill_cd_left > 0.0:
		skill_cd_left = maxf(skill_cd_left - delta, 0.0)
	# dash meter — rovnake pravidlo ako skill cooldown (netika v smrti, tika v stune)
	if not is_dead:
		dash_meter.tick(delta)

func _reset_skill_cooldown() -> void:
	skill_cd_left = skill.cooldown if skill != null else 0.0

func get_skill_cooldown_left() -> float:
	return skill_cd_left

# AI ciel: najblizsi zivy nepriatel v cast_range.
func _pick_skill_target() -> Node2D:
	return SkillEffects.pick_cast_target(skill, global_position, SkillEffects.enemy_team_of(team))

func can_cast_skill() -> bool:
	if not SkillEffects.is_implemented(skill):
		return false
	if skill_cd_left > 0.0 or is_dead or stun_left > 0.0 or BattleManager.is_match_over():
		return false
	return _pick_skill_target() != null

# Instant cast (zatial bez windupu/animacie). Odmietnuty cast cooldown nespusti.
func try_cast_skill() -> bool:
	if not can_cast_skill():
		return false
	var target := _pick_skill_target()
	_cancel_attack_windup()
	last_direction = (target.global_position - global_position).normalized()
	update_idle_animation()
	var ok := SkillEffects.cast(skill, self, team, target, projectile_damage)
	if ok:
		skill_cd_left = skill.cooldown
	return ok

# Pohybove ciele — refresh v intervale (unit.gd pattern), nie kazdy frame
var structure_target: Node2D = null  # NORMAL stav
var heal_target: Node2D = null       # LOW_HP stav
# Rovnaky princip ako player.gd — fyzicky prekryvajuce hurtboxy
# nepriatelskeho timu, zdroj pravdy pre "je X v dosahu".
var _range_areas: Array[Area2D] = []
var target_check_timer: float = 0.0
const TARGET_CHECK_INTERVAL := 0.4
# Ked AI aktivne pochoduje/ustupuje, strielba je potlacena (aby ustup
# skutocne znamenal ustup) OKREM sebaobrany — ak sa nepriatel dostane
# na menej nez tento podiel z attack_range, hrdina uz aj tak nemoze
# unikaru, tak radsej opetuje paľbu. 0.5 = nepriatel musi byt
# "za rohom" (polovica normalneho dosahu), nie len niekde v dosahu.
const SELF_DEFENSE_RANGE_RATIO := 0.5
# int, nie HeroAI.State — autoload meno nie je class_name, takze sa neda
# pouzit v type anotacii (enum hodnoty su aj tak int)
var _prev_hp_state: int = HeroAI.State.NORMAL

@onready var health_bar: Control = $HealthBar
@onready var target_marker: Sprite2D = $TargetMarker
@onready var attack_range_area: Area2D = $AttackRange
@onready var nav_agent: NavigationAgent2D = $NavAgent

# Posledny ciel poslany NavAgentu. Vector2.INF = ziadny (donutim prvy vypocet
# cesty). Prepocet cesty len ked sa ciel posunie o viac ako NAV_REPATH_DIST_SQ
# (chase pohybliveho ciela) — nie kazdy frame.
var _nav_goal: Vector2 = Vector2.INF
const NAV_REPATH_DIST_SQ := 16.0 * 16.0

# Nastavi hrdinu podla HeroData PRED vstupom do stromu (spawn flow:
# instantiate → configure → add_child). Pouziva $NodePath priamo, nie
# @onready vary — tie sa priradia az pri _ready(), ktory tu este neprebehol.
func configure(data: HeroData, new_team: String, stat_mods: Dictionary = {}) -> void:
	hero_data = data
	team = new_team
	max_hp = roundi(data.max_hp * float(stat_mods.get(&"max_hp", 1.0)))
	speed = data.speed
	attack_range = data.attack_range
	$AttackRange/CollisionShape2D.shape.radius = data.attack_range
	# attack speed = zatial len kratsi recovery po zasahu (rework neskor)
	recovery_time = data.recovery_time / maxf(float(stat_mods.get(&"attack_speed", 1.0)), 0.01)
	damage_point_ratio = data.damage_point_ratio
	projectile_damage = roundi(data.projectile_damage * float(stat_mods.get(&"damage", 1.0)))
	bolt_scene = data.projectile_scene
	attack_type = data.attack_type
	can_move_while_attacking = data.can_move_while_attacking
	skill = data.skill
	dash_meter = DashMeter.new(data.dash_charges, data.dash_recharge_time)
	if data.sprite_frames != null:
		$AnimatedSprite2D.sprite_frames = data.sprite_frames

func _ready() -> void:
	hp = max_hp
	_reset_skill_cooldown()
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

	attack_range_area.collision_mask = ENEMY_HURTBOX_LAYER if team == "player" else PLAYER_HURTBOX_LAYER
	attack_range_area.area_entered.connect(_on_attack_range_area_entered)
	attack_range_area.area_exited.connect(_on_attack_range_area_exited)

	HealingSystem.heal_instant.connect(_on_heal_instant)
	HealingSystem.heal_tick.connect(_on_heal_tick)
	HealingSystem.heal_ended.connect(_on_heal_ended)

	# unit_base.tscn (*_unit.tscn archetypy) skryva marker priamo v scene (visible = false);
	# hero_dummy.tscn to nema, tak ho skryjeme tu
	target_marker.visible = false

	_rng.randomize()  # AI dash reakcny cas

	await play_spawn_animation()

func _apply_hurtbox_layer() -> void:
	$Hurtbox.collision_layer = PLAYER_HURTBOX_LAYER if team == "player" else ENEMY_HURTBOX_LAYER

# =========================
# AI POHYB A CIELENIE
# =========================

func _physics_process(delta: float) -> void:
	stun_left = maxf(stun_left - delta, 0.0)
	root_left = maxf(root_left - delta, 0.0)
	slow_left = maxf(slow_left - delta, 0.0)
	if slow_left <= 0.0:
		slow_multiplier = 1.0

	# knockback ma prednost aj pred stunom — vynuteny pohyb, bez AI/utokov
	if knockback_left > 0.0:
		knockback_left = maxf(knockback_left - delta, 0.0)
		velocity = knockback_velocity
		move_and_slide()
		update_idle_animation()
		if knockback_left <= 0.0:
			velocity = Vector2.ZERO
		return

	# dash — rovnaky tvar ako knockback; bez AI/utokov, ignoruje slow, walk klip
	if dash_left > 0.0:
		dash_left = maxf(dash_left - delta, 0.0)
		velocity = dash_velocity
		move_and_slide()
		update_animation(dash_velocity)
		if dash_left <= 0.0:
			_end_dash()
		return

	# stun = tvrde CC — ziadny pohyb ani strelba; fire_left pocas stunu
	# netika (zamerne, rovnako ako unit.gd attack_left)
	if stun_left > 0.0:
		_stand_idle()
		move_and_slide()
		return

	fire_left = maxf(fire_left - delta, 0.0)

	var hp_pct := float(hp) / float(max_hp)
	var hp_state := HeroAI.get_hp_state(team, hp_pct)
	if hp_state != _prev_hp_state:
		_prev_hp_state = hp_state
		target_check_timer = 0.0  # novy stav = okamzity re-query ciela

	# je AI prave teraz aktivne v pohybe s cielom (march/retreat), alebo
	# stoji na mieste? Rozhoduje to nizsie, ci sa strielba deje volne
	# (idle) alebo len na sebaobranu (march/retreat) — rovnaky princip
	# ako move-command gate v player.gd, len namiesto hracovho vstupu je
	# tu AI-ov vlastny pohybovy zamer.
	var is_marching_or_retreating := false

	# if/elif namiesto match — HeroAI.State.X cez autoload instanciu nie je
	# konstantny vyraz pre match pattern (autoload nema class_name)
	if hp_state == HeroAI.State.LOW_HP:
		structure_target = null  # zahod staru NORMAL cache
		_update_heal_target(delta)
		if heal_target != null and is_instance_valid(heal_target):
			# dojdenie na pod spusti existujuci area_entered heal
			# automaticky — ziadne explicitne "use pod" volanie
			_steer_towards(heal_target.global_position)
			is_marching_or_retreating = true
		else:
			# ziadny ready pod nikde — ustup k vlastnemu spawnu. Prisunute na
			# navmesh: spawn point moze lezat tesne pri prekazke (agent radius
			# margin), bez toho by cesta koncila kus pred nim a 8px arrival
			# check by nikdy neprešiel.
			var retreat: Vector2 = BattleManager.snap_to_navigation(
					BattleManager.hero_spawn_positions.get(team, global_position))
			if global_position.distance_squared_to(retreat) <= 8.0 * 8.0:
				_stand_idle()
			else:
				_steer_towards(retreat)
				is_marching_or_retreating = true
	else:
		heal_target = null  # zahod staru LOW_HP cache
		_update_structure_target(delta)
		if structure_target != null:
			# zrkadli player.gd primary-target logiku — v dosahu stoj
			# a strielaj (fire krok nizsie), mimo dosahu chase
			if _is_target_in_attack_range(structure_target):
				_stand_idle()
			else:
				_steer_towards(structure_target.global_position)
				is_marching_or_retreating = true
		else:
			_stand_idle()

	# smer steeringu PRED strelbou — _try_fire nizsie prepise last_direction k cielu
	var steer_dir := last_direction

	# strelba: volne ked hrdina stoji (idle), inak len sebaobrana ked je
	# nepriatel velmi blizko (SELF_DEFENSE_RANGE_RATIO) — march/retreat ma
	# prioritu, aby ustup skutocne znamenal ustup, ale hrdina sa nema
	# nechat bit zadara ked uz aj tak nemoze unikaru
	var nearest := find_nearest_enemy()
	if nearest != null:
		if not is_marching_or_retreating:
			_try_fire(nearest)
		else:
			var self_defense_range := attack_range * SELF_DEFENSE_RANGE_RATIO
			var d2 := global_position.distance_squared_to(nearest.global_position)
			if d2 <= self_defense_range * self_defense_range:
				_try_fire(nearest)

	# skill: AI castne hned ako moze (NORMAL aj LOW_HP), prvy jednoduchy pass —
	# ziadne cluster skore ani reaction delay
	if can_cast_skill():
		try_cast_skill()

	# AI dash — posledny krok framu (dodge / escape / chase)
	_update_ai_dash(delta, hp_state, is_marching_or_retreating, steer_dir)

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

# Smer k cielu cez navmesh. Bez navmeshu (NordPlains / prvy frame) = priamy
# smer, identicky so starym spravanim. Cesta sa prepocita len ked sa ciel
# posunie o viac ako NAV_REPATH_DIST (chase pohybliveho ciela), nie kazdy frame.
func _nav_direction_to(goal: Vector2) -> Vector2:
	if not BattleManager.has_navigation():
		return (goal - global_position).normalized()
	if _nav_goal == Vector2.INF or _nav_goal.distance_squared_to(goal) > NAV_REPATH_DIST_SQ:
		_nav_goal = goal
		nav_agent.target_position = goal
	if nav_agent.is_navigation_finished():
		return (goal - global_position).normalized()
	var next := nav_agent.get_next_path_position()
	return (next - global_position).normalized()

# Single-hero steering — ZIADNA separation/neighbor logika (to je unit.gd
# vec pre squady, nie pre osamoteneho hrdinu)
func _steer_towards(target_pos: Vector2) -> void:
	# root (Trapping Net) — pohyb stoji, strelba dole vo _physics_process bezi
	if root_left > 0.0:
		_stand_idle()
		move_and_slide()
		return

	var dir := _nav_direction_to(target_pos)
	last_direction = dir
	update_animation(dir)
	var eff_speed := speed * slow_multiplier
	velocity = dir * eff_speed
	move_and_slide()

func _stand_idle() -> void:
	velocity = Vector2.ZERO
	update_idle_animation()

# =========================
# FIGHTING LOGIC (port z player.gd, generalizovany team)
# =========================

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

func _is_valid_attack_target(area: Area2D) -> bool:
	if not _is_hurtbox_owner_alive(area):
		return false
	var enemy_team := "player" if team == "enemy" else "enemy"
	return area.is_in_group(enemy_team + "_hurtbox") or area.is_in_group(enemy_team + "_turret_hurtbox") or area.is_in_group(enemy_team + "_base_hurtbox")

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

func _is_target_in_attack_range(target: Node2D) -> bool:
	for area in _range_areas:
		if is_instance_valid(area) and area.get_parent() == target:
			return true
	return false

# Dlzka attack_left animacie prave teraz (frame_count / speed), 0.0 ak
# animacia chyba/je nevalidna. Pouzivane aj v _try_fire() aj v
# _perform_attack(), aby cyklus vzdy sedel s aktualne nahratou
# animaciou bez ohladu na jej fps/pocet snimkov.
func _current_cast_point() -> float:
	var frames: SpriteFrames = $AnimatedSprite2D.sprite_frames
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

func fire_bolt(target: Node2D) -> void:
	if bolt_scene == null:
		push_error("HeroDummy: bolt_scene nie je nastavene!")
		return

	var bolt := bolt_scene.instantiate()
	bolt.set("damage", projectile_damage)
	get_parent().add_child.call_deferred(bolt)
	bolt.call_deferred("setup", global_position, target)

# Cast-point utok — identicka logika ako player.gd::_perform_attack(), pouziva
# $AnimatedSprite2D priamo (tento subor nema cachovany sprite var).
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
		return  # zrusene (HP-flip/stun) alebo hrdina medzitym zomrel — canceller uz vsetko vyriesil

	is_attacking = false
	_attacking_target = null
	if not can_move_while_attacking:
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
			if hero_data != null:
				AudioManager.play_sfx(hero_data.attack_sfx, global_position)
		_:
			if hero_data != null:
				AudioManager.play_sfx(hero_data.attack_sfx, global_position)
			fire_bolt(target)

# Zrusi rozbehnuty windup (pred damage pointom) bez damage a bez cooldown
# penalty — hrdina sa "este nezaviazal". Volane pri HP-hysteresis flipe
# (take_damage()) a pri stune (viz volania vyssie).
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
	if $AnimatedSprite2D.sprite_frames != null and $AnimatedSprite2D.sprite_frames.has_animation("attack_left"):
		if abs(last_direction.x) > abs(last_direction.y):
			$AnimatedSprite2D.flip_h = last_direction.x > 0
		else:
			$AnimatedSprite2D.flip_h = last_direction.y < 0
		$AnimatedSprite2D.play("attack_left")

# =========================
# ANIMATION LOGIC (port z player.gd)
# =========================

func update_animation(direction: Vector2) -> void:
	# Porovname absolutne hodnoty osi
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			$AnimatedSprite2D.flip_h = true
			$AnimatedSprite2D.play("walk_left") #RIGHT
		else:
			$AnimatedSprite2D.flip_h = false
			$AnimatedSprite2D.play("walk_left") #LEFT
	else:
		if direction.y > 0:
			$AnimatedSprite2D.flip_h = false
			$AnimatedSprite2D.play("walk_left") #DOWN
		else:
			$AnimatedSprite2D.flip_h = true
			$AnimatedSprite2D.play("walk_left") #UP

func update_idle_animation() -> void:
	if abs(last_direction.x) > abs(last_direction.y):
		if last_direction.x > 0:
			$AnimatedSprite2D.flip_h = true
			$AnimatedSprite2D.play("iddle_left") #RIGHT
		else:
			$AnimatedSprite2D.flip_h = false
			$AnimatedSprite2D.play("iddle_left") #LEFT
	else:
		if last_direction.y > 0:
			$AnimatedSprite2D.flip_h = false
			$AnimatedSprite2D.play("iddle_left") #DOWN
		else:
			$AnimatedSprite2D.flip_h = true
			$AnimatedSprite2D.play("iddle_left") #UP

# Spawn/respawn vizualny efekt — hra sa pri prvom vstupe do zapasu aj po
# kazdom respawne (volane z _ready() aj revive()). Pocas prehravania je
# hrdina zamrznuty (rovnaky vzor ako die() cez set_physics_process), aby
# nemohol hybat/strielat/AI-rozhodovat kym sa "materializuje". Chybajuca
# spawn_left animacia degraduje na ziadny efekt — rovnaky guard ako
# has_animation("death") v die(). Cakame casovacom (frame_count / speed),
# nie `await animation_finished` — spawn_left moze byt loop=1 (architecture.md
# §6, vzor spell_zone.gd "cast").
func play_spawn_animation() -> void:
	_is_spawning = true  # try_dash odmietne — inak by dash "cakal" na zapnutie physics
	set_physics_process(false)
	velocity = Vector2.ZERO
	var frames: SpriteFrames = $AnimatedSprite2D.sprite_frames
	if frames != null and frames.has_animation("spawn_left"):
		$AnimatedSprite2D.flip_h = false
		$AnimatedSprite2D.play("spawn_left")
		var fc := frames.get_frame_count("spawn_left")
		var spd := frames.get_animation_speed("spawn_left")
		if fc > 0 and spd > 0.0:
			await get_tree().create_timer(fc / spd).timeout
	if is_dead:
		_is_spawning = false
		return  # zomrel pocas spawn klipu — die() uz prebehol, nekriesime physics
	_is_spawning = false
	set_physics_process(true)
	update_idle_animation()

# Rovnaky pattern ako unit.gd — player.gd vola set_targeted(true/false)
# pri zamknuti/odomknuti primary_target
func set_targeted(state: bool) -> void:
	target_marker.visible = state

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	health_bar.set_health(hp)
	if is_attacking and hp > 0:
		var hp_pct := float(hp) / float(max_hp)
		var hp_state := HeroAI.get_hp_state(team, hp_pct)
		if hp_state != _prev_hp_state:
			_cancel_attack_windup()
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
	_end_dash()
	_reset_ai_dash()
	if hero_data != null:
		AudioManager.play_sfx(hero_data.death_sfx, global_position)
	_nav_goal = Vector2.INF

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

	if $AnimatedSprite2D.sprite_frames != null and $AnimatedSprite2D.sprite_frames.has_animation("death_left"):
		# rovnaka smerova logika ako update_idle_animation() — flip podla
		# last_direction v momente smrti
		if abs(last_direction.x) > abs(last_direction.y):
			if last_direction.x > 0:
				$AnimatedSprite2D.flip_h = true  #RIGHT
			else:
				$AnimatedSprite2D.flip_h = false  #LEFT
		else:
			if last_direction.y > 0:
				$AnimatedSprite2D.flip_h = false  #DOWN
			else:
				$AnimatedSprite2D.flip_h = true  #UP
		$AnimatedSprite2D.play("death_left")
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
	# cerstvy spawn nesmie mierit na staru cache
	last_direction = Vector2.DOWN
	structure_target = null
	heal_target = null
	_nav_goal = Vector2.INF
	knockback_left = 0.0  # zvysok posunu zo smrti nesmie odtlacit hrdinu zo spawnu
	_end_dash()
	dash_meter.refill()  # po respawne plny meter
	_reset_ai_dash()
	_reset_skill_cooldown()
	await play_spawn_animation()

func _on_hurtbox_input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var players := get_tree().get_nodes_in_group("team_player")
			for p in players:
				if p.has_method("set_primary_target"):
					p.set_primary_target(self)
			InputR.suppress_release_of_touch(event.index)
		get_viewport().set_input_as_handled()
