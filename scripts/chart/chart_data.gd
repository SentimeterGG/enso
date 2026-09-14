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
