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
# Id-cka SoundData (data/sounds/) — prehravane cez AudioManager.play_sfx().
# attack_sfx hra v DAMAGE POINTE (dopad melee / vypustenie strely), nie na
# zaciatku svihu — zruseny windup tak nikdy nevyda zvuk. &"" = ticho.
@export var attack_sfx: StringName
@export var death_sfx: StringName
# Hlaska boha pri spawne/respawne LOKALNEHO hrdinu (len player.gd, nie
# hero_dummy). Id-cko SoundData na Voice buse (data/sounds/) — varianty
# zije v SoundData.streams, nikdy nie tu. &"" = ticho.
@export var spawn_voice: StringName

# --- Scrolls (zbierka kariet) metadata ---
# Bohovia su tiez karty: rovnake kody ako CardData. rarity 4 = UNIQUE.
@export var rarity: int = 4
@export var obtain_source: int = 0
# Panteon boha (greek, norse, ...) — rovnaky vyznam ako CardData.faction.
@export var faction: StringName = &"greek"
# Domena napriec panteonmi (olympus/sky, sea, underworld).
@export var domain: StringName
# --- Synergy: PODMIENKA (zlozenie balicka) -> BONUS pre vlastny panteon ---
# Podmienka: balicek obsahuje aspon synergy_count kariet so znackou
# synergy_tag, ktore su zaroven z panteonu boha. Rataju sa jednotky AJ
# spelly. Jeden prah na boha, ziadne stupne. Prazdny tag alebo count <= 0
# = boh nema synergy.
@export var synergy_tag: StringName
@export var synergy_count: int = 4
# Bonus pre karty z panteonu boha, ked je podmienka splnena. Kluc = efekt,
# hodnota = nasobic (1.1 = +10 %). Povolene kluce:
#   &"max_hp", &"damage", &"speed", &"attack_speed"  -> jednotky
#   &"spell_damage"                                  -> spelly
#   &"energy_regen"                                  -> regeneracia energie timu
# Chybajuci kluc = 1.0. Karty cudzieho panteonu bonus NEDOSTANU.
@export var synergy_bonuses: Dictionary = {}
# Znacky kariet, ktore tento boh ODMIETA v balicku. Prazdne = neutralny boh.
# Porovnava sa s CardData.tags + faction + domain karty.
@export var forbidden_tags: Array[StringName] = []
# Kratky popis pre flashcard (encyklopedia). Prazdny = nic sa nezobrazi.
@export_multiline var description: String = ""
