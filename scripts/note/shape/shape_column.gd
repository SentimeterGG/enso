extends Node2D

const SHAPE_POINT := preload("res://scenes/shape_point.tscn")
const _SONG_TIME_SNAP_THRESHOLD := 0.15
const _SONG_TIME_DEADZONE := 0.012
const _SONG_TIME_LERP_WEIGHT := 0.05
var _smooth_song_time := 0.0
var _song_time_initialized := false


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


func _process(delta: float) -> void:
	_update_smooth_song_time(delta)


func _update_smooth_song_time(delta: float) -> void:
	if BgMusic.playing:
		var real_time := (
			BgMusic.get_playback_position()
			+ AudioServer.get_time_since_last_mix()
			- AudioServer.get_output_latency()
			+ _preroll_sec()
		)

		if not _song_time_initialized:
			_smooth_song_time = real_time
			_song_time_initialized = true
			return

		# always advance by delta first — this is what keeps it smooth
		_smooth_song_time += delta

		var error := real_time - _smooth_song_time
		if absf(error) > _SONG_TIME_SNAP_THRESHOLD:
			# big desync (seek/pause/resume) — snap immediately
			_smooth_song_time = real_time
		elif absf(error) > _SONG_TIME_DEADZONE:
			# small real drift — correct gently, don't chase every jitter
			_smooth_song_time += error * _SONG_TIME_LERP_WEIGHT
		# else: error is just mixer jitter noise — ignore it, keep the delta-driven value
	else:
		_song_time_initialized = false
		var scene := %game
		if scene != null and scene.has_method("get_virtual_song_time"):
			_smooth_song_time = float(scene.call("get_virtual_song_time"))
		else:
			_smooth_song_time = 0.0


func get_song_time() -> float:
	return _smooth_song_time


func _preroll_sec() -> float:
	var scene := %game
	if scene != null and scene.has_method("get_preroll_sec"):
		return float(scene.call("get_preroll_sec"))
	return 0.0
