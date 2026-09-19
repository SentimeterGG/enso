extends Control

## IO controller for the level creator.
## Owns import/export dialogs + file/folder work and emits results to
## metadata.gd, which owns all UI widgets via when_import()/when_export().
signal chart_imported(chart: ChartData)
signal export_requested(dest_dir: String)

@onready var level_creator_group: Control = %LevelCreator
@onready var mapping_button: Button = %MappingButton
@onready var metadata_button: Button = %MetadataButton
@onready var _save_dialog: FileDialog = %ExportPopup
@onready var _import_dialog: FileDialog = %ImportPopup
@onready var metadata_group: Control = %METADATA

var viewport_size: Vector2
var viewport_width: float

var _slide_tween: Tween
const SLIDE_DURATION := 0.35


func _ready() -> void:
	viewport_size = get_viewport_rect().size
	viewport_width = viewport_size.x


func _on_mapping_pressed() -> void:
	mapping_button.disabled = true
	metadata_button.disabled = false
	_slide_to(-viewport_width)


func _on_metadata_pressed() -> void:
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
	var text := _build_metadata_text(data, "./" + song_file)
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


func _build_metadata_text(data: Dictionary, song_value: String) -> String:
	var colors: Array = data.get("color_scheme", [])
	var colors_str := "[" + ", ".join(colors.map(func(c): return '"' + str(c) + '"')) + "]"
	return (
		"[metadata]\nname = %s\nsource = %s\nmapper = %s\nsong = %s\ncolor_scheme = %s\npreview_start = %d\nbpm = %d\nbeat0 = %d\noverall_difficulty = %d\n\n[notes]\n"
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
