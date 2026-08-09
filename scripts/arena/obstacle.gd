@tool
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

## Which Shape2D this obstacle's collision uses. RECTANGLE/CIRCLE/CAPSULE are
## auto-built from the size fields below. CUSTOM leaves the CollisionShape2D
## child's shape exactly as you hand-assign it in the inherited scene (e.g. a
## rotated rectangle, a ConvexPolygonShape2D for an irregular rock outline) —
## the script never touches it, same non-destructive treatment as "texture".
enum ShapeType { RECTANGLE, CIRCLE, CAPSULE, CUSTOM }

@export var shape_type: ShapeType = ShapeType.RECTANGLE:
	set(value):
		shape_type = value
		if is_inside_tree():
			_apply_collision_shape()

## Footprint used for both collision and unit-pathing avoidance.
## Keep this close to the *base* of the art (e.g. trunk, not the tree crown)
## so units path around the physical obstacle, not the whole sprite.
## Only used when shape_type == RECTANGLE.
@export var collision_size: Vector2 = Vector2(16, 16):
	set(value):
		collision_size = value
		if is_inside_tree():
			_apply_collision_shape()

## Radius for CIRCLE and CAPSULE shape_type.
@export var collision_radius: float = 8.0:
	set(value):
		collision_radius = value
		if is_inside_tree():
			_apply_collision_shape()

## Height for CAPSULE shape_type only (total capsule length, including the
## rounded ends — same convention as Godot's own CapsuleShape2D).
@export var collision_height: float = 24.0:
	set(value):
		collision_height = value
		if is_inside_tree():
			_apply_collision_shape()

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
	_apply_collision_shape()
	_apply_texture()
	_sprite.position = sprite_offset
	if not Engine.is_editor_hint():
		collision_layer = 4 if blocks_movement else 0 # "structures" layer
		collision_mask = 0 # obstacles are static; they don't need to detect anything


func _apply_texture() -> void:
	# Only override the sprite's texture if this Obstacle's own "Texture"
	# export was set. This way, setting the texture directly on the child
	# Sprite2D node (the normal Godot workflow) is left alone and never
	# gets wiped out at runtime.
	if _sprite and texture != null:
		_sprite.texture = texture


func _apply_collision_shape() -> void:
	if not _collision:
		return
	# RECTANGLE/CIRCLE/CAPSULE always build a BRAND NEW shape instance here
	# (never resize the existing one in place). Obstacle.tscn's shape starts
	# as one shared sub-resource, and shared Shape2D resources silently
	# resize every instance that references them at once — this is what
	# keeps each obstacle's collision independent of every other one.
	match shape_type:
		ShapeType.RECTANGLE:
			var shape := RectangleShape2D.new()
			shape.size = collision_size
			_collision.shape = shape
		ShapeType.CIRCLE:
			var shape := CircleShape2D.new()
			shape.radius = collision_radius
			_collision.shape = shape
		ShapeType.CAPSULE:
			var shape := CapsuleShape2D.new()
			shape.radius = collision_radius
			shape.height = collision_height
			_collision.shape = shape
		ShapeType.CUSTOM:
			pass # hand-assigned directly on the CollisionShape2D child; leave it alone
