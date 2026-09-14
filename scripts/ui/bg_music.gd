extends AudioStreamPlayer

const FADE_DURATION := 0.3
const SILENT_DB := -60.0
const FULL_DB := 0.0


func change_song(p_stream: AudioStream = null, p_seek: float = 0.0) -> void:
	var tween := create_tween()
	tween.tween_property(self, "volume_db", SILENT_DB, FADE_DURATION)
	tween.tween_callback(
		func() -> void:
			if p_stream != null:
				stream = p_stream
				play(p_seek)
			else:
				stop()
	)
	tween.tween_property(self, "volume_db", FULL_DB, FADE_DURATION)
