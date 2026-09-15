extends Node2D

const SHAPE_POINT := preload("res://scenes/shape_point.tscn")


func spawn_beat(
	width: float,
	line_point: PackedVector2Array,
	hit_time: float,
	receptor_x: float,
	px_per_sec: float,
	color: Color = Color.WHITE
) -> void:
	var shape_point = SHAPE_POINT.instantiate()
	shape_point.hit_time = hit_time
	shape_point.receptor_x = receptor_x
	shape_point.px_per_sec = px_per_sec
	shape_point.song_time = get_song_time
	shape_point.color = color
	shape_point.size.x = width
	shape_point.position = $shape_spawner.position
	add_child(shape_point)
	shape_point.init(line_point)


func get_song_time() -> float:
	return BgMusic.get_playback_position()
