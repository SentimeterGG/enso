extends Node
var current_chart: ChartData = null

var first_time_playing: bool = true

var save_file_path = "user://ENSO_FILES/"

# Settings and Main Menu variables.
var settingsData = SettingsData.new()

# for getting a list of extension
var image_exts: Array = ResourceLoader.get_recognized_extensions_for_type("Texture2D")
var video_exts: Array = ResourceLoader.get_recognized_extensions_for_type("VideoStream")
var audio_exts: Array = ResourceLoader.get_recognized_extensions_for_type("AudioStream")

signal toggle_window


func _ready():
	DirAccess.make_dir_recursive_absolute(save_file_path)
	load_all_data()
	DisplayServer.window_set_mode(
		(
			DisplayServer.WINDOW_MODE_FULLSCREEN
			if settingsData.fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)


func save(resource, save_filename):
	ResourceSaver.save(resource, save_file_path + save_filename)


func load_all_data():
	settingsData = load_data(SettingsData)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_window"):
		toggle_window.emit()
		if Global.settingsData.fullscreen == true:
			Global.settingsData.fullscreen = false
		else:
			Global.settingsData.fullscreen = true
		save(settingsData, settingsData.save_file_name)
		DisplayServer.window_set_mode(
			(
				DisplayServer.WINDOW_MODE_FULLSCREEN
				if settingsData.fullscreen
				else DisplayServer.WINDOW_MODE_WINDOWED
			)
		)

	if event.is_action_pressed("ui_cancel"):
		# Check if a LineEdit (or any Control node) currently has focus
		var focused_control = get_viewport().gui_get_focus_owner()

		if focused_control is LineEdit:
			# Release focus globally across the UI
			get_viewport().gui_release_focus()


func load_data(res_class: Resource):
	var temp = res_class.new()
	var path = save_file_path + temp.save_file_name

	if FileAccess.file_exists(path):
		var loaded = ResourceLoader.load(path)
		if loaded:
			return loaded.duplicate(true)
		else:
			push_warning("Failed to load, creating new: " + path)
	else:
		save(temp, temp.save_file_name)

	# ALWAYS return something
	return temp


func choose_random_chart() -> ChartData:
	var by_folder: Dictionary = {}
	for base_dir in ["res://levels", "user://levels"]:
		for chart_path in _find_charts_in(base_dir):
			var key := chart_path.get_file()
			if chart_path.get_base_dir() != base_dir:
				key = chart_path.get_base_dir().get_file()
			else:
				key = "::file::" + key
			by_folder[key] = chart_path
	var paths: Array[String] = []
	for key in by_folder:
		var candidate := String(by_folder[key])
		if not ChartParser.has_unsetup_notes(candidate):
			paths.append(candidate)
	if paths.is_empty():
		push_warning("global: no complete charts available for random pick.")
		return null
	var picked: String = paths[randi() % paths.size()]
	var chart := ChartParser.load(picked)
	if chart == null or chart.is_empty():
		push_warning("global: failed to load random chart: " + picked)
		return null
	current_chart = chart
	return chart


## Same chart scan as level_list._find_charts_in (kept in sync manually).
func _find_charts_in(base_dir: String) -> Array[String]:
	var out: Array[String] = []
	if base_dir == "user://levels" and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	if not DirAccess.dir_exists_absolute(base_dir):
		return out
	for sub in DirAccess.get_directories_at(base_dir):
		var folder := base_dir.path_join(sub)
		var candidates: Array[String] = []
		for f in DirAccess.get_files_at(folder):
			if f.get_extension().to_lower() == "enso":
				candidates.append(f)
		if candidates.is_empty():
			continue
		candidates.sort()
		var picked := "chart.enso"
		if not candidates.has(picked):
			picked = candidates[0]
		out.append(folder.path_join(picked))
	for f in DirAccess.get_files_at(base_dir):
		if f.get_extension().to_lower() == "enso":
			out.append(base_dir.path_join(f))
	out.sort()
	return out


func load_safely(path: String) -> Resource:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			return load(path)
		push_warning("load_safely: missing resource: " + path)
		return null
	if not FileAccess.file_exists(path):
		push_warning("load_safely: file not found: " + path)
		return null
	match path.get_extension().to_lower():
		"png", "jpg", "jpeg", "webp":
			var img := Image.load_from_file(path)
			if img == null or img.is_empty():
				push_warning("load_safely: couldn't decode image: " + path)
				return null
			return ImageTexture.create_from_image(img)
		"ogv":
			var video_resource := VideoStreamTheora.new()
			video_resource.file = path
			return video_resource
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg", "opus":
			return AudioStreamOggVorbis.load_from_file(path)
	push_error("load_safely: unsupported file type: " + path)
	return null
