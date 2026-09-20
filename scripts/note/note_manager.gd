# note_manager.gd — Scrolling-note spawner facade: computes lane length from
# spawner-to-receptor distance for sync timing and forwards spawn() calls to
# the beat column with hit time, scroll speed and color.
# RETURN: scrolling beat notes spawned down the lane
extends Node2D

@export var px_per_sec := 400.0

@onready var shape_column: Node2D = $shape_column
@onready var beat_column: Node2D = $beat_column
@onready var receptor = $beat_column/beat_receptor
@onready var spawner: Node2D = $beat_column/beat_spawner


func lane_length() -> float:
	return spawner.position.x - receptor.position.x


func spawn(hit_time: float, color: Color = Color.WHITE, beat_id: String = ""):
	beat_column.spawn_beat(hit_time, receptor.position.x, px_per_sec, color, beat_id)


func spawn_shape(
	width: float,
	line_points: PackedVector2Array,
	hit_time: float,
	color: Color = Color.WHITE,
):
	shape_column.spawn_beat(width, line_points, hit_time, receptor.position.x, px_per_sec, color)
