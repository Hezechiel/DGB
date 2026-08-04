extends StaticBody2D
## Generic static map obstacle (rock, wall, tree, etc.)
## One script + one base scene drives every obstacle variant.
## Variants are made by duplicating Obstacle.tscn (or making an inherited
## scene) and just changing the exported values below in the Inspector —
## no new script needed per obstacle type.

## Visual sprite. Swap per variant (rock texture, wall texture, tree texture...).
@export var texture: Texture2D:
	set(value):
		texture = value
		if is_inside_tree():
			_apply_texture()

## Where sprite is drawn relative to the collision body. Useful for tall
## obstacles like trees, where the trunk base (collision) sits lower than
## the visual sprite center.
@export var sprite_offset: Vector2 = Vector2.ZERO:
	set(value):
		sprite_offset = value
		if is_inside_tree():
			_sprite.position = sprite_offset

## Footprint used for both collision and unit-pathing avoidance.
## Keep this close to the *base* of the art (e.g. trunk, not the tree crown)
## so units path around the physical obstacle, not the whole sprite.
@export var collision_size: Vector2 = Vector2(16, 16):
	set(value):
		collision_size = value
		if is_inside_tree():
			_apply_collision_size()

## Off for obstacles that are visual-only (e.g. decorative grass patch)
## but should still be excluded from deploy validity checks. On for
## anything that should physically block movement and projectiles.
@export var blocks_movement: bool = true:
	set(value):
		blocks_movement = value
		if is_inside_tree():
			collision_layer = 4 if blocks_movement else 0 # bit 3 "structures"

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 4 if blocks_movement else 0 # "structures" layer
	collision_mask = 0 # obstacles are static; they don't need to detect anything
	if not _collision.shape:
		_collision.shape = RectangleShape2D.new()
	_apply_texture()
	_apply_collision_size()
	_sprite.position = sprite_offset


func _apply_texture() -> void:
	if _sprite:
		_sprite.texture = texture


func _apply_collision_size() -> void:
	if _collision and _collision.shape is RectangleShape2D:
		_collision.shape.size = collision_size
