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
@export var spell_type: int = 0   # mapuje sa na SpellType konvenciu vyssie, efekt pride v Prompt 2
@export var radius: float = 40.0
@export var duration: float = 1.0
@export var damage: int = 0
@export var tick_interval: float = 0.5
