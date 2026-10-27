@tool
extends Control

@export var aspect_ratio: float = 1.0:
	set(value):
		aspect_ratio = value
		update_size()

@export var follow_width: bool = false:
	set(value):
		follow_width = value
		update_size()

@export_tool_button("Calculate", "") var activate = update_size
@export_tool_button("Reset", "") var reset = set_size_to_old_size

var old_size: Vector2


func set_size_to_old_size():
	size = old_size


func update_size():
	old_size = size
	if follow_width:
		# Height is derived from width; width is free
		custom_minimum_size.y = size.x * aspect_ratio
		custom_maximum_size.y = size.x * aspect_ratio
	else:
		# Width is derived from height; height is free
		custom_minimum_size.x = size.y * aspect_ratio
		custom_maximum_size.x = size.y * aspect_ratio
