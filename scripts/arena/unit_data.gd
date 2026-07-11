extends Resource
class_name UnitData

# Resources su ZDIELANE medzi vsetkymi spawnutymi instanciami — runtime stav
# (hp a pod.) sa NIKDY nezapisuje spat do resource, len do instancie uzlu.

@export var id: StringName
@export var display_name: String
@export var archetype_scene: PackedScene      # melee_unit.tscn atd.
@export var max_hp: int = 50
@export var damage: int = 10
@export var attack_cooldown: float = 1.2
@export var speed: float = 35.0
@export var target_filter: int = 0            # mapuje sa na unit.gd TargetFilter enum
@export var sprite_frames: SpriteFrames
