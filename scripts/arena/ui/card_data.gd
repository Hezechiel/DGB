extends Resource
class_name CardData

@export var id: StringName
@export var display_name: String
@export var cost: int = 1
@export var scroll_texture: Texture2D
@export var unit_data: UnitData

# PLACEHOLDER: faction filtering comes in a later step.
@export var faction: StringName
