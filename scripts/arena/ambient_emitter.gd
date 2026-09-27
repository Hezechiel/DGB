extends Node2D
class_name AmbientEmitter

# Ambient zvuk mapy — umiestneny RUCNE v scene mapy (pod uzlom "Ambient"),
# rovnako ako veze/pody. Zije so scenou mapy: koniec zapasu / zmena sceny ho
# uprace bez akehokolvek reset kodu. Pauzuje sa spolu s hrou (dedi process_mode).
#   LOOP   = podklad (bed) — vlastny AudioStreamPlayer, hra stale, NIE cez SFX pool
#            (loop by navzdy blokoval hlas v poole a steal by ho umlcal).
#   RANDOM = one-shot cez AudioManager.play_sfx() v nahodnych intervaloch.
# Pozicia uzla sa pouzije len ak SoundData.positional = true.

enum Mode { LOOP, RANDOM }

@export var sound_id: StringName
@export var mode: Mode = Mode.RANDOM
# RANDOM: dalsi one-shot o nahodny cas z <min, max> sekund.
@export var min_interval: float = 15.0
@export var max_interval: float = 35.0
# RANDOM: prvy one-shot az po nahodnom oneskoreni — nie hned pri nacitani mapy.
@export var first_delay_min: float = 5.0
@export var first_delay_max: float = 15.0
# LOOP: nabeh hlasitosti podkladu pri starte zapasu.
@export var loop_fade_in: float = 2.0

var _left: float = 0.0
var _bed: AudioStreamPlayer = null

func _ready() -> void:
	if mode == Mode.LOOP:
		set_process(false)
		_start_bed()
	else:
		_left = randf_range(first_delay_min, first_delay_max)

func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = randf_range(min_interval, max_interval)
	AudioManager.play_sfx(sound_id, global_position)

func _start_bed() -> void:
	var def := AudioManager.get_sound(sound_id)
	if def == null or def.streams.is_empty():
		return  # get_sound uz varoval / asset chyba — mapa ostane bez podkladu
	_bed = AudioStreamPlayer.new()
	_bed.bus = def.bus
	_bed.stream = def.streams.pick_random()
	if "loop" in _bed.stream and not _bed.stream.loop:
		push_warning("AmbientEmitter: '%s' stream nema loop=true — bed sa po jednom prehrati zastavi" % sound_id)
	add_child(_bed)
	_bed.volume_linear = 0.0
	_bed.play()
	create_tween().tween_property(_bed, "volume_linear", db_to_linear(def.volume_db), loop_fade_in)
