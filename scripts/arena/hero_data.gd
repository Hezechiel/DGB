extends Resource
class_name HeroData

# Resource je ZDIELANY medzi hrdinami — runtime HP sa nikdy nezapisuje spat.
# sidekick companion field pride v buducom kroku.

@export var id: StringName
@export var display_name: String
@export var max_hp: int = 500
@export var speed: float = 70.0
@export var attack_range: float = 80.0
# Cas OD DAMAGE POINTU (nie od konca animacie) po dalsi mozny utok.
# NIE celkovy cyklus — ten je vzdy cast_point_do_damage_pointu +
# recovery_time, kde cast_point sa pocita live z aktualnej attack_left
# animacie (frame_count/speed). Zmena fps/poctu snimkov attack_left tak
# nikdy nevyzaduje pretuning tejto hodnoty.
@export var recovery_time: float = 0.4
# Zlomok (0-1) live cast-pointu (attack_left frame_count/speed) — po tuto
# cast pada zasah. Pred dosiahnutim tohto zlomku hrdina este "nie je
# zaviazany": novy prikaz hraca/AI utok cely zrusi (bez damage). Po
# dosiahnuti tohto bodu zasah dopadne a pohyb sa odomkne okamzite,
# bez ohladu na dlzku celej animacie — recovery_time teraz plynie
# OD TOHTO bodu, nie od konca animacie.
# Nizsie hodnoty (~0.3-0.5) = rychly, lahko zrusitelny utocnik
# (napr. Artemis); vyssie (~0.8-1.0) = pomaly, zaviazany utocnik,
# ktoreho zamach je tazke prerusit (napr. Hephaestus).
@export_range(0.0, 1.0, 0.01) var damage_point_ratio: float = 0.7
@export var projectile_damage: int = 25
@export var projectile_scene: PackedScene
@export var sprite_frames: SpriteFrames

enum AttackType { RANGED, MELEE }

@export var attack_type: AttackType = AttackType.RANGED
@export var can_move_while_attacking: bool = false
@export var attack_sound: AudioStream
