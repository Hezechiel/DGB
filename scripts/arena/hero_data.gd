extends Resource
class_name HeroData

# Resource je ZDIELANY medzi hrdinami — runtime HP sa nikdy nezapisuje spat.
# sidekick companion field pride v buducom kroku.

@export var id: StringName
@export var display_name: String
@export var max_hp: int = 500
@export var speed: float = 70.0
@export var attack_range: float = 80.0
# Cas OD SKONCENIA cast-pointu (attack_left animacie) po dalsi mozny
# utok. NIE celkovy cyklus — ten je vzdy cast_point + recovery_time,
# kde cast_point sa pocita live z aktualnej attack_left animacie
# (frame_count/speed). Zmena fps/poctu snimkov attack_left tak nikdy
# nevyzaduje pretuning tejto hodnoty.
@export var recovery_time: float = 0.4
@export var projectile_damage: int = 25
@export var projectile_scene: PackedScene
@export var sprite_frames: SpriteFrames

enum AttackType { RANGED, MELEE }

@export var attack_type: AttackType = AttackType.RANGED
@export var can_move_while_attacking: bool = false
@export var attack_sound: AudioStream
