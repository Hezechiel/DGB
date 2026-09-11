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

enum AttackType { MELEE, RANGED }
@export var attack_type: AttackType = AttackType.MELEE

@export var attack_range: float = 16.0

@export var projectile_scene: PackedScene   # pouzite len ked attack_type == RANGED

# Zlomok (0-1) live cast-pointu (attack animacie frame_count/speed) — po tuto
# hranicu zasah este nedopadol. `attack_cooldown` vyssie teraz hra tu istu
# rolu ako HeroData.recovery_time — je to cooldown PO dopade zasahu, nie
# celkova dlzka cyklu.
@export_range(0.0, 1.0, 0.01) var damage_point_ratio: float = 0.7
