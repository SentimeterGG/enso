extends EditorInput

const NUDGE_MS := 10
const AUDITION_SEC := 0.05

@export var id: StringName

@onready var _start_button: Button = %start
@onready var _play_button: Button = %play
@onready var _end_button: Button = %end

var _play_atlas_unique: AtlasTexture = null
var _has_song := true
var _audition_token := 0


func _ready() -> void:
	BgMusic.playback_source_changed.connect(_on_playback_source_changed)

	_refresh_song_controls()
	_playing(BgMusic.current_source_id == id)


func _exit_tree() -> void:
	if BgMusic.playback_source_changed.is_connected(_on_playback_source_changed):
		BgMusic.playback_source_changed.disconnect(_on_playback_source_changed)


func _process(_delta: float) -> void:
	_refresh_song_controls()


func _on_playback_source_changed(source_id: StringName) -> void:
	_playing(source_id == id)


func _refresh_song_controls() -> void:
	var has_song := BgMusic.stream != null

	if has_song == _has_song:
		return

	_has_song = has_song

	_start_button.disabled = not has_song
	_play_button.disabled = not has_song
	_end_button.disabled = not has_song


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


func _sync_range(duration_ms: int) -> void:
	if duration_ms > 0:
		%slider.max_value = duration_ms

	%slider.set_value_no_signal(clampi(int(%slider.value), 0, duration_ms))


func _on_start_pressed() -> void:
	if BgMusic.stream == null:
		return

	_do_nudge(-1.0)


func _on_play_pressed() -> void:
	if BgMusic.stream == null:
		return

	if BgMusic.current_source_id == id and BgMusic.playing:
		_invalidate_audition()
		BgMusic.stop_from_source(id)
	else:
		_invalidate_audition()
		BgMusic.play_from_source(id, BgMusic.stream, _slider_seconds())


func _playing(play: bool) -> void:
	if _play_atlas_unique == null:
		var icon := _play_button.icon

		if icon is AtlasTexture:
			_play_atlas_unique = icon.duplicate() as AtlasTexture
			_play_button.icon = _play_atlas_unique
		else:
			return

	if play:
		_play_atlas_unique.region = Rect2i(16, 32, 16, 16)
	else:
		_play_atlas_unique.region = Rect2i(16, 16, 16, 16)


func _on_end_pressed() -> void:
	if BgMusic.stream == null:
		return

	_do_nudge(1.0)


func _slider_seconds() -> float:
	var start_ms := int(
		clampi(floori(%slider.value), floori(%slider.min_value), floori(%slider.max_value))
	)

	return float(start_ms) / 1000.0


func _do_nudge(dir: float) -> void:
	var marker_ms := _nudged_marker_ms(dir)

	%slider.set_value_no_signal(marker_ms)
	%output.text = _format_ms(marker_ms)

	if BgMusic.stream == null:
		return

	var window := _audition_window(marker_ms, dir)

	_play_audition(window["from_ms"], window["duration_sec"])


func _play_audition(from_ms: int, duration_sec: float) -> void:
	_invalidate_audition()

	var token := _audition_token

	BgMusic.play_from_source(id, BgMusic.stream, float(from_ms) / 1000.0)

	await get_tree().create_timer(maxf(duration_sec, 0.01)).timeout

	# Ignore this timer if another audition or playback replaced it.
	if token != _audition_token:
		return

	if BgMusic.current_source_id == id:
		BgMusic.stop_from_source(id)


func _invalidate_audition() -> void:
	_audition_token += 1


func _audition_window(marker_ms: int, dir: float) -> Dictionary:
	var from_ms := marker_ms
	var duration_sec := AUDITION_SEC

	if dir < 0.0:
		from_ms = maxi(int(%slider.min_value), marker_ms - int(AUDITION_SEC * 1000.0))

		duration_sec = float(marker_ms - from_ms) / 1000.0

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
