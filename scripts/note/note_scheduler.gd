# spawns scrolling notes in sync with playback position
# Optimized: chart is treated as immutable. Note/shape consumption uses
# integer cursors (no remove_at(0), no per-spawn filter scan), shape data
# comes from ChartData.shape_groups (pre-grouped at load, id-mapped so the
# old shapes[0] bug is gone), and lane lead time is cached on start().
class_name NoteScheduler
extends Resource

const SHAPE_BASE_WIDTH_PX := 42.0

var playing = false
var _shape_spawned := false
var last_shape_id: String = ""

var _note_cursor := 0
var _shape_cursor := 0
var _lead := 0.0
var _cached_px_per_sec := -1.0
var _cached_lane_length := 0.0


func start(note_manager: Node2D = null):
	playing = true
	_note_cursor = 0
	_shape_cursor = 0
	_shape_spawned = false
	last_shape_id = ""
	if note_manager != null:
		_refresh_lead(note_manager)


func _refresh_lead(note_manager: Node2D) -> void:
	_cached_lane_length = note_manager.lane_length()
	_cached_px_per_sec = note_manager.px_per_sec
	_lead = _cached_lane_length / _cached_px_per_sec if _cached_px_per_sec > 0.0 else 0.0


func process(
	note_manager: Node2D, music: AudioStreamPlayer, charts: ChartData, target_shape: Line2D
):
	if playing == false:
		return
	if charts == null:
		return
	# Lead is static after layout; only recompute if scroll speed changed.
	if note_manager.px_per_sec != _cached_px_per_sec:
		_refresh_lead(note_manager)

	var playback_pos = music.get_playback_position()

	while _note_cursor < charts.note_count() and playback_pos >= charts.note_time(_note_cursor) / 1000.0 - _lead:
		var note: Dictionary = charts.get_note(_note_cursor)
		var current_id := str(note.get("id", ""))
		var hit_sec: float = float(note.get("start_time", note.get("time", 0.0))) / 1000.0
		var color: Color = charts.shape_colors.get(current_id, Color.WHITE)
		note_manager.spawn(hit_sec, color)

		if current_id != last_shape_id:
			var group: Dictionary = charts.shape_group(current_id)
			if not group.is_empty():
				var width_px: float = (float(group["end_ms"]) - float(group["start_ms"])) / 1000.0 * note_manager.px_per_sec
				note_manager.spawn_shape(
					SHAPE_BASE_WIDTH_PX + width_px,
					charts.shape_points_at(int(group["shape_idx"])),
					hit_sec,
					color
				)
				last_shape_id = current_id

		_note_cursor += 1

	while _shape_cursor < charts.shape_count():
		var shape_time: Array = charts.shape_time(_shape_cursor)

		if playback_pos >= float(shape_time[0]) / 1000.0 and not _shape_spawned:
			target_shape.change(charts.shape_points_at(_shape_cursor))
			_shape_spawned = true

		if playback_pos >= float(shape_time[1]) / 1000.0:
			_shape_cursor += 1
			_shape_spawned = false  # reset for the NEXT shape
		else:
			break
	pass


func end():
	playing = false
	pass
