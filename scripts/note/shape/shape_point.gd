extends ColorRect
var hit_time: float = 0.0
var receptor_x: float = 0.0
var px_per_sec: float = 600.0
var song_time: Callable
var max_width = Transform2D().scaled(Vector2(40.0, 40.0))
@onready var line2D: Line2D = $Line2D


func init(points: PackedVector2Array):
	line2D.points = points * max_width


func _process(_delta: float) -> void:
	position.x = receptor_x + (hit_time - song_time.call()) * px_per_sec
