extends AudioStreamPlayer

const SILENT_DB := -60.0
const FULL_DB := 0.0

var FADE_DURATION := 0.3
var loop: bool = true
var current_stream: AudioStream
var current_preview_start: float
var _fade_tween: Tween = null


func start():
	play()


func _disable_loop():
	loop = false


func enable_loop():
	loop = true


func load_song(p_stream: AudioStream = null) -> void:
	volume_db = FULL_DB
	stream = p_stream


func change_song(p_stream: AudioStream = null, p_seek: float = 0.0) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	current_stream = p_stream
	current_preview_start = p_seek
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


func _on_finished() -> void:
	if loop == true:
		change_song(current_stream, current_preview_start)
	else:
		change_song(null)
		return
