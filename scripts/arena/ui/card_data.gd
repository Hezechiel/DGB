extends Resource
class_name CardData

@export var id: StringName
@export var display_name: String
@export var cost: int = 1
@export var scroll_texture: Texture2D

# PLACEHOLDER: gameplay wiring (unit spawning, faction filtering) comes in
# a later step — these fields are declared but unused for now.
@export var unit_scene: PackedScene
@export var faction: StringName
