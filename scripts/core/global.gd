extends Node

const DECODED_AUDIO_CACHE_LIMIT := 1
const AUDIO_DECODE_CHUNK_FRAMES := 4096

var current_chart: ChartData = null

var first_time_playing: bool = true

var save_file_path = "user://ENSO_FILES/"

var settingsData = SettingsData.new()

signal toggle_window


class SafeResource:
	signal completed(resource: Resource)
	var result: Resource = null


var resource_load_task_ids: Array[int] = []

var _decoded_audio_cache: Dictionary = { }
var _decoded_audio_cache_order: Array[String] = []
var _decoded_audio_pending: Dictionary = { }


func _ready():
	get_window().min_size = Vector2i(640, 360)
	DirAccess.make_dir_recursive_absolute(save_file_path)
	load_all_data()
	DisplayServer.window_set_mode(
		(
			DisplayServer.WINDOW_MODE_FULLSCREEN
			if settingsData.fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)


func _process(_delta: float) -> void:
	for i in range(resource_load_task_ids.size() - 1, -1, -1):
		var id := resource_load_task_ids[i]
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)

			resource_load_task_ids.remove_at(i)


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
		var focused_control = get_viewport().gui_get_focus_owner()

		if focused_control is LineEdit:
			get_viewport().gui_release_focus()


func save(resource, save_filename):
	ResourceSaver.save(resource, save_file_path + save_filename)


func load_all_data():
	settingsData = load_data(SettingsData)


func call_if_exists(node: Object, method: String, args: Array = []) -> void:
	if node != null and node.has_method(method):
		node.callv(method, args)


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

	return temp


func choose_random_chart() -> ChartData:
	var by_folder: Dictionary = { }
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
	var chart := ChartData.new()
	chart.chart_path = picked
	chart.metadata = ChartParser.parse_metadata(picked)
	if chart == null or chart.is_empty():
		push_warning("global: failed to load random chart: " + picked)
		return null
	current_chart = chart
	return chart


func load_safely(path: String) -> Resource:
	return _load_resource(path)


func _load_resource(path: String) -> Resource:
	if path.is_empty():
		push_warning("load_safely: missing resource: " + path)
		return null

	if path.begins_with("res://"):
		# Use the ResourceLoader for res:// paths so imported assets (e.g. .png -> .ctex)
		# resolve correctly in exported builds such as Android.
		if ResourceLoader.exists(path):
			return ResourceLoader.load(path)

		push_warning("load_safely: missing resource: " + path)
		return null

	if not FileAccess.file_exists(path):
		push_warning("load_safely: file not found: " + path)
		return null

	return _load_external_resource(path)


func _load_external_resource(path: String) -> Resource:
	match path.get_extension().to_lower():
		# Images
		"png", "jpg", "jpeg", "webp":
			var img := Image.load_from_file(path)
			if img == null or img.is_empty():
				push_warning("load_safely: couldn't decode image: " + path)
				return null
			return ImageTexture.create_from_image(img)

		# Videos
		"ogv":
			var video_resource := VideoStreamTheora.new()
			video_resource.file = path
			return video_resource

		# Audio
		"opus":
			return AudioStreamOpus.load_from_file(path)

		"mp3":
			return AudioStreamMP3.load_from_file(path)

		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)

		"wav":
			return AudioStreamWAV.load_from_file(path)

	push_error("load_safely: unsupported file type: " + path)
	return null


func load_safely_async(path: String) -> SafeResource:
	var safe_resource = SafeResource.new()
	resource_load_task_ids.append(
		WorkerThreadPool.add_task(_create_resource.bind(path, safe_resource))
	)
	return safe_resource


func load_audio_wav_async(path: String) -> SafeResource:
	var p := path.strip_edges()
	var safe_resource := SafeResource.new()
	if p.is_empty():
		safe_resource.completed.emit.call_deferred(null)
		return safe_resource
	var cache_key := _audio_wav_cache_key(p)
	if _decoded_audio_cache.has(cache_key):
		safe_resource.result = _decoded_audio_cache[cache_key]
		safe_resource.completed.emit.call_deferred(safe_resource.result)
		return safe_resource
	if _decoded_audio_pending.has(cache_key):
		return _decoded_audio_pending[cache_key] as SafeResource

	var job := SafeResource.new()
	_decoded_audio_pending[cache_key] = job
	var mix_rate := AudioServer.get_mix_rate()
	resource_load_task_ids.append(
		WorkerThreadPool.add_task(_create_decoded_audio.bind(p, cache_key, job, mix_rate))
	)
	return job


func _audio_wav_cache_key(path: String) -> String:
	var modified := FileAccess.get_modified_time(path)
	var length := -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		length = file.get_length()
		file.close()
	return "%s|%d|%d" % [path, modified, length]


func _create_decoded_audio(
	path: String,
	cache_key: String,
	job: SafeResource,
	mix_rate: int,
) -> void:
	var wav := _decode_audio_to_wav(path, mix_rate)
	_finish_decoded_audio.call_deferred(cache_key, job, wav)


func _finish_decoded_audio(cache_key: String, job: SafeResource, wav: AudioStreamWAV) -> void:
	_decoded_audio_pending.erase(cache_key)
	if wav != null:
		_cache_decoded_audio(cache_key, wav)
	job.result = wav
	job.completed.emit(wav)


func _cache_decoded_audio(cache_key: String, wav: AudioStreamWAV) -> void:
	if not _decoded_audio_cache.has(cache_key):
		_decoded_audio_cache_order.append(cache_key)
	_decoded_audio_cache[cache_key] = wav
	while _decoded_audio_cache_order.size() > DECODED_AUDIO_CACHE_LIMIT:
		var old_key: String = _decoded_audio_cache_order.pop_front()
		_decoded_audio_cache.erase(old_key)


func _decode_audio_to_wav(path: String, mix_rate: int) -> AudioStreamWAV:
	var stream := _load_resource(path) as AudioStream
	if stream == null:
		push_warning("decode_audio: could not load: " + path)
		return null
	if stream is AudioStreamWAV:
		return stream as AudioStreamWAV

	var playback := stream.instantiate_playback()
	if playback == null:
		push_warning("decode_audio: could not create playback: " + path)
		return null
	if mix_rate <= 0:
		mix_rate = 44100

	var total_frames := int(ceil(stream.get_length() * float(mix_rate)))
	if total_frames <= 0:
		push_warning("decode_audio: empty stream: " + path)
		return null

	playback.start(0.0)
	var pcm := PackedByteArray()
	var remaining := total_frames
	while remaining > 0:
		var frames := playback.mix_audio(1.0, mini(remaining, AUDIO_DECODE_CHUNK_FRAMES))
		if frames.is_empty():
			break
		var base := pcm.size()
		pcm.resize(base + frames.size() * 4)
		for i in range(frames.size()):
			var frame := frames[i]
			pcm.encode_s16(base + i * 4, int(clampf(frame.x, -1.0, 1.0) * 32767.0))
			pcm.encode_s16(base + i * 4 + 2, int(clampf(frame.y, -1.0, 1.0) * 32767.0))
		remaining -= frames.size()
	playback.stop()

	if pcm.is_empty():
		push_warning("decode_audio: no PCM data: " + path)
		return null

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = mix_rate
	wav.data = pcm
	return wav


func _create_resource(path: String, safe_resource: SafeResource) -> void:
	var loaded_resource := _load_resource(path)
	if loaded_resource == null:
		push_warning("load_safely: failed to load resource: " + path)
	safe_resource.result = loaded_resource
	# Always complete so callers awaiting this resource are never left hanging.
	safe_resource.completed.emit.call_deferred(loaded_resource)


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
