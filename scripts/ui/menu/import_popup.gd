extends Control

signal levels_imported(count: int)

const LEVEL_ITEM_SCENE: PackedScene = preload("res://scenes/menus/level_item.tscn")
const PREVIEW_ROOT := "user://import_preview"
const CACHE_ROOT := "user://import_cache"
const DOWNLOAD_PATH := CACHE_ROOT + "/download.ensz"
const ARCHIVE_FILTER := "*.ensz ; ENSO Level Archive"
const PREVIEW_ROW_SIZE := Vector2(744, 120)
const PREVIEW_VARIANT_SIZE := Vector2(700, 96)
const LEVEL_LIST_PATH := "Main Content/HBoxContainer/RSide/MaxLevelWidth/Level List"
const IMPORT_BUTTON_PATH := "Main Content/HBoxContainer/RSide/MaxLevelWidth/SearchSection/ImportButton"

var android_picker: Object
var _archive := EnszArchive.new()
var _source_path := ""
var _preview_levels: Array[String] = []
var _busy := false

@onready var _preview_list: VBoxContainer = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/Preview/ScrollContainer/VBoxContainer
@onready var _preview_label: Label = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/Preview/PreviewLab
@onready var _scroll: ScrollContainer = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/Preview/ScrollContainer
@onready var _file_line: LineEdit = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/ImportInput/ImportFileContainer/ImportFileLine
@onready var _browse_button: Button = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/ImportInput/ImportFileContainer/Button
@onready var _import_file_button: Button = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/ImportInput/ImportFile
@onready var _link_line: LineEdit = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/ImportInput/ImportLinkLine
@onready var _import_link_button: Button = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/ImportInput/ImportLink
@onready var _import_levels_button: Button = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/ImportInput/ImportLevels
@onready var _go_back_button: Button = $AspectRatioContainer/MarginContainer/Panel/MarginContainer/HBoxContainer/ImportInput/GoBack
@onready var _file_dialog: FileDialog = $FileDialog
@onready var _http: HTTPRequest = $HTTPRequest
@onready var _level_list: Control = get_parent().get_node_or_null(LEVEL_LIST_PATH) as Control


func _ready() -> void:
	visible = false
	_clear_preview_list()
	_preview_label.visible = true
	_clear_dir(PREVIEW_ROOT)
	_clear_dir(CACHE_ROOT)
	_set_busy(false)
	if Engine.has_singleton("GodotFilePicker"):
		android_picker = Engine.get_singleton("GodotFilePicker")
		android_picker.file_picked.connect(_on_file_android_picked)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_popup()


func open_popup() -> void:
	if _busy:
		return
	visible = true
	move_to_front()
	_set_level_list_enabled(false)
	_preview_label.visible = _preview_list.get_child_count() == 0
	_file_line.grab_focus()


func close_popup() -> void:
	if _busy:
		return
	_reset_state()
	visible = false
	_set_level_list_enabled(true)


func _open_file_dialog() -> void:
	if _busy:
		return

	var current := _file_line.text.strip_edges()
	if not current.is_empty():
		_file_dialog.current_dir = current.get_base_dir()
		_file_dialog.current_file = current.get_file()

	if android_picker:
		android_picker.openFilePicker("*/*")
	else:
		_file_dialog.popup_centered_ratio(0.8)


func _on_file_android_picked(temp_path: String, _mime_type: String) -> void:
	if not temp_path.get_file().to_lower().ends_with(".ensz"):
		push_error("Invalid file. Expected .ensz")
		DirAccess.remove_absolute(temp_path)
		return

	_file_line.text = temp_path
	_preview_archive(temp_path)


func _on_file_selected(path: String) -> void:
	_file_line.text = path
	_preview_archive(path)


func _on_file_line_submitted(_text: String) -> void:
	_on_import_file_pressed()


func _on_import_file_pressed() -> void:
	if _busy:
		return
	var path := _file_line.text.strip_edges()
	if path.is_empty():
		_open_file_dialog()
		return
	_preview_archive(path)


func _on_link_line_submitted(_text: String) -> void:
	_on_import_link_pressed()


func _on_import_link_pressed() -> void:
	if _busy:
		return
	var url := _link_line.text.strip_edges()
	if url.is_empty():
		_warn("No Link", "Paste a link to a .ensz archive first.")
		return
	if not (url.begins_with("http://") or url.begins_with("https://")):
		_warn("Invalid Link", "The link must start with http:// or https://.")
		return
	_download_and_preview(url)


func _download_and_preview(url: String) -> void:
	_set_busy(true, "link")
	var request_error := _http.request(url)
	if request_error != OK:
		_set_busy(false)
		_warn("Download Failed", "Could not start the download.")
		return

	var response: Array = await _http.request_completed
	if not is_inside_tree():
		return
	_set_busy(false)

	var result := int(response[0])
	var response_code := int(response[1])
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		_warn("Download Failed", "The link could not be reached.")
		return
	if response_code < 200 or response_code >= 300:
		_warn("Download Failed", "The server returned HTTP %d." % response_code)
		return
	if body.is_empty():
		_warn("Download Failed", "The downloaded archive is empty.")
		return

	var saved_path := _save_download(body)
	if saved_path.is_empty():
		_warn("Download Failed", "Could not save the downloaded archive.")
		return
	_preview_archive(saved_path)


func _save_download(body: PackedByteArray) -> String:
	_clear_dir(CACHE_ROOT)
	if DirAccess.make_dir_recursive_absolute(CACHE_ROOT) != OK:
		return ""
	var file := FileAccess.open(DOWNLOAD_PATH, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(body)
	file.close()
	return DOWNLOAD_PATH


func _preview_archive(path: String) -> void:
	_reset_preview()
	_clear_dir(PREVIEW_ROOT)

	var result := _archive.load(path, PREVIEW_ROOT)
	if bool(result.get("error", true)):
		_clear_dir(PREVIEW_ROOT)
		_warn("Import Failed", str(result.get("reason", "Could not read the archive.")))
		return

	for level_path in result.get("levels", []):
		_preview_levels.append(str(level_path))
	if _preview_levels.is_empty():
		_clear_dir(PREVIEW_ROOT)
		_warn("Import Failed", "The archive does not contain any level folders.")
		return

	_source_path = path
	_populate_preview()
	_warn_if_overwriting(path)


func _warn_if_overwriting(path: String) -> void:
	var existing := _archive.find_existing_levels(path)
	if existing.is_empty():
		return
	var suffix := "" if existing.size() == 1 else "s"
	_warn(
		"Overwrite Warning",
		"Importing will overwrite the existing level folder%s: %s." % [suffix, ", ".join(existing)],
	)


func _populate_preview() -> void:
	_clear_preview_list()
	var row_id := 0
	for level_dir in _preview_levels:
		var charts := _find_charts_in(level_dir)
		if charts.is_empty():
			continue

		var metadata := ChartParser.parse_metadata(charts[0])
		var title := _title_from_metadata(metadata, level_dir)
		var subtitle := _subtitle_from_metadata(metadata)
		var background := _resolve_background(metadata, charts[0])
		_add_preview_item(row_id, title, subtitle, charts[0], background, false)

		if charts.size() > 0:
			for chart_path in charts:
				var difficulty := chart_path.get_file().get_basename().capitalize()
				_add_preview_item(row_id, difficulty, subtitle, chart_path, "", true)

		row_id += 1

	_preview_label.text = "Preview Of Imported Files"
	_preview_label.visible = _preview_list.get_child_count() == 0
	_scroll.scroll_vertical = 0


func _add_preview_item(
	row_id: int,
	title: String,
	subtitle: String,
	chart_path: String,
	background: String,
	variant: bool,
) -> void:
	var item := LEVEL_ITEM_SCENE.instantiate() as Panel
	_preview_list.add_child(item)
	item.custom_minimum_size = PREVIEW_VARIANT_SIZE if variant else PREVIEW_ROW_SIZE
	item.custom_maximum_size = item.custom_minimum_size
	item.size_flags_horizontal = Control.SIZE_SHRINK_END
	item.size_flags_vertical = Control.SIZE_FILL
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item.has_method("setup"):
		item.call("setup", row_id, title, subtitle, chart_path, background, variant)


func _title_from_metadata(metadata: Dictionary, fallback: String) -> String:
	var display_name := str(metadata.get("name", "")).strip_edges()
	var source := str(metadata.get("source", "")).strip_edges()
	if not source.is_empty():
		display_name = "%s by %s" % [display_name, source] if not display_name.is_empty() else source
	if display_name.is_empty():
		display_name = fallback.get_file()
	return display_name


func _subtitle_from_metadata(metadata: Dictionary) -> String:
	var mapper := str(metadata.get("mapper", "")).strip_edges()
	return "MAPPED BY " + mapper if not mapper.is_empty() else ""


func _resolve_background(metadata: Dictionary, chart_path: String) -> String:
	var background := str(metadata.get("bg", "")).strip_edges()
	if (
		not background.is_empty() and not background.begins_with("res://")
		and not background.begins_with("user://")
	):
		background = chart_path.get_base_dir().path_join(background).simplify_path()
	return background


func _find_charts_in(level_dir: String) -> Array[String]:
	var out: Array[String] = []
	for file_name in DirAccess.get_files_at(level_dir):
		if file_name.get_extension().to_lower() == "enso":
			out.append(level_dir.path_join(file_name))
	out.sort()
	return out


func _on_import_levels_pressed() -> void:
	if _busy:
		return
	if _source_path.is_empty() or _preview_levels.is_empty():
		_warn("Nothing To Import", "Choose a file or link and refresh the preview first.")
		return
	if not FileAccess.file_exists(_source_path):
		_warn("Import Failed", "The selected archive is no longer available.")
		return

	_set_busy(true, "import")
	await get_tree().process_frame

	var result := _archive.load(_source_path)
	_set_busy(false)
	if bool(result.get("error", true)):
		_warn("Import Failed", str(result.get("reason", "Could not import the archive.")))
		return

	var imported: Array = result.get("levels", [])
	if imported.is_empty():
		_warn("Import Failed", "No level folders were imported.")
		return

	var count := imported.size()
	var suffix := "" if count == 1 else "s"
	_notify(
		"Import Complete",
		"Imported %d level%s into your level list." % [count, suffix],
		NotificationToast.Kind.SUCCESS,
	)
	_reload_level_list()
	levels_imported.emit(count)
	close_popup()


func _reset_state() -> void:
	_reset_preview()
	_file_line.text = ""
	_link_line.text = ""
	_clear_dir(PREVIEW_ROOT)
	_clear_dir(CACHE_ROOT)


func _reset_preview() -> void:
	_source_path = ""
	_preview_levels.clear()
	_clear_preview_list()
	_preview_label.text = "Preview Of Imported Files"
	_preview_label.visible = true
	_scroll.scroll_vertical = 0


func _clear_preview_list() -> void:
	for child in _preview_list.get_children():
		_preview_list.remove_child(child)
		child.queue_free()


func _set_level_list_enabled(enabled: bool) -> void:
	if _level_list == null:
		return
	_level_list.set_process_input(enabled)
	_level_list.set_process_unhandled_key_input(enabled)


func _reload_level_list() -> void:
	if _level_list != null and _level_list.has_method("reload_levels"):
		_level_list.call_deferred("reload_levels")


func _set_busy(busy: bool, action: String = "") -> void:
	_busy = busy
	_browse_button.disabled = busy
	_import_file_button.disabled = busy
	_import_link_button.disabled = busy
	_import_levels_button.disabled = busy
	_go_back_button.disabled = busy
	_file_line.editable = not busy
	_link_line.editable = not busy
	if not busy:
		_import_link_button.text = "IMPORT FROM A LINK"
		_import_levels_button.text = "IMPORT LEVELS"
	elif action == "link":
		_import_link_button.text = "DOWNLOADING..."
	elif action == "import":
		_import_levels_button.text = "IMPORTING..."


func _clear_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	_remove_dir_contents(path)
	DirAccess.remove_absolute(path)


func _remove_dir_contents(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			_remove_dir_contents(path.path_join(entry))
		dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()


func _notify(
	title: String,
	body: String,
	kind: NotificationToast.Kind,
	duration: float = 4.0,
) -> void:
	Notification.show_toast(title, body, kind, duration)


func _warn(title: String, body: String) -> void:
	_notify(title, body, NotificationToast.Kind.WARN, 7.0)
