extends Resource
class_name CardData

@export var id: StringName
@export var display_name: String
@export var cost: int = 1
@export var scroll_texture: Texture2D
# unit_data a spell_data su NAVZAJOM VYLUCNE — karta je unit karta ALEBO
# spell karta, nikdy oboje (CardDB._load_into to vynucuje pri skene).
@export var unit_data: UnitData
@export var spell_data: SpellData

# Kolko jednotiek karta sumonuje (squad). 1 = jedna jednotka.
@export var unit_count: int = 1
# Polomer formacie pri unit_count > 1 (world units).
@export var formation_radius: float = 12.0

# PLACEHOLDER: faction filtering comes in a later step.
@export var faction: StringName
