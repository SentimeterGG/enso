@tool
extends Control

enum Shapes {
	CIRCLE,
	RECTANGLE,
	EXIT,
	PLAY,
	LINE,
}

@export var shape: Shapes = Shapes.RECTANGLE:
	set(value):
		shape = value
		update_line()

@export var shape_size: Vector2 = Vector2(40.0, 40.0):
	set(value):
		shape_size = value
		update_line()
@export var line_thickness: int = 5:
	set(value):
		line_thickness = value
		update_line()

@export var follow_anchor: bool = false:
	set(value):
		follow_anchor = value
		update_line()


func update_line():
	var raw_points: PackedVector2Array
	var max_width: Transform2D

	if follow_anchor:
		custom_minimum_size = Vector2(0.0, 0.0)
		custom_maximum_size = Vector2(-1, -1)
		max_width = Transform2D().scaled(size)
	else:
		custom_minimum_size = shape_size
		custom_maximum_size = shape_size
		max_width = Transform2D().scaled(shape_size)

	match shape:
		Shapes.RECTANGLE:
			raw_points = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]
		Shapes.PLAY:
			raw_points = [Vector2(0, 0), Vector2(1, 0.5), Vector2(0, 1), Vector2(0, 0)]
		Shapes.LINE:
			raw_points = [Vector2(0, 0.5), Vector2(1, 0.5)]
		Shapes.CIRCLE:
			var circle_points: PackedVector2Array
			var segments := 12
			for i in range(segments + 1):
				var angle := TAU * i / segments
				circle_points.append(Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * 0.5)
			raw_points = circle_points
		Shapes.EXIT:
			raw_points = [Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(0, 1)]
		_:
			raw_points = [Vector2(0, 0)]
	update_line_node(line_thickness, max_width * raw_points)


func update_line_node(thick: int, points: PackedVector2Array):
	if has_node("L"):
		%L.width = thick
		%L.points = points
