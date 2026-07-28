extends Node2D
# Zona spell efektu — jeden mechanizmus pre VSETKY spelly.
# Faza CAST: len varovny kruh, ziadny efekt (superov hrac ma cas odist).
# Faza ZONE: kazdy tick si ZNOVU vypyta ciele v polomere (NIE snapshot!)
# a aplikuje efekt na toho, kto je v nej PRAVE TERAZ.
# zone_duration = 0.0 → jediny tick v momente dopadu (Stun/Net).
# Casovanie zije v tomto uzle, nie v autoloade — uzol je dieta areny,
# takze koniec zapasu / zmena sceny ho upratu automaticky.
# TODO: placeholder kruh nahradit realnymi animaciami (drag/cast/impact)
# az budu assety — samostatny krok.

const PHASE_CAST := 0
const PHASE_ZONE := 1

@export var color_cast := Color(0.9, 0.5, 0.1, 0.30)   # varovanie pocas castu
@export var color_zone := Color(0.6, 0.2, 0.9, 0.30)   # aktivna zona
@export var anim_scale: float = 0.25

var spell: SpellData = null
var caster_team: String = "player"
var _affected_team: String = "enemy"
var _phase: int = PHASE_CAST
var _cast_left: float = 0.0
var _zone_left: float = 0.0
var _tick_left: float = 0.0

# Volane PRED add_child() (spawn flow: instantiate → configure →
# add_child), rovnaky kontrakt ako unit.configure()/hero.configure().
func configure(data: SpellData, team: String, pos: Vector2) -> void:
	spell = data
	caster_team = team
	_affected_team = "player" if team == "enemy" else "enemy"
	_cast_left = data.cast_time
	global_position = pos

	# "cast" sa roztiahne tak, aby dobehla PRESNE v momente dopadu —
	# cast_time je balancne cislo, animacia sa mu prisposobi (nie naopak).
	# speed_scale sa nastavuje na UZLE, nikdy sa nemeni zdielany SpriteFrames.
	var anim: AnimatedSprite2D = $CastAnim
	anim.visible = false
	if data.sprite_frames != null and data.sprite_frames.has_animation(&"cast") and data.cast_time > 0.0:
		var fc := data.sprite_frames.get_frame_count(&"cast")
		var spd := data.sprite_frames.get_animation_speed(&"cast")
		if fc > 0 and spd > 0.0:
			var natural := float(fc) / spd
			anim.sprite_frames = data.sprite_frames
			anim.scale = Vector2(anim_scale, anim_scale)
			anim.speed_scale = natural / data.cast_time
			anim.visible = true
			anim.play(&"cast")

func _process(delta: float) -> void:
	if spell == null:
		return

	if _phase == PHASE_CAST:
		_cast_left -= delta
		if _cast_left <= 0.0:
			_phase = PHASE_ZONE
			$CastAnim.stop()
			$CastAnim.visible = false
			_zone_left = spell.zone_duration
			queue_redraw()
			_apply_tick()                 # prvy tick PRESNE v momente dopadu
			_tick_left = spell.tick_interval
			if _zone_left <= 0.0:
				queue_free()              # instantny spell (Stun/Net)
		return

	_zone_left -= delta
	_tick_left -= delta
	if _zone_left > 0.0 and _tick_left <= 0.0:
		_apply_tick()
		_tick_left = spell.tick_interval
	if _zone_left <= 0.0:
		queue_free()

# Znovu-dotaz na ciele KAZDY tick — jednotka ktora vojde neskor efekt
# dostane, jednotka ktora odide uz nie.
func _apply_tick() -> void:
	var targets := BattleManager.get_targets_in_radius(global_position, spell.radius, _affected_team)
	match spell.spell_type:
		0:  # STORM — damage + obnovenie kratkeho slow
			for n in targets:
				if is_instance_valid(n) and n.has_method("take_damage"):
					n.take_damage(spell.damage)
				if is_instance_valid(n) and n.has_method("apply_slow"):
					n.apply_slow(spell.slow_multiplier, spell.effect_duration)
		1:  # STUN
			for n in targets:
				if is_instance_valid(n) and n.has_method("apply_stun"):
					n.apply_stun(spell.effect_duration)
		2:  # NET (root)
			for n in targets:
				if is_instance_valid(n) and n.has_method("apply_root"):
					n.apply_root(spell.effect_duration)
		_:
			push_error("SpellZone: neznamy spell_type %d ('%s')" % [spell.spell_type, spell.id])

func _draw() -> void:
	if spell == null:
		return
	draw_circle(Vector2.ZERO, spell.radius, color_cast if _phase == PHASE_CAST else color_zone)
