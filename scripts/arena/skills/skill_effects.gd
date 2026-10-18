class_name SkillEffects

# Efekty aktivnych skillov bohov — JEDINE miesto, kde sa skill efekt aplikuje.
# Iba static funkcie, ziadne uzly sa tu nedrzia (duch DeckRules). Na rozdiel
# od DeckRules sa tu vola BattleManager (target registry, arena_root pre FX).
# Hero skripty (player.gd / hero_dummy.gd) drzia len cooldown a volaju sem.
# Tuning sa cita LEN cez skill.get_value() — do SkillData sa nikdy nezapisuje.
#
# cast() je oddeleny od vyberu ciela, aby ho buduci network handler mohol
# zavolat s uz danym cielom. / cast() takes the target as an argument.

const CHAIN_LIGHTNING := &"skill_zeus_chain_lightning"
const TIDAL_WAVE := &"skill_poseidon_tidal_wave"

# Jediny static stav: neznamy skill id varuje len raz. / Warn once per id.
static var _warned_ids: Dictionary = {}

static func is_implemented(skill: SkillData) -> bool:
	return skill != null and (skill.id == CHAIN_LIGHTNING or skill.id == TIDAL_WAVE)

# Ziva = existuje, nie je mrtvy hrdina/unit, nie je vrak veze (hp = 0 ostava
# v registri). Rovnake pravidlo ako _is_hurtbox_owner_alive() v hero skriptoch.
static func is_alive(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if "is_dead" in n and n.is_dead:
		return false
	if "hp" in n and n.hp <= 0:
		return false
	return true

# % Attack Power -> damage, vzdy aspon 1.
static func skill_damage(attack_power: int, pct: float) -> int:
	return maxi(1, roundi(attack_power * pct / 100.0))

static func enemy_team_of(team: String) -> String:
	return "player" if team == "enemy" else "enemy"

# Najblizsi zivy nepriatel v radiuse (center-to-center), mimo `exclude`.
# Kandidati z BattleManager registra — bazy v nom nie su, su teda imunne.
static func find_nearest_target(from: Vector2, radius: float, enemy_team: String, exclude: Array = []) -> Node2D:
	var nearest: Node2D = null
	var nearest_d2 := INF
	for n in BattleManager.get_targets_in_radius(from, radius, enemy_team):
		if not is_alive(n) or exclude.has(n):
			continue
		var d2 := from.distance_squared_to(n.global_position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = n
	return nearest

# Ciel castu: `preferred` (hracov primary_target), ak je zivy kandidat v
# cast_range — inak najblizsi. null = nie je na co castnut.
# Preferred musi byt v registri, inak by tapnuta baza bola platny ciel.
static func pick_cast_target(skill: SkillData, caster_pos: Vector2, enemy_team: String, preferred: Node2D = null) -> Node2D:
	if skill == null:
		return null
	if preferred != null and is_alive(preferred):
		var candidates := BattleManager.get_targets_in_radius(caster_pos, skill.cast_range, enemy_team)
		if candidates.has(preferred):
			return preferred
	return find_nearest_target(caster_pos, skill.cast_range, enemy_team)

# Spusti efekt skillu. true = efekt prebehol (volajuci spusti cooldown),
# false = odmietnute (ziadny cooldown).
static func cast(skill: SkillData, caster: Node2D, caster_team: String, target: Node2D, attack_power: int) -> bool:
	if skill == null:
		return false
	if skill.id == CHAIN_LIGHTNING:
		return _chain_lightning(skill, caster, caster_team, target, attack_power)
	elif skill.id == TIDAL_WAVE:
		return _tidal_wave(skill, caster, caster_team, target, attack_power)
	if not _warned_ids.has(skill.id):
		_warned_ids[skill.id] = true
		push_warning("SkillEffects: skill '%s' nie je implementovany" % skill.id)
	return false

# Zeus — Chain Lightning. Vsetko v jednom frame, deterministicky (bez RNG):
# zasah ciela, potom az `jumps` skokov na najblizsieho este nezasiahnuteho
# nepriatela v `jump_range` od POSLEDNEHO zasahu. Damage klesa multiplikativne
# (220 % -> 176 % -> 141 % ...). Kazdy zasah: damage, potom stun (ak ciel
# este zije — mrtvy hrdina by inak respawnol stunnuty) a vezi restart vystrelu.
static func _chain_lightning(skill: SkillData, caster: Node2D, caster_team: String, target: Node2D, attack_power: int) -> bool:
	if not is_alive(target) or not is_instance_valid(caster):
		return false
	var damage_pct := skill.get_value(&"damage_pct")
	var falloff := skill.get_value(&"falloff_pct") / 100.0
	var jump_range := skill.get_value(&"jump_range")
	var jumps := roundi(skill.get_value(&"jumps"))
	var stun := skill.get_value(&"stun")
	var enemy_team := enemy_team_of(caster_team)

	var hit: Array = []
	var damages: Array[int] = []
	var points := PackedVector2Array([caster.global_position])
	var current: Node2D = target
	var i := 0
	while current != null:
		# pozicia PRED damage — ciel moze na zasah zomriet
		var pos := current.global_position
		var dmg := skill_damage(attack_power, damage_pct * pow(1.0 - falloff, i))
		hit.append(current)
		damages.append(dmg)
		points.append(pos)
		if current.has_method("take_damage"):
			current.take_damage(dmg)
		if is_alive(current):
			if current.has_method("apply_stun"):
				current.apply_stun(stun)
			if current.has_method("interrupt_shot"):
				current.interrupt_shot()
		i += 1
		if i > jumps:
			break
		current = find_nearest_target(pos, jump_range, enemy_team, hit)

	_spawn_chain_fx(points)
	DebugLog.info("skill", "team=%s id=%s hits=%d dmg=%s" % [caster_team, skill.id, hit.size(), str(damages)])
	return true

# Poseidon — Tidal Wave. Instantny kuzel pred Poseidonom (jeden frame, bez RNG).
# Ciel castu urcuje LEN smer kuzela. Zasah = nepriatel v wave_range (center-to-
# center) a v uhle cone_angle. Kazdy zasah: plny damage (bez falloffu), potom ak
# este zije slow a knockback radialne od Poseidona. Veze/bazy knockback nemaju
# (has_method ich preskoci), bazy nie su ani v registri.
static func _tidal_wave(skill: SkillData, caster: Node2D, caster_team: String, target: Node2D, attack_power: int) -> bool:
	if not is_alive(target) or not is_instance_valid(caster):
		return false
	var origin := caster.global_position
	var dir := target.global_position - origin
	dir = Vector2.RIGHT if dir.length_squared() < 0.0001 else dir.normalized()
	var damage_pct := skill.get_value(&"damage_pct")
	var cone_angle := skill.get_value(&"cone_angle")
	var wave_range := skill.get_value(&"wave_range")
	var knockback := skill.get_value(&"knockback")
	var slow_pct := skill.get_value(&"slow_pct")
	var slow_duration := skill.get_value(&"slow_duration")
	# kluc v .tres zamerne nie je — 0.2 s je prvy pass
	var knockback_time := skill.get_value(&"knockback_time", 0.2)
	var cos_half := cos(deg_to_rad(cone_angle / 2.0))
	var dmg := skill_damage(attack_power, damage_pct)

	var damages: Array[int] = []
	for n in BattleManager.get_targets_in_radius(origin, wave_range, enemy_team_of(caster_team)):
		if not is_alive(n):
			continue
		var to: Vector2 = n.global_position - origin
		var push_dir := dir
		if to.length_squared() >= 0.0001:
			push_dir = to.normalized()
			if dir.dot(push_dir) < cos_half:
				continue
		n.take_damage(dmg)
		damages.append(dmg)
		if is_alive(n) and n.has_method("apply_slow"):
			n.apply_slow(1.0 - slow_pct / 100.0, slow_duration)
		if is_alive(n) and n.has_method("apply_knockback"):
			n.apply_knockback(push_dir, knockback, knockback_time)

	_spawn_tidal_fx(origin, dir, wave_range, cone_angle)
	DebugLog.info("skill", "team=%s id=%s hits=%d dmg=%s" % [caster_team, skill.id, damages.size(), str(damages)])
	return true

static func _spawn_tidal_fx(origin: Vector2, dir: Vector2, radius: float, angle_deg: float) -> void:
	if BattleManager.arena_root == null:
		return
	var fx := TidalWaveFx.new()
	fx.setup(origin, dir, radius, angle_deg)
	BattleManager.arena_root.add_child.call_deferred(fx)

static func _spawn_chain_fx(points: PackedVector2Array) -> void:
	if BattleManager.arena_root == null:
		return
	var fx := ChainLightningFx.new()
	fx.setup(points)
	BattleManager.arena_root.add_child.call_deferred(fx)
