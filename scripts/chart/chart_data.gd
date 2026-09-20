# chart_data.gd — Chart data model (class_name ChartData): holds parsed metadata,
# timed notes, shape outlines + timings, and per-shape colors. Provides helpers
# for note time/color, color-scheme parsing, and resolving the song file path.
# RETURN: notes, shapes, timings and per-shape colors
class_name ChartData
extends RefCounted

var metadata: Dictionary = {}
var notes: Array = []
var shapes: Array = []
var shape_times: Array = []
var shape_colors: Dictionary = {}
var chart_path := ""
# Parallel to shapes/shape_times: shape_ids[i] is the id for shapes[i].
var shape_ids: Array = []
# id -> index into shapes/shape_times/shape_ids. Built once at load.
var shape_index_by_id: Dictionary = {}
# id -> {shape_idx, start_ms, end_ms, color, count}. Built once at load so
# the scheduler never filters/scans notes at runtime.
var shape_groups: Dictionary = {}


func is_empty() -> bool:
	return metadata.is_empty() and notes.is_empty() and shapes.is_empty()


func note_time(index: int) -> float:
	if index < 0 or index >= notes.size():
		return 0.0
	var note: Dictionary = notes[index]
	return float(note.get("start_time", note.get("time", 0.0)))


func note_color(index: int) -> Color:
	if index < 0 or index >= notes.size():
		return Color.WHITE
	var note: Dictionary = notes[index]
	return shape_colors.get(str(note.get("id", "")), Color.WHITE)


## Gives every distinct shape id one color, cycling through the chart's
## optional "color_scheme" metadata (e.g. ["#EEB8C4", "#E6D47B", ...]).
## Falls back to a random vivid color per id when no valid scheme exists.
func build_shape_colors() -> void:
	var scheme := _parse_color_scheme(str(metadata.get("color_scheme", "")))
	var next := 0
	for note in notes:
		var id := str(note.get("id", ""))
		if shape_colors.has(id):
			continue
		if scheme.is_empty():
			shape_colors[id] = Color.from_hsv(randf(), randf_range(0.6, 0.85), 1.0)
		else:
			shape_colors[id] = scheme[next % scheme.size()]
			next += 1


static func _parse_color_scheme(raw: String) -> Array[Color]:
	var colors: Array[Color] = []
	for part in raw.trim_prefix("[").trim_suffix("]").split(",", false):
		var token: String = part.strip_edges()
		token = token.trim_prefix('"').trim_prefix("'")
		token = token.trim_suffix('"').trim_suffix("'")
		var c := Color.from_string(token, Color.TRANSPARENT)
		if c != Color.TRANSPARENT:
			colors.append(c)
	return colors


func shape_time(index: int) -> Array:
	if index < 0 or index >= shape_times.size():
		return [0.0, 0.0]
	return shape_times[index]


## One-time runtime index built at load: id -> shape lookup + per-shape
## start/end/color/count. Single O(n) pass so gameplay never scans.
func build_runtime_index() -> void:
	shape_index_by_id.clear()
	shape_groups.clear()
	for i in range(shapes.size()):
		var sid := str(shape_ids[i]) if i < shape_ids.size() else ""
		# First occurrence wins; ids must be unique per chart spec.
		if not sid.is_empty() and not shape_index_by_id.has(sid):
			shape_index_by_id[sid] = i
	var counts := {}
	for note in notes:
		var nid := str((note as Dictionary).get("id", ""))
		counts[nid] = int(counts.get(nid, 0)) + 1
	for sid in shape_index_by_id:
		var idx: int = shape_index_by_id[sid]
		var st: Array = shape_time(idx)
		shape_groups[sid] = {
			"shape_idx": idx,
			"start_ms": float(st[0]),
			"end_ms": float(st[1]),
			"color": shape_colors.get(sid, Color.WHITE),
			"count": int(counts.get(sid, 0)),
		}


func note_count() -> int:
	return notes.size()


## True when any note belongs to a solo/unsetup shape (incomplete chart).
func is_incomplete() -> bool:
	for note in notes:
		if ChartParser.is_solo_id(str((note as Dictionary).get("id", ""))):
			return true
		if str((note as Dictionary).get("id", "")).strip_edges().is_empty():
			return true
	return false
func shape_count() -> int:
	return shapes.size()


func get_note(index: int) -> Dictionary:
	return notes[index] as Dictionary


func shape_points_at(index: int) -> PackedVector2Array:
	return shapes[index] as PackedVector2Array


func shape_points_by_id(shape_id: String) -> PackedVector2Array:
	if not shape_index_by_id.has(shape_id):
		return PackedVector2Array()
	return shapes[int(shape_index_by_id[shape_id])] as PackedVector2Array


func shape_group(shape_id: String) -> Dictionary:
	return shape_groups.get(shape_id, {}) as Dictionary


func song_path() -> String:
	var song := str(metadata.get("song", ""))
	if song.is_empty() or song.begins_with("res://") or song.begins_with("user://"):
		return song
	if chart_path.is_empty():
		return song
	return chart_path.get_base_dir().path_join(song)


func preview_start() -> float:
	return float(metadata.get("preview_start", 0.0)) / 1000.0


func get_bpm() -> float:
	return float(metadata.get("bpm", 0.0)) / 60.0


func beat_offset() -> float:
	return float(metadata.get("beat0", 0.0)) / 1000.0


func get_od() -> float:
	return float(metadata.get("overall_difficulty", 0.0)) / 1000.0


func get_song_title() -> String:
	return metadata.get("name", "")


func get_song_source() -> String:
	return metadata.get("source", "")


func get_mapper() -> String:
	return metadata.get("mapper", "")

func get_video_background() -> String:
	var video_bg := str(metadata.get("video_bg", ""))
	if video_bg.is_empty() or video_bg.begins_with("res://") or video_bg.begins_with("user://"):
		return video_bg
	if chart_path.is_empty():
		return video_bg
	return chart_path.get_base_dir().path_join(video_bg)

func get_bg() -> String:
	var bg := str(metadata.get("bg", ""))
	if bg.is_empty() or bg.begins_with("res://") or bg.begins_with("user://"):
		return bg
	if chart_path.is_empty():
		return bg
	return chart_path.get_base_dir().path_join(bg)
