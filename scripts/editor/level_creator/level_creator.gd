extends Control

signal chart_imported(chart: ChartData)
signal export_requested(dest_dir: String)

enum SCENES {
	METADATA,
	MAPPING,
}

const SLIDE_DURATION := 0.35

var viewport_size: Vector2
var viewport_width: float

var _exporter: ChartExporter
var _importer: ChartImporter

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


func _ready() -> void:
	BgMusic.FADE_DURATION = 1.6
	BgMusic.change_song(null)
	VolumePopup.hide_pop_up()
	viewport_size = get_viewport_rect().size
	viewport_width = viewport_size.x
	_exporter = ChartExporter.new(metadata_group, mapping_group)
	_exporter.export_requested.connect(_forward_export_requested)
	_exporter.toast_requested.connect(_on_toast_requested)
	_importer = ChartImporter.new(mapping_group)
	_importer.chart_imported.connect(_forward_chart_imported)
	_importer.toast_requested.connect(_on_toast_requested)
	_switch_to(SCENES.METADATA)
	_sync_export_button()
	_update_discord_activity()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().gui_release_focus()


func _forward_export_requested(dest_dir: String) -> void:
	export_requested.emit(dest_dir)


func _forward_chart_imported(chart: ChartData) -> void:
	chart_imported.emit(chart)


func _on_toast_requested(
	title: String,
	message: String,
	kind: NotificationToast.Kind,
	duration: float,
) -> void:
	if duration > 0.0:
		Notification.show_toast(title, message, kind, duration)
		return
	Notification.show_toast(title, message, kind)


func _process(_delta: float) -> void:
	_sync_export_button()


func _on_mapping_pressed() -> void:
	VolumePopup.can_popup = false
	mapping_button.disabled = true
	metadata_button.disabled = false
	_switch_to(SCENES.MAPPING)


func _on_metadata_pressed() -> void:
	VolumePopup.can_popup = true
	mapping_button.disabled = false
	metadata_button.disabled = true
	_switch_to(SCENES.METADATA)


func _switch_to(scene: SCENES) -> void:
	get_viewport().gui_release_focus()
	match scene:
		SCENES.METADATA:
			metadata_group.visible = true
			mapping_group.visible = false
			pass
		SCENES.MAPPING:
			mapping_group.visible = true
			metadata_group.visible = false
			pass
		_:
			metadata_group.visible = true
			mapping_group.visible = false
			return


func _sync_export_button() -> void:
	if _export_button == null or metadata_group == null:
		return
	if not metadata_group.has_method("is_export_ready"):
		return
	_export_button.disabled = not metadata_group.is_export_ready()


func _on_import_file_pressed() -> void:
	_import_dialog.popup_centered(Vector2i(600, 400))


func _on_export_button_pressed() -> void:
	_save_dialog.popup_centered(Vector2i(600, 400))


func _on_export_popup_dir_selected(dir: String) -> void:
	_exporter.export_to(dir)


func _on_draw_guessed_shape(shape: String) -> void:
	if shape == "circle":
		get_tree().call_deferred("change_scene_to_file", "res://scenes/menus/main_menu.tscn")


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


func _on_song_name_edit_text_submitted(_new_text: String) -> void:
	_update_discord_activity()


func _on_song_author_edit_text_submitted(_new_text: String) -> void:
	_update_discord_activity()


func _on_song_fields_changed(_new_text: String) -> void:
	_update_discord_activity()


func _update_discord_activity() -> void:
	var song_name := ""
	var source := ""
	if _name_edit != null:
		song_name = _name_edit.text.strip_edges()
	if _source_edit != null:
		source = _source_edit.text.strip_edges()
	var state := ""
	if not song_name.is_empty() and not source.is_empty():
		state = song_name + " - " + source
	elif not song_name.is_empty():
		state = song_name
	elif not source.is_empty():
		state = source
	DiscordRPC.set_activity("Drawing a map", state)


func _exit_tree() -> void:
	BgMusic.FADE_DURATION = 0.3


func _on_import_popup_dir_selected(dir: String) -> void:
	if _importer.import_folder(dir):
		_update_discord_activity()

