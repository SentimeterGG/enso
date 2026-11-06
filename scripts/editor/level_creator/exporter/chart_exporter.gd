class_name ChartExporter
extends RefCounted

## Writes .enso chart folders from the current editor state.

signal export_requested(dest_dir: String)
signal toast_requested(
	title: String,
	message: String,
	kind: NotificationToast.Kind,
	duration: float,
)

var _metadata_group: Control
var _mapping_group: Control


func _init(metadata_group: Control, mapping_group: Control) -> void:
	_metadata_group = metadata_group
	_mapping_group = mapping_group


func _toast(
	title: String,
	message: String,
	kind: NotificationToast.Kind,
	duration: float = -1.0,
) -> void:
	toast_requested.emit(title, message, kind, duration)


func export_to(dir: String) -> void:
	var context := _build_export_context(dir)
	if context.is_empty():
		return
	var written := _write_difficulty_files(context)
	_notify_export_result(context["diffs"], written, context["folder_name"])


func _build_export_context(dir: String) -> Dictionary:
	if dir.is_empty():
		_fail_export("Invalid export folder.", true)
		return { }
	export_requested.emit(dir)
	if _metadata_group == null or not _metadata_group.has_method("when_export"):
		_fail_export("METADATA missing when_export().", true)
		return { }
	if _mapping_group == null or not _mapping_group.has_method("get_difficulties_data"):
		_fail_export("MAPPING missing get_difficulties_data().", true)
		return { }

	var diffs: Dictionary = _mapping_group.get_difficulties_data()
	if diffs.is_empty():
		_toast(
			"Difficulty Missing",
			"Add at least one difficulty before exporting.",
			NotificationToast.Kind.WARN,
		)
		return { }

	var data: Dictionary = _metadata_group.when_export()
	var song_info := _normalized_song_info(data)
	var folder_name := _sanitize_folder_name(
		"%s by %s mapped by %s" % [song_info["name"], song_info["author"], song_info["mapper"]]
	)
	var out_dir := dir.path_join(folder_name)
	if not _ensure_export_folder(out_dir):
		return { }
	var assets := _copy_export_assets(data, out_dir)
	return {
		"diffs": diffs,
		"data": data,
		"folder_name": folder_name,
		"out_dir": out_dir,
		"song_file": assets["song_file"],
		"bg_value": assets["bg_value"],
		"video_value": assets["video_value"],
	}


func _normalized_song_info(data: Dictionary) -> Dictionary:
	return {
		"name": _text_or_default(data, "name", "untitled"),
		"author": _text_or_default(data, "source", "unknown"),
		"mapper": _text_or_default(data, "mapper", "unknown"),
	}


func _text_or_default(data: Dictionary, key: String, fallback: String) -> String:
	var value := str(data.get(key, "")).strip_edges()
	return fallback if value.is_empty() else value


func _ensure_export_folder(out_dir: String) -> bool:
	if DirAccess.dir_exists_absolute(out_dir):
		return true
	var err := DirAccess.make_dir_recursive_absolute(out_dir)
	if err == OK:
		return true
	push_error("Failed to create folder: " + out_dir + " " + error_string(err))
	_fail_export("Failed to create folder.")
	return false


func _copy_export_assets(data: Dictionary, out_dir: String) -> Dictionary:
	var song_file := "song.mp3"
	var src_song := str(data.get("song_src", "")).strip_edges()
	if not src_song.is_empty():
		song_file = _resolve_song_filename(src_song)
		_copy_song_into(src_song, out_dir.path_join(song_file))
	return {
		"song_file": song_file,
		"bg_value": _copy_optional_asset(str(data.get("bg", "")), out_dir),
		"video_value": _copy_optional_asset(str(data.get("video_bg", "")), out_dir),
	}


func _copy_optional_asset(src: String, out_dir: String) -> String:
	var path := src.strip_edges()
	if path.is_empty():
		return ""
	var file_name := _resolve_song_filename(path)
	_copy_song_into(path, out_dir.path_join(file_name))
	return "./" + file_name


func _write_difficulty_files(context: Dictionary) -> Array[String]:
	var written: Array[String] = []
	for diff_name in (context["diffs"] as Dictionary).keys():
		if _write_difficulty_file(context, str(diff_name)):
			written.append(str(diff_name))
	return written


func _write_difficulty_file(context: Dictionary, diff_name: String) -> bool:
	var diffs: Dictionary = context["diffs"]
	var data: Dictionary = context["data"]
	var d: Dictionary = diffs[diff_name]
	var beats: Array = d.get("beats", [])
	var shapes: Array = d.get("shapes", [])
	var overall := int(d.get("overall_difficulty", int(data.get("overall_difficulty", 0))))
	var text := _build_metadata_text(
		data, "./" + str(context["song_file"]), context["bg_value"], context["video_value"], overall
	)
	text += _build_notes_text(beats, shapes)
	var file_name := _sanitize_difficulty_filename(diff_name) + ".enso"
	var chart_path: String = (context["out_dir"] as String).path_join(file_name)
	var err := _write_text_file(chart_path, text)
	if err == OK:
		return true
	push_error("Failed to write chart: " + chart_path + " " + error_string(err))
	_fail_export("Failed to write %s." % file_name)
	return false


func _write_text_file(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


func _fail_export(message: String, log_error: bool = false) -> void:
	if log_error:
		push_error(message)
	_toast(
		"Export Failed",
		message,
		NotificationToast.Kind.WARN,
	)


func _resolve_song_filename(src: String) -> String:
	var s := src.strip_edges()
	if s.begins_with("res://") or s.begins_with("user://"):
		return s.get_file()
	return s.get_file().strip_edges()


func _resolve_song_abs(src: String) -> String:
	var s := src.strip_edges()
	if s.is_empty():
		return ""
	if s.begins_with("res://") or s.begins_with("user://"):
		return ProjectSettings.globalize_path(s)
	if s.begins_with("./") or s.begins_with("../") or not s.begins_with("/"):
		if s.begins_with("./"):
			s = s.substr(2)
		var proj := ProjectSettings.globalize_path("res://").path_join(s)
		if FileAccess.file_exists(proj):
			return proj
		return s
	return s


func _copy_song_into(src: String, dst: String) -> void:
	var abs_src := _resolve_song_abs(src)
	if abs_src.is_empty():
		return
	if abs_src == dst:
		return
	if not FileAccess.file_exists(abs_src) and not FileAccess.file_exists(src):
		push_error("Song file not found, skipping copy: " + src)
		return
	var read_path := abs_src if FileAccess.file_exists(abs_src) else src
	if DirAccess.copy_absolute(read_path, dst) == OK:
		return
	var data := FileAccess.get_file_as_bytes(read_path)
	if data.is_empty():
		push_error("Failed to read song file: " + read_path)
		return
	var out := FileAccess.open(dst, FileAccess.WRITE)
	if out == null:
		push_error("Failed to write song copy: " + dst)
		return
	out.store_buffer(data)
	out.close()


func _sanitize_folder_name(raw: String) -> String:
	var bad := ["/", "\\", ":", "*", "?", '"', "<", ">", "|"]
	var out := raw.strip_edges()
	for ch in bad:
		out = out.replace(ch, "_")
	out = out.strip_edges().rstrip(".")
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.is_empty():
		out = "untitled"
	if out.length() > 120:
		out = out.substr(0, 120).strip_edges()
	return out


func _sanitize_difficulty_filename(raw: String) -> String:
	var bad := ["/", "\\", ":", "*", "?", '"', "<", ">", "|", " "]
	var out := raw.strip_edges().to_lower()
	for ch in bad:
		out = out.replace(ch, "_")
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().rstrip(".").rstrip("_")
	if out.is_empty():
		out = "difficulty"
	return out


func _build_metadata_text(
	data: Dictionary,
	song_value: String,
	bg_value: String = "",
	video_value: String = "",
	overall_difficulty_override: int = -1,
) -> String:
	var colors_str := _format_color_scheme(data.get("color_scheme", []))
	var overall := _resolve_overall_difficulty(data, overall_difficulty_override)
	var text := (
		"[metadata]\nname = %s\nsource = %s\nmapper = %s\nsong = %s\ncolor_scheme = %s\npreview_start = %d\nbpm = %d\nbeat0 = %d\noverall_difficulty = %d\n"
		% [
			str(data.get("name", "")),
			str(data.get("source", "")),
			str(data.get("mapper", "")),
			song_value,
			colors_str,
			int(data.get("preview_start", 0)),
			int(data.get("bpm", 120)),
			int(data.get("beat0", 0)),
			overall,
		]
	)
	if not bg_value.is_empty():
		text += "bg = %s\n" % bg_value
	if not video_value.is_empty():
		text += "video_bg = %s\n" % video_value
	text += "\n[notes]\n"
	return text


func _format_color_scheme(colors: Array) -> String:
	var quoted := colors.map(
		func(c):
			return '"' + str(c) + '"',
	)
	return "[" + ", ".join(quoted) + "]"


func _resolve_overall_difficulty(data: Dictionary, override: int) -> int:
	if override >= 0:
		return override
	return int(data.get("overall_difficulty", 0))


func _build_notes_text(beats: Array, shapes: Array) -> String:
	var out := ""
	var used: Dictionary = { }
	var id_counts: Dictionary = { }
	for shape in _shapes_sorted_by_first_time(shapes):
		var shape_name := str(shape.get("shape", "Square"))
		var times := _sorted_shape_times(shape)
		if times.is_empty():
			continue
		var sid := _unique_shape_id(shape_name, id_counts)
		for t in times:
			used[int(t)] = true
		out += _shape_block(sid, shape_name, times, shape)
	out += _solo_blocks(beats, used)
	return "\n" if out.is_empty() else out


func _shapes_sorted_by_first_time(shapes: Array) -> Array:
	var ordered: Array = shapes.duplicate()
	ordered.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _first_shape_time(a) < _first_shape_time(b),
	)
	return ordered


func _first_shape_time(shape: Dictionary) -> int:
	var times: Array = shape.get("times_ms", [])
	if times.is_empty():
		return 9223372036854775807
	return int(times[0])


func _sorted_shape_times(shape: Dictionary) -> Array:
	var times: Array = (shape.get("times_ms", []) as Array).duplicate()
	times.sort()
	return times


func _unique_shape_id(shape_name: String, id_counts: Dictionary) -> String:
	var base := shape_name.to_lower().strip_edges().replace(" ", "_")
	if base.is_empty():
		base = "shape"
	var count := int(id_counts.get(base, 0)) + 1
	id_counts[base] = count
	return base if count == 1 else "%s_%d" % [base, count]


func _solo_blocks(beats: Array, used: Dictionary) -> String:
	var solo_beats: Array = []
	for b in beats:
		var bi := int(b)
		if not used.has(bi):
			solo_beats.append(bi)
	solo_beats.sort()
	var out := ""
	for i in range(solo_beats.size()):
		out += "[[solo_%d]]\n@ %d\n\n" % [i + 1, solo_beats[i]]
	return out


func _shape_block(
	sid: String,
	shape_name: String,
	times: Array,
	shape_dict: Dictionary = { },
) -> String:
	var pts := _shape_block_points(shape_dict, shape_name)
	if pts.is_empty():
		return ""
	var closed := _shape_is_closed(shape_dict, shape_name, pts)
	var block := ("[(%s)]\n" if closed else "[[%s]]\n") % sid
	for i in range(times.size()):
		block += _beat_coord_line(int(times[i]), _point_at(pts, i))
	if not closed and pts.size() > times.size():
		block += _tail_coord_line(_point_at(pts, times.size()))
	return block + "\n"


func _shape_block_points(shape_dict: Dictionary, shape_name: String) -> PackedVector2Array:
	var stored = shape_dict.get("points", PackedVector2Array())
	if stored is PackedVector2Array and (stored as PackedVector2Array).size() > 0:
		return stored as PackedVector2Array
	return _export_shape_points(shape_name)


func _shape_is_closed(
	shape_dict: Dictionary,
	shape_name: String,
	pts: PackedVector2Array,
) -> bool:
	if bool(shape_dict.get("closed", shape_name == "Square")):
		return true
	return pts.size() >= 3 and pts[0].is_equal_approx(pts[pts.size() - 1])


func _point_at(pts: PackedVector2Array, index: int) -> Vector2:
	var p := pts[index] if index < pts.size() else Vector2(0.5, 0.5)
	return Vector2(clampf(p.x, 0.0, 1.0), clampf(p.y, 0.0, 1.0))


func _beat_coord_line(time_ms: int, p: Vector2) -> String:
	return "@ %d %s %s\n" % [time_ms, _fmt_coord(p.x), _fmt_coord(p.y)]


func _tail_coord_line(p: Vector2) -> String:
	return "! %s %s\n" % [_fmt_coord(p.x), _fmt_coord(p.y)]


func _fmt_coord(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return ("%.3f" % v).rstrip("0").rstrip(".")


func _export_shape_points(shape_name: String) -> PackedVector2Array:
	return ShapeLibrary.points(shape_name)


func _notify_export_result(diffs: Dictionary, written: Array[String], folder_name: String) -> void:
	if written.is_empty():
		_toast(
			"Export failed",
			"No difficulty files were written.",
			NotificationToast.Kind.WARN,
		)
		return
	var totals := _export_totals(diffs, written)
	var title := 'Exported "%s"' % folder_name
	var names := ", ".join(written)
	if totals["solo"] > 0:
		_toast(
			title,
			"%s: %d beats, %d shapes. %d solo hidden from list."
			% [names, totals["beats"], totals["shapes"], totals["solo"]],
			NotificationToast.Kind.WARN,
			4.0,
		)
	else:
		_toast(
			title,
			"%s: %d beats, %d shapes." % [names, totals["beats"], totals["shapes"]],
			NotificationToast.Kind.SUCCESS,
		)


func _export_totals(diffs: Dictionary, written: Array[String]) -> Dictionary:
	var totals := { "beats": 0, "shapes": 0, "solo": 0 }
	for diff_name in written:
		var d: Dictionary = diffs.get(diff_name, { })
		var beats: Array = d.get("beats", [])
		var shapes: Array = d.get("shapes", [])
		totals["beats"] += beats.size()
		totals["shapes"] += shapes.size()
		totals["solo"] += _count_solo_beats(beats, shapes)
	return totals


func _count_solo_beats(beats: Array, shapes: Array) -> int:
	var used := { }
	for shape in shapes:
		for t in (shape as Dictionary).get("times_ms", []):
			used[int(t)] = true
	var solo := 0
	for b in beats:
		if not used.has(int(b)):
			solo += 1
	return solo
