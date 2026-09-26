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
	if BgMusic.playing:
		return BgMusic.get_playback_position() + _preroll_sec()
	var scene := %game
	if scene != null and scene.has_method("get_virtual_song_time"):
		return float(scene.call("get_virtual_song_time"))
	return 0.0


func _preroll_sec() -> float:
	var scene := %game
	if scene != null and scene.has_method("get_preroll_sec"):
		return float(scene.call("get_preroll_sec"))
	return 0.0
