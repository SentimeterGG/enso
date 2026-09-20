extends Control

## IO controller for the level creator.
## Owns import/export dialogs + file/folder work and emits results to
## metadata.gd, which owns all UI widgets via when_import()/when_export().
signal chart_imported(chart: ChartData)
signal export_requested(dest_dir: String)

@onready var _name_edit: LineEdit = %SongNameEdit
@onready var _source_edit: LineEdit = %SongAuthorEdit
@onready var level_creator_group: Control = %LevelCreator
@onready var mapping_button: Button = %MappingButton
@onready var metadata_button: Button = %MetadataButton
@onready var _save_dialog: FileDialog = %ExportPopup
@onready var _import_dialog: FileDialog = %ImportPopup
@onready var metadata_group: Control = %METADATA
@onready var mapping_group: Control = $LevelCreator/MAPPING
@onready var _export_button: Button = %ExportButton
@onready var _draw: Line2D = $draw

var viewport_size: Vector2
var viewport_width: float

var _slide_tween: Tween
const SLIDE_DURATION := 0.35


func _ready() -> void:
	BgMusic.change_song(null)
	VolumePopup.hide_pop_up()
	viewport_size = get_viewport_rect().size
	viewport_width = viewport_size.x
	_sync_export_button()
	DiscordRPC.set_activity("Drawing a map", "")


func _process(_delta: float) -> void:
	_sync_export_button()


func _on_mapping_pressed() -> void:
	VolumePopup.can_popup = false
	mapping_button.disabled = true
	metadata_button.disabled = false
	_slide_to(-viewport_width)


func _on_metadata_pressed() -> void:
	VolumePopup.can_popup = true
	mapping_button.disabled = false
	metadata_button.disabled = true
	_slide_to(0.0)


func _slide_to(target_x: float) -> void:
	if _slide_tween:
		_slide_tween.kill()

	_slide_tween = create_tween()
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(level_creator_group, "position:x", target_x, SLIDE_DURATION)


## Export stays disabled until every required metadata field is filled
## (video_bg is the only optional one). Polls metadata so ColorRect
## add/remove (queue_free) needs no extra signal wiring.
func _sync_export_button() -> void:
	if _export_button == null or metadata_group == null:
		return
	if not metadata_group.has_method("is_export_ready"):
		return
	_export_button.disabled = not metadata_group.is_export_ready()


func _on_import_file_pressed() -> void:
	_import_dialog.popup_centered(Vector2i(600, 400))


func _on_import_popup_file_selected(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Invalid chart file: " + path)
		return

	var chart := ChartParser.load(path)
	if chart.is_empty() or chart.metadata.is_empty():
		push_error("No metadata found in chart: " + path)
		return

	chart_imported.emit(chart)


func _on_export_button_pressed() -> void:
	_save_dialog.popup_centered(Vector2i(600, 400))


func _on_export_popup_dir_selected(dir: String) -> void:
	if dir.is_empty():
		push_error("Invalid export folder.")
		return
	export_requested.emit(dir)
	if metadata_group == null or not metadata_group.has_method("when_export"):
		push_error("METADATA missing when_export().")
		return

	var data: Dictionary = metadata_group.when_export()
	var song_name := str(data.get("name", "")).strip_edges()
	var song_author := str(data.get("source", "")).strip_edges()
	var mapper := str(data.get("mapper", "")).strip_edges()
	if song_name.is_empty():
		song_name = "untitled"
	if song_author.is_empty():
		song_author = "unknown"
	if mapper.is_empty():
		mapper = "unknown"
	var folder_name := _sanitize_folder_name(
		"%s by %s mapped by %s" % [song_name, song_author, mapper]
	)
	var out_dir := dir.path_join(folder_name)
	if not DirAccess.dir_exists_absolute(out_dir):
		var err := DirAccess.make_dir_recursive_absolute(out_dir)
		if err != OK:
			push_error("Failed to create folder: " + out_dir + " " + error_string(err))
			return
	var src_song := str(data.get("song_src", "")).strip_edges()
	var song_file := "song.mp3"
	if not src_song.is_empty():
		song_file = _resolve_song_filename(src_song)
		_copy_song_into(src_song, out_dir.path_join(song_file))
	# Copy optional bg / video_bg next to the chart when they point at real files.
	var bg_value := ""
	var src_bg := str(data.get("bg", "")).strip_edges()
	if not src_bg.is_empty():
		var bg_file := _resolve_song_filename(src_bg)
		_copy_song_into(src_bg, out_dir.path_join(bg_file))
		bg_value = "./" + bg_file
	var video_value := ""
	var src_video := str(data.get("video_bg", "")).strip_edges()
	if not src_video.is_empty():
		var video_file := _resolve_song_filename(src_video)
		_copy_song_into(src_video, out_dir.path_join(video_file))
		video_value = "./" + video_file
	var mapping_beats: Array = []
	var mapping_shapes: Array = []
	if mapping_group != null:
		if mapping_group.has_method("get_beat_times_ms"):
			mapping_beats = mapping_group.get_beat_times_ms()
		if mapping_group.has_method("get_shapes"):
			mapping_shapes = mapping_group.get_shapes()
	var text := _build_metadata_text(data, "./" + song_file, bg_value, video_value)
	text += _build_notes_text(mapping_beats, mapping_shapes)
	var chart_path := out_dir.path_join("chart.enso")
	var f := FileAccess.open(chart_path, FileAccess.WRITE)
	if f == null:
		push_error(
			"Failed to write chart: " + chart_path + " " + error_string(FileAccess.get_open_error())
		)
		return
	f.store_string(text)
	f.close()


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


func _build_metadata_text(
	data: Dictionary, song_value: String, bg_value: String = "", video_value: String = ""
) -> String:
	var colors: Array = data.get("color_scheme", [])
	var colors_str := "[" + ", ".join(colors.map(func(c): return '"' + str(c) + '"')) + "]"
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
			int(data.get("overall_difficulty", 0)),
		]
	)
	if not bg_value.is_empty():
		text += "bg = %s\n" % bg_value
	if not video_value.is_empty():
		text += "video_bg = %s\n" % video_value
	text += "\n[notes]\n"
	return text


## Serializes editor beats + shapes into the [notes] section.
## Shapes are sorted by first beat; each gets a unique id; leftover solo
## beats (not in any shape) are exported as single-note [[solo_N]] shapes
## so no timing data is lost. Mirrors mapping.gd's _shape_points() geometry.
func _build_notes_text(beats: Array, shapes: Array) -> String:
	var out := ""
	var used: Dictionary = {}
	var ordered: Array = shapes.duplicate()
	ordered.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ta: Array = a.get("times_ms", [])
			var tb: Array = b.get("times_ms", [])
			var fa := int(ta[0]) if not ta.is_empty() else 9223372036854775807
			var fb := int(tb[0]) if not tb.is_empty() else 9223372036854775807
			return fa < fb
	)
	var id_counts: Dictionary = {}
	var idx := 0
	for shape in ordered:
		idx += 1
		var shape_name := str(shape.get("shape", "Square"))
		var times: Array = (shape.get("times_ms", []) as Array).duplicate()
		times.sort()
		if times.is_empty():
			continue
		var base := shape_name.to_lower().strip_edges().replace(" ", "_")
		if base.is_empty():
			base = "shape"
		var count := int(id_counts.get(base, 0)) + 1
		id_counts[base] = count
		var sid := base if count == 1 else "%s_%d" % [base, count]
		for t in times:
			used[int(t)] = true
		out += _shape_block(sid, shape_name, times, shape)
	var solo := 0
	var solo_beats: Array = []
	for b in beats:
		var bi := int(b)
		if not used.has(bi):
			solo_beats.append(bi)
	solo_beats.sort()
	for bi in solo_beats:
		solo += 1
		out += "[[solo_%d]]\n@ %d 0.5 0.5\n\n" % [solo, bi]
	if out.is_empty():
		out = "\n"
	return out


## One shape block: closed [(id)] for Square/Custom-closed, open [[id]] otherwise.
## First N outline points become @ lines (time + x y), the trailing
## geometry-only point becomes a ! line — matching chart.enso's spec.
## Points are 0..1 normalized (same as mapping.gd:719-735). Custom shapes
## carry their own points in shape dict; presets fall back to lookup.
func _shape_block(sid: String, shape_name: String, times: Array, shape_dict: Dictionary = {}) -> String:
	var pts: PackedVector2Array
	if shape_dict.has("points") and shape_dict["points"] is PackedVector2Array and (shape_dict["points"] as PackedVector2Array).size() > 0:
		pts = shape_dict["points"] as PackedVector2Array
	else:
		pts = _export_shape_points(shape_name)
	if pts.is_empty():
		return ""
	var closed: bool = bool(shape_dict.get("closed", shape_name == "Square"))
	# Also treat duplicate-closed geometry as closed (last == first)
	if not closed and pts.size() >= 3 and pts[0].is_equal_approx(pts[pts.size() - 1]):
		closed = true
	var header := "[[%s]]\n" % sid
	if closed:
		header = "[(%s)]\n" % sid
	var block := header
	if closed:
		# Closed: one @ per beat, parser auto-closes the loop. Clamp 0..1.
		for i in range(times.size()):
			var p := pts[i] if i < pts.size() else Vector2(0.5, 0.5)
			p = Vector2(clampf(p.x, 0.0, 1.0), clampf(p.y, 0.0, 1.0))
			block += "@ %d %s %s\n" % [int(times[i]), _fmt_coord(p.x), _fmt_coord(p.y)]
	else:
		for i in range(times.size()):
			var p := pts[i] if i < pts.size() else Vector2(0.5, 0.5)
			p = Vector2(clampf(p.x, 0.0, 1.0), clampf(p.y, 0.0, 1.0))
			block += "@ %d %s %s\n" % [int(times[i]), _fmt_coord(p.x), _fmt_coord(p.y)]
		if pts.size() > times.size():
			var tail: Vector2 = pts[times.size()]
			tail = Vector2(clampf(tail.x, 0.0, 1.0), clampf(tail.y, 0.0, 1.0))
			block += "! %s %s\n" % [_fmt_coord(tail.x), _fmt_coord(tail.y)]
	block += "\n"
	return block


func _fmt_coord(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return ("%.3f" % v).rstrip("0").rstrip(".")


## Must stay in sync with mapping.gd's _shape_points().
func _export_shape_points(shape_name: String) -> PackedVector2Array:
	match shape_name:
		"L":
			return PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)])
		"L90":
			return PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
		"L180":
			return PackedVector2Array([Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		"L270":
			return PackedVector2Array([Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)])
		"LFlip":
			return PackedVector2Array([Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)])
		"U":
			return PackedVector2Array(
				[Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
			)
		"UInv":
			return PackedVector2Array([Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
		"Square":
			return PackedVector2Array(
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]
			)
		"Triangle":
			return PackedVector2Array([Vector2(0.5, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0.5, 0)])
		"HLine":
			return PackedVector2Array([Vector2(0, 0.5), Vector2(1, 0.5)])
		"VLine":
			return PackedVector2Array([Vector2(0.5, 0), Vector2(0.5, 1)])
		"Diag":
			return PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
		"DiagInv":
			return PackedVector2Array([Vector2(1, 0), Vector2(0, 1)])
		"ZigZag":
			return PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	return PackedVector2Array(
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]
	)



func _on_draw_guessed_shape(shape: String) -> void:
	if shape == "circle":
		get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")


func _on_draw_area_mouse_entered() -> void:
	_draw.start()
	pass # Replace with function body.


func _on_draw_area_mouse_exited() -> void:
	_draw.stop()
	pass # Replace with function body.


func _on_scroll_container_mouse_entered() -> void:
	VolumePopup.can_popup = false
	pass # Replace with function body.


func _on_scroll_container_mouse_exited() -> void:
	VolumePopup.can_popup = true
	pass # Replace with function body.


func _on_mapping_mouse_entered() -> void:
	VolumePopup.can_popup = false
	pass # Replace with function body.


func _on_mapping_mouse_exited() -> void:
	VolumePopup.can_popup = true
	pass # Replace with function body.


func _on_song_name_edit_text_submitted(new_text: String) -> void:
	DiscordRPC.set_activity("Drawing a map", new_text + " - " + _source_edit.text)
	pass # Replace with function body.


func _on_song_author_edit_text_submitted(new_text: String) -> void:
	DiscordRPC.set_activity("Drawing a map", _name_edit.text + " - " + new_text)
	pass # Replace with function body.
