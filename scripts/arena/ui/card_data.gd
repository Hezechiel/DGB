extends Resource
class_name CardData

@export var id: StringName
@export var display_name: String
@export var cost: int = 1
@export var scroll_texture: Texture2D
@export var unit_data: UnitData

# Kolko jednotiek karta sumonuje (squad). 1 = jedna jednotka.
@export var unit_count: int = 1
# Polomer formacie pri unit_count > 1 (world units).
@export var formation_radius: float = 12.0

# PLACEHOLDER: faction filtering comes in a later step.
@export var faction: StringName
