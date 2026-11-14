extends AudioStreamPlayer

signal playback_source_changed(source_id: StringName)

const SILENT_DB := -60.0
const FULL_DB := 0.0

@export var FADE_DURATION := 0.3

var loop: bool = true

var current_stream: AudioStream = null
var current_preview_start: float = 0.0
var current_source_id: StringName = &""

var _fade_tween: Tween = null


func start() -> void:
	play()


func _disable_loop() -> void:
	loop = false


func enable_loop() -> void:
	loop = true


func load_song(p_stream: AudioStream = null) -> void:
	_cancel_fade()
	volume_db = FULL_DB
	stop()
	stream = p_stream

	current_stream = p_stream
	current_preview_start = 0.0
	_set_source_id(&"")


func play_from_source(
	source_id: StringName,
	p_stream: AudioStream = null,
	p_seek: float = 0.0,
) -> void:
	if p_stream != null:
		stream = p_stream

	if stream == null:
		return

	current_stream = stream
	current_preview_start = p_seek

	_set_source_id(source_id)

	_cancel_fade()
	volume_db = FULL_DB
	play(p_seek)


func stop_from_source(source_id: StringName) -> void:
	# Only the current owner can stop its own playback.
	if current_source_id != source_id:
		return

	_cancel_fade()
	stop()
	_set_source_id(&"")


func change_song(
	p_stream: AudioStream = null,
	p_seek: float = 0.0,
	p_source_id: StringName = &"",
) -> void:
	_cancel_fade()

	current_stream = p_stream
	current_preview_start = p_seek

	_set_source_id(p_source_id)

	var tween := create_tween()
	_fade_tween = tween

	tween.tween_property(self, "volume_db", SILENT_DB, FADE_DURATION)

	tween.tween_callback(
		func() -> void:
			if p_stream != null:
				stream = p_stream
				play(p_seek)
			else:
				stop(),
	)

	tween.tween_property(self, "volume_db", FULL_DB, FADE_DURATION)


func stop_all() -> void:
	_cancel_fade()
	stop()
	_set_source_id(&"")


func _set_source_id(new_value: StringName) -> void:
	if current_source_id == new_value:
		return

	current_source_id = new_value
	playback_source_changed.emit(current_source_id)


func _cancel_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = null


func _on_finished() -> void:
	if not loop or current_stream == null:
		_set_source_id(&"")
		return

	change_song(current_stream, current_preview_start, current_source_id)
