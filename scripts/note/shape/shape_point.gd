extends ColorRect

var max_width = Transform2D().scaled(Vector2(40.0, 40.0))
@onready var line2D: Line2D = $Line2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func init(points: PackedVector2Array):
	line2D.points = points * max_width
