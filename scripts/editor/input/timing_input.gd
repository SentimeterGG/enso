extends EditorInput

const NUDGE_MS := 10
const AUDITION_SEC := 0.05


func _format_ms(ms: int) -> String:
	var total_s := floori(ms / 1000.0)
	var m := floori(total_s / 60.0)
	var s := total_s % 60
	var left := ms % 1000
	return "%d:%02d.%03d" % [m, s, left]


func _on_slider_value_changed(value: float) -> void:
	%output.text = _format_ms(int(value))
	if BgMusic.stream != null and BgMusic.playing and not BgMusic.stream_paused:
		BgMusic.play(float(value) / 1000.0)


func _sync_range(duration_ms: int):
	if duration_ms > 0:
		%slider.max_value = duration_ms
	%slider.set_value_no_signal(clampi(int(%slider.value), 0, duration_ms))


func _on_start_pressed() -> void:
	_do_nudge(-1.0)
	pass


func _on_play_pressed() -> void:
	if BgMusic.stream == null:
		return
	if BgMusic.playing:
		BgMusic.stop()
	else:
		BgMusic.play(_slider_seconds())


func _on_end_pressed() -> void:
	_do_nudge(1.0)
	pass


func _slider_seconds() -> float:
	var start_ms := int(
		clampi(floor(%slider.value), floor(%slider.min_value), floor(%slider.max_value))
	)
	return float(start_ms) / 1000.0


func _do_nudge(dir: float) -> void:
	var marker_ms := _nudged_marker_ms(dir)
	%slider.set_value_no_signal(marker_ms)
	%output.text = _format_ms(marker_ms)
	if BgMusic.stream == null:
		return
	var window := _audition_window(marker_ms, dir)
	await _play_audition(window["from_ms"], window["duration_sec"])


func _play_audition(from_ms: int, duration_sec: float) -> void:
	BgMusic.play(float(from_ms) / 1000.0)
	await get_tree().create_timer(maxf(duration_sec, 0.01)).timeout
	if BgMusic.playing:
		BgMusic.stop()


func _audition_window(marker_ms: int, dir: float) -> Dictionary:
	var from_ms := marker_ms
	var duration_sec := AUDITION_SEC
	if dir < 0.0:
		from_ms = maxi(int(%slider.min_value), marker_ms - int(AUDITION_SEC * 1000.0))
		duration_sec = (marker_ms - from_ms) / 1000.0
	return { "from_ms": from_ms, "duration_sec": duration_sec }


func _nudged_marker_ms(dir: float) -> int:
	return clampi(
		int(%slider.value) + int(NUDGE_MS * dir),
		int(%slider.min_value),
		int(%slider.max_value),
	)


func _put_data(input: Variant) -> void:
	var duration_ms: int = input.to_int()
	%slider.set_value_no_signal(clampi(duration_ms, 0, int(%slider.max_value)))
	%output.text = _format_ms(int(%slider.value))


func _take_data() -> Variant:
	return int(%slider.value)
