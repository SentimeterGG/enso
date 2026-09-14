extends Line2D

var max_width = Transform2D().scaled(Vector2(50.0, 50.0))


func change(new_points: PackedVector2Array):
	points = max_width * new_points
