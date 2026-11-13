# Handle FileDialogPublic Behavior, BgMusic Behavior, prepare all of the fields into dictionary, setting up value for import
extends Control

var android_picker: Object
var _awaiting_field = ""
var fields: Array


func _ready() -> void:
	fields = get_editor_input_children()
	FileDialogGlobal.file_selected.connect(_on_file_dialog_file_selected)
	if Engine.has_singleton("GodotFilePicker"):
		android_picker = Engine.get_singleton("GodotFilePicker")


# Handle FileDialogPublic properties for video bg
func _show_video_bg_file_dialog():
	_awaiting_field = "video_bg"
	FileDialogGlobal.filters = ["*.ogv"]
	FileDialogGlobal.title = "Choose a Video Background"
	FileDialogGlobal.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	FileDialogGlobal.access = FileDialog.ACCESS_FILESYSTEM
	if android_picker:
		android_picker.openFilePicker("video/*")
	else:
		FileDialogGlobal.popup_centered()


# Handle FileDialogPublic properties for song
func _show_song_file_dialog():
	_awaiting_field = "song"
	FileDialogGlobal.filters = ["*.mp3", "*.ogg", "*.wav"]
	FileDialogGlobal.title = "Choose a Song"
	FileDialogGlobal.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	FileDialogGlobal.access = FileDialog.ACCESS_FILESYSTEM
	if android_picker:
		android_picker.openFilePicker("audio/*")
	else:
		FileDialogGlobal.popup_centered()


# Handle FileDialogPublic properties for bg
func _show_bg_file_dialog():
	_awaiting_field = "bg"
	FileDialogGlobal.filters = ["*.png", "*.jpg", "*.jpeg", "*.webp"]
	FileDialogGlobal.title = "Choose a Background Image"
	FileDialogGlobal.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	FileDialogGlobal.access = FileDialog.ACCESS_FILESYSTEM
	if android_picker:
		android_picker.openFilePicker("image/*")
	else:
		FileDialogGlobal.popup_centered()


func _on_level_creator_chart_imported(chart: ChartData) -> void:
	var metadata = chart.metadata
	var base_dir := chart.chart_path.get_base_dir()
	_setup_fields(metadata, base_dir)


func _setup_fields(metadata: Dictionary, base_dir: String = ""):
	for field in fields:
		var key = field.name.to_lower()
		if metadata.has(key):
			if field.has_method("_put_data"):
				var value: String = metadata[key]
				if base_dir != "" and (key == "song" or key == "bg" or key == "video_bg"):
					value = _resolve_asset_path(base_dir, value)
				if key == "song":
					_load_song(value)
				if key == "bg":
					GlobalBackground.change(value)
				field._put_data(value)


func _resolve_asset_path(base_dir: String, path: String) -> String:
	if path.is_empty():
		return path
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	return base_dir.path_join(path).simplify_path()


func get_editor_input_children() -> Array[Node]:
	var result = find_children("*", "EditorInput", true, false)
	return result


func _allowed_extensions(field_name: String) -> PackedStringArray:
	match field_name:
		"video_bg":
			return ["ogv"]
		"song":
			return ["mp3", "ogg", "wav"]
		"bg":
			return ["png", "jpg", "jpeg", "webp"]
		_:
			return []


func _on_file_dialog_file_selected(path: String) -> void:
	if _awaiting_field == "":
		return
	var allowed := _allowed_extensions(_awaiting_field)
	var ext := path.get_extension().to_lower()
	if allowed.size() > 0 and not allowed.has(ext):
		Notification.show_toast(
			"Invalid File",
			'Expected "%s" but got "%s".' % [", ".join(allowed), ext],
			NotificationToast.Kind.WARN,
			2.6,
		)
		_awaiting_field = ""
		return
	for field in fields:
		if field.name == _awaiting_field:
			if field.has_method("_put_data"):
				field._put_data(path)
			if field.name == "song":
				_load_song(path)
			if field.name == "bg":
				GlobalBackground.change(path)
			break
	_awaiting_field = ""


func _load_song(path: String) -> void:
	var p := path.strip_edges()
	if p.is_empty():
		return
	var stream_call := Global.load_safely_async(path)
	var stream: AudioStream = await stream_call.completed
	if stream == null:
		push_error("Could not load audio: " + p)
		return
	BgMusic.stream = stream
	var duration_ms := int(stream.get_length() * 1000.0)
	for field in fields:
		if field.has_method("_sync_range"):
			field._sync_range(duration_ms)


func _find_field(p_name: String) -> Object:
	for field in fields:
		if field.name == p_name:
			return field
	return null


func is_export_ready() -> bool:
	var song_field := _find_field("song")
	var name_field := _find_field("name")
	if song_field == null or name_field == null:
		return false
	var song := str(song_field._take_data()).strip_edges()
	var name_value := str(name_field._take_data()).strip_edges()
	return not song.is_empty() and not name_value.is_empty()


func when_export() -> Dictionary:
	var data: Dictionary = { }
	for field in fields:
		var key: String = field.name
		var value: Variant
		if field.has_method("_take_data"):
			value = field._take_data()
		else:
			value = ""
		data[key] = value
	return data
