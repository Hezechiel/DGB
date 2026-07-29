extends Resource
class_name SpellData

# Resources su ZDIELANE medzi vsetkymi instanciami efektov — runtime stav
# sa NIKDY nezapisuje spat do resource, len do instancie uzlu.

# spell_type values (Prompt 2 will consume these): 0 = STORM, 1 = STUN, 2 = NET
# Zamerne plain int, NIE enum — cross-referencing autoload/resource enumov je
# v tomto projekte pasca (architecture.md: HeroAI.State poznamka o autoload
# enumoch nepouzitelnych ako typy).

@export var id: StringName
@export var display_name: String
@export var spell_type: int = 0   # mapuje sa na SpellType konvenciu vyssie
@export var radius: float = 40.0
# Predtym nez efekt dopadne — kruh je vidno ako varovanie, superov hrac
# ma sancu z oblasti odist. Stun ma najkratsi cas (ostava najrychlejsim
# reaktivnym nastrojom), Storm najdlhsi.
@export var cast_time: float = 0.5
# Ako dlho zona ZIJE na mape. 0.0 = jediny tick presne v momente dopadu
# (Stun/Net sa takto spravaju "instantne" bez samostatnej vetvy v kode).
@export var zone_duration: float = 0.0
# Ako dlho efekt (stun/root/slow) drzi NA ZASIAHNUTEJ jednotke. Pri Storme
# sa obnovuje kazdy tick — stat v zone = ostat spomaleny, odist = slow
# dobehne a zmizne (zamerny "reziduálny" efekt).
@export var effect_duration: float = 1.0
@export var damage: int = 0
@export var tick_interval: float = 0.5
# Nasobic rychlosti pre Storm slow (0.5 = polovicna rychlost). Vsetky
# ciselne hodnoty su exportovane, ziadne hardcoded konstanty v kode.
@export var slow_multiplier: float = 0.5
# Animacie zvitku pre tento spell. Nazvy animacii su KONTRAKT (rovnako
# ako pri jednotkach/hrdinoch):
#   "drag"  = pocas tahania karty nad mapou (deploy ghost)
#   "cast"  = pocas cast fazy na mieste dopadu
#   "spell" = samotny efekt na zemi pocas zone fazy
# Chybajuca animacia sa ticho preskoci (has_animation guard) — spell bez
# frames stale plne funguje, len sa vykresli placeholder kruh.
@export var sprite_frames: SpriteFrames
# Ako dlho ma bezat animacia efektu pri INSTANTNOM spelle
# (zone_duration = 0.0 — granaty, stun, siet: efekt sa aplikuje raz v
# momente dopadu, zona nezije). Zona sama tikne jedinykrat, ale animacia
# musi byt vidiet. Pri zonovych spelloch (Storm) sa tato hodnota
# IGNORUJE — animacia tam trva presne zone_duration.
# Exportovane zamerne: cas sa ladi podla pocitu z animacie, nie kodom.
@export var impact_anim_duration: float = 0.5
