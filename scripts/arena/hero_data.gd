extends Resource
class_name HeroData

# Resource je ZDIELANY medzi hrdinami — runtime HP sa nikdy nezapisuje spat.
# sidekick companion field pride v buducom kroku.

@export var id: StringName
@export var display_name: String
@export var max_hp: int = 500
@export var speed: float = 70.0
@export var attack_range: float = 80.0
@export var fire_cooldown: float = 0.5
@export var projectile_damage: int = 25
@export var projectile_scene: PackedScene
@export var sprite_frames: SpriteFrames
