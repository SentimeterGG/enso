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
const _SONG_TIME_SNAP_THRESHOLD := 0.15
const _SONG_TIME_DEADZONE := 0.012
const _SONG_TIME_LERP_WEIGHT := 0.05
var _smooth_song_time := 0.0
var _song_time_initialized := false


func _ready() -> void:
	px_per_sec = Global.settingsData.scroll_speed


func lane_length() -> float:
	return spawner.position.x - receptor.position.x


func spawn(hit_time: float, color: Color = Color.WHITE, beat_id: String = ""):
	beat_column.spawn_beat(hit_time, receptor.position.x, px_per_sec, color, beat_id)


func _process(delta: float) -> void:
	_update_smooth_song_time(delta)


func spawn_shape(
	width: float,
	line_points: PackedVector2Array,
	hit_time: float,
	color: Color = Color.WHITE,
):
	shape_column.spawn_beat(width, line_points, hit_time, receptor.position.x, px_per_sec, color)


func _preroll_sec() -> float:
	var scene := %game
	if scene != null and scene.has_method("get_preroll_sec"):
		return float(scene.call("get_preroll_sec"))
	return 0.0


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
