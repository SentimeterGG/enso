extends ColorRect
var max_width = Transform2D().scaled(Vector2(120.0, 120.0))
@onready var line2D: Line2D = $Line2D


func init(points: PackedVector2Array):
	line2D.points = points * max_width
