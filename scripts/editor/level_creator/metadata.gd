extends Control
@onready var _name_edit: LineEdit = %SongNameEdit
@onready var _source_edit: LineEdit = %SongAuthorEdit
@onready var _mapper_edit: LineEdit = %MapperEdit
@onready var _video_bg_edit: LineEdit = %VideoBgPathEdit
@onready var _bg_edit: LineEdit = %BGPath
@onready var _song_edit: LineEdit = %SongPathEdit
@onready var _picker: ColorPicker = %ColorPicker
@onready var _list: HBoxContainer = %list_colorscheme
@onready var _preview_slider: HSlider = %PreviewSlider
@onready var _preview_label: LineEdit = %PreviewLabelEdit
@onready var _beat_slider: HSlider = %BeatSlider
@onready var _beat_label: LineEdit = %BeatLabelEdit
@onready var _bpm_spin: SpinBox = %BpmSpin
@onready var _diff_spin: SpinBox = %DiffSpin
@onready var _diff_label: Label = %DiffLabel
@onready var _load_dialog: FileDialog = %LoadSong
@onready var _load_video_bg_dialog: FileDialog = %LoadVideoBG
@onready var _load_bg_dialog: FileDialog = %LoadBG
@onready var _preview_player: AudioStreamPlayer = $PreviewPlayer
@onready var _beat_player: AudioStreamPlayer = $BeatPlayer
@onready var _end_song_player: AudioStreamPlayer = $EndSongPlayer
@onready var _end_song_slider: HSlider = %EndSongSlider
@onready var _end_song_label: LineEdit = %EndSongEdit
const NUDGE_MS := 10
const AUDITION_SEC := 0.05
var _preview_audition_id := 0
var _beat_audition_id := 0
var _end_song_audition_id := 0


func _ready() -> void:
	BgMusic.FADE_DURATION = 0.4
	_on_preview_changed(_preview_slider.value)
	_on_beat_changed(_beat_slider.value)
	_on_diff_changed(_diff_spin.value)
	_on_end_song_value_changed(_end_song_slider.value)
	_preview_label.text_submitted.connect(_on_preview_text_submitted)
	_preview_label.focus_exited.connect(_on_preview_edit_focus_exited)
	_beat_label.text_submitted.connect(_on_beat_text_submitted)
	_beat_label.focus_exited.connect(_on_beat_edit_focus_exited)
	for child in _list.get_children():
		if child is ColorRect:
			_make_removable(child)
	var initial_song := _song_edit.text.strip_edges()
	if not initial_song.is_empty():
		_load_song(initial_song)


func _process(_delta: float) -> void:
	_sync_slider(_preview_player, _preview_slider, _preview_label)
	_sync_slider(_beat_player, _beat_slider, _beat_label)


func _sync_slider(player: AudioStreamPlayer, slider: HSlider, label: LineEdit) -> void:
	if player == null or slider == null or label == null:
		return
	if player.stream == null:
		return
	if label.has_focus():
		return # don't clobber what the user is currently typing
	if player.playing and not player.stream_paused:
		var ms := int(player.get_playback_position() * 1000.0)
		ms = clampi(ms, int(slider.min_value), int(slider.max_value))
		slider.set_value_no_signal(ms)
		label.text = _format_ms(ms)


func _on_browse_pressed() -> void:
	_load_dialog.popup_centered(Vector2i(600, 400))


func _on_song_file_selected(path: String) -> void:
	_song_edit.text = path
	_load_song(path)


func _on_song_text_submitted(path: String) -> void:
	_load_song(path.strip_edges())


func load_song(path: String) -> void:
	_load_song(path)


func when_import(chart: ChartData) -> void:
	if chart == null or chart.metadata.is_empty():
		return
	var metadata: Dictionary = chart.metadata
	_apply_chart_fields(metadata, chart)
	_apply_chart_timing(metadata)
	_replace_color_scheme(str(metadata.get("color_scheme", "")))


func _apply_chart_fields(metadata: Dictionary, chart: ChartData) -> void:
	if metadata.has("name"):
		_name_edit.text = str(metadata["name"])
	if metadata.has("source"):
		_source_edit.text = str(metadata["source"])
	if metadata.has("mapper"):
		_mapper_edit.text = str(metadata["mapper"])
	if metadata.has("video_bg"):
		_video_bg_edit.text = chart.get_video_background()
	if metadata.has("bg"):
		_bg_edit.text = chart.get_bg()
	if metadata.has("song"):
		_song_edit.text = chart.song_path()
		if not _song_edit.text.is_empty():
			_load_song(_song_edit.text)


func _apply_chart_timing(metadata: Dictionary) -> void:
	if metadata.has("preview_start"):
		var preview := int(metadata["preview_start"])
		_preview_slider.set_value_no_signal(preview)
		_preview_label.text = _format_ms(preview)
	if metadata.has("bpm"):
		_bpm_spin.value = int(metadata["bpm"])
	if metadata.has("beat0"):
		var beat0 := int(metadata["beat0"])
		_beat_slider.set_value_no_signal(beat0)
		_beat_label.text = _format_ms(beat0)
	if metadata.has("overall_difficulty"):
		_diff_spin.value = int(metadata["overall_difficulty"])
		_on_diff_changed(_diff_spin.value)
	if metadata.has("end_song_position"):
		var end_pos := int(metadata["end_song_position"])
		_end_song_slider.set_value_no_signal(end_pos)
		_end_song_label.text = _format_ms(end_pos)


func _replace_color_scheme(raw: String) -> void:
	for child in _list.get_children():
		if child is ColorRect:
			child.queue_free()
	if raw.is_empty():
		return
	for color in _parse_color_scheme(raw):
		_add_color_rect(color)


func is_export_ready() -> bool:
	if not _has_required_fields():
		return false
	if not _field_has_text(_song_edit):
		return false
	if not _field_has_text(_bg_edit):
		return false
	if _bpm_spin != null and int(_bpm_spin.value) <= 0:
		return false
	return _has_color_swatch()


func _has_required_fields() -> bool:
	return (
		_field_has_text(_name_edit) and _field_has_text(_source_edit)
		and _field_has_text(_mapper_edit)
	)


func _field_has_text(edit: LineEdit) -> bool:
	return edit != null and not edit.text.strip_edges().is_empty()


func _has_color_swatch() -> bool:
	if _list == null:
		return false
	for child in _list.get_children():
		if child is ColorRect:
			return true
	return false


func when_export(_dest_dir: String = "") -> Dictionary:
	return {
		"name": _line_text(_name_edit),
		"source": _line_text(_source_edit),
		"mapper": _line_text(_mapper_edit),
		"video_bg": _line_text(_video_bg_edit),
		"bg": _line_text(_bg_edit),
		"song_src": _line_text(_song_edit),
		"preview_start": _slider_int(_preview_slider, 0),
		"beat0": _slider_int(_beat_slider, 0),
		"bpm": _spin_int(_bpm_spin, 120),
		"overall_difficulty": _spin_int(_diff_spin, 0),
		"color_scheme": _collect_colors(),
		"end_song_position": _slider_int(_end_song_slider, 0),
	}


func _line_text(edit: LineEdit) -> String:
	return edit.text.strip_edges() if edit != null else ""


func _slider_int(slider: HSlider, fallback: int) -> int:
	return int(slider.value) if slider != null else fallback


func _spin_int(spin: SpinBox, fallback: int) -> int:
	return int(spin.value) if spin != null else fallback


func _add_color_rect(color: Color) -> void:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(50, 50)
	rect.color = color
	_make_removable(rect)
	_list.add_child(rect)


func _load_song(path: String) -> void:
	var p := path.strip_edges()
	if p.is_empty():
		return
	var stream := Global.load_safely(path)
	if stream == null:
		push_error("Could not load audio: " + p)
		return
	_assign_song_stream(stream)
	_sync_song_ranges(stream)


func _assign_song_stream(stream: AudioStream) -> void:
	_preview_player.stream = stream
	_beat_player.stream = stream
	_preview_player.stop()
	_beat_player.stop()
	_preview_player.stream_paused = false
	_beat_player.stream_paused = false


func _sync_song_ranges(stream: AudioStream) -> void:
	var duration_ms := int(stream.get_length() * 1000.0)
	if duration_ms > 0:
		_preview_slider.max_value = duration_ms
		_beat_slider.max_value = duration_ms
		_end_song_slider.max_value = duration_ms
	_preview_slider.set_value_no_signal(clampi(int(_preview_slider.value), 0, duration_ms))
	_beat_slider.set_value_no_signal(clampi(int(_beat_slider.value), 0, duration_ms))
	_preview_label.text = _format_ms(int(_preview_slider.value))
	_beat_label.text = _format_ms(int(_beat_slider.value))
	_end_song_label.text = _format_ms(int(_end_song_slider.value))


func _on_preview_play() -> void:
	_toggle(_preview_player, [_beat_player, _end_song_player], _preview_slider)


func _on_beat_play() -> void:
	_toggle(_beat_player, [_preview_player, _end_song_player], _beat_slider)


func _on_end_song_play() -> void:
	_toggle(_end_song_player, [_preview_player, _beat_player], _end_song_slider)


func _toggle(player: AudioStreamPlayer, others: Array[AudioStreamPlayer], slider: HSlider) -> void:
	if player.stream == null:
		return
	_bump_audition_id(player)
	if player.playing and not player.stream_paused:
		player.stream_paused = true
		return
	for other in others:
		if other.playing and not other.stream_paused:
			other.stop()
	player.stream_paused = false
	player.play(_slider_seconds(slider))


func _slider_seconds(slider: HSlider) -> float:
	var start_ms := int(
		clampi(floor(slider.value), floor(slider.min_value), floor(slider.max_value))
	)
	return float(start_ms) / 1000.0


func _on_preview_nudge_minus() -> void:
	_do_nudge(_preview_slider, _preview_label, _preview_player, -1.0)


func _on_preview_nudge_plus() -> void:
	_do_nudge(_preview_slider, _preview_label, _preview_player, 1.0)


func _on_end_song_nudge_plus() -> void:
	_do_nudge(_end_song_slider, _end_song_label, _end_song_player, -1.0)


func _on_end_song_nudge_minus() -> void:
	_do_nudge(_end_song_slider, _end_song_label, _end_song_player, 1.0)


func _on_beat_nudge_minus() -> void:
	_do_nudge(_beat_slider, _beat_label, _beat_player, -1.0)


func _on_beat_nudge_plus() -> void:
	_do_nudge(_beat_slider, _beat_label, _beat_player, 1.0)


func _do_nudge(slider: HSlider, label: LineEdit, player: AudioStreamPlayer, dir: float) -> void:
	var marker_ms := _nudged_marker_ms(slider, dir)
	slider.set_value_no_signal(marker_ms)
	label.text = _format_ms(marker_ms)
	if player.stream == null:
		return
	var window := _audition_window(slider, marker_ms, dir)
	await _play_audition(player, window["from_ms"], window["duration_sec"])


func _nudged_marker_ms(slider: HSlider, dir: float) -> int:
	return clampi(
		int(slider.value) + int(NUDGE_MS * dir),
		int(slider.min_value),
		int(slider.max_value),
	)


func _audition_window(slider: HSlider, marker_ms: int, dir: float) -> Dictionary:
	var from_ms := marker_ms
	var duration_sec := AUDITION_SEC
	if dir < 0.0:
		from_ms = maxi(int(slider.min_value), marker_ms - int(AUDITION_SEC * 1000.0))
		duration_sec = (marker_ms - from_ms) / 1000.0
	return { "from_ms": from_ms, "duration_sec": duration_sec }


func _play_audition(player: AudioStreamPlayer, from_ms: int, duration_sec: float) -> void:
	_bump_audition_id(player)
	var my_id := _audition_id(player)
	player.play(float(from_ms) / 1000.0)
	await get_tree().create_timer(maxf(duration_sec, 0.01)).timeout
	if _audition_id(player) == my_id and player.playing:
		player.stop()


func _bump_audition_id(player: AudioStreamPlayer) -> void:
	if player == _preview_player:
		_preview_audition_id += 1
	elif player == _end_song_player:
		_end_song_audition_id += 1
	elif player == _beat_player:
		_beat_audition_id += 1


func _audition_id(player: AudioStreamPlayer) -> int:
	if player == _preview_player:
		return _preview_audition_id
	return _beat_audition_id


func _format_ms(ms: int) -> String:
	var total_s := floori(ms / 1000.0)
	var m := floori(total_s / 60.0)
	var s := total_s % 60
	var left := ms % 1000
	return "%d:%02d.%03d" % [m, s, left]


func _on_preview_changed(v: float) -> void:
	_preview_label.text = _format_ms(int(v))
	if (
		_preview_player.stream != null and _preview_player.playing
		and not _preview_player.stream_paused
	):
		_preview_player.play(float(v) / 1000.0)


func _on_beat_changed(v: float) -> void:
	_beat_label.text = _format_ms(int(v))
	if _beat_player.stream != null and _beat_player.playing and not _beat_player.stream_paused:
		_beat_player.play(float(v) / 1000.0)


func _on_preview_text_submitted(text: String) -> void:
	_apply_typed_time(_preview_label, _preview_slider, _preview_player, text)
	_preview_label.release_focus()


func _on_beat_text_submitted(text: String) -> void:
	_apply_typed_time(_beat_label, _beat_slider, _beat_player, _beat_label.text)
	_beat_label.release_focus()


func _on_preview_edit_focus_exited() -> void:
	_apply_typed_time(_preview_label, _preview_slider, _preview_player, _preview_label.text)


func _on_beat_edit_focus_exited() -> void:
	_apply_typed_time(_beat_label, _beat_slider, _beat_player, _beat_label.text)


func _apply_typed_time(
	edit: LineEdit,
	slider: HSlider,
	_player: AudioStreamPlayer,
	text: String,
) -> void:
	if edit == null or slider == null:
		return
	var ms := _parse_ms(text)
	if ms < 0:
		edit.text = _format_ms(int(slider.value)) # invalid: revert
		return
	ms = clampi(ms, int(slider.min_value), int(slider.max_value))
	slider.value = ms # emits value_changed -> seeks if playing, updates field
	edit.text = _format_ms(ms)
	edit.caret_column = edit.text.length()


func _parse_ms(raw: String) -> int:
	var s := raw.strip_edges().to_lower().replace(",", ".")
	if s.is_empty():
		return -1
	if s.ends_with("ms"):
		return _parse_millisecond_token(s)
	if s.ends_with("s"):
		return _parse_second_token(s)
	if s.contains(":"):
		return _parse_clock_token(s)
	if s.is_valid_int():
		return int(s) # plain number = milliseconds
	if s.is_valid_float():
		return _seconds_to_ms(s) # decimal without unit = seconds
	return -1


func _parse_millisecond_token(token: String) -> int:
	var value := token.trim_suffix("ms").strip_edges()
	return int(value) if value.is_valid_int() else -1


func _parse_second_token(token: String) -> int:
	var value := token.trim_suffix("s").strip_edges()
	return _seconds_to_ms(value) if value.is_valid_float() else -1


func _parse_clock_token(token: String) -> int:
	var parts := token.split(":")
	if parts.size() != 2:
		return -1
	var minutes := parts[0].strip_edges()
	var seconds := parts[1].strip_edges()
	if not minutes.is_valid_int() or not seconds.is_valid_float():
		return -1
	return int(minutes) * 60000 + _seconds_to_ms(seconds)


func _seconds_to_ms(value: String) -> int:
	return int(round(float(value) * 1000.0))


func _resolve_song_abs(src: String) -> String:
	var s := src.strip_edges()
	if s.is_empty():
		return ""
	if s.begins_with("res://") or s.begins_with("user://"):
		return ProjectSettings.globalize_path(s)
	if s.begins_with("./") or s.begins_with("../") or not s.begins_with("/"):
		if s.begins_with("./"):
			s = s.substr(2)
		var proj := ProjectSettings.globalize_path("res://").path_join(s)
		if FileAccess.file_exists(proj):
			return proj
		return ProjectSettings.globalize_path(s) if s.begins_with("res://") else s
	return s


func _collect_colors() -> Array:
	var out: Array = []
	for child in _list.get_children():
		if child is ColorRect:
			out.append("#" + child.color.to_html(false).to_upper())
	return out


func _on_add_color() -> void:
	_add_color_rect(_picker.color)


func _make_removable(rect: ColorRect) -> void:
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	if rect.gui_input.is_connected(_on_rect_gui_input):
		return
	rect.gui_input.connect(_on_rect_gui_input.bind(rect))


func _on_rect_gui_input(event: InputEvent, rect: ColorRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		rect.queue_free()


func _on_diff_changed(v: float) -> void:
	var i := int(v)
	if i <= 3:
		_diff_label.text = "EASY"
	elif i <= 6:
		_diff_label.text = "MEDIUM"
	else:
		_diff_label.text = "HARD"


func _parse_color_scheme(raw: String) -> Array[Color]:
	var colors: Array[Color] = []
	var cleaned := raw.trim_prefix("[").trim_suffix("]").strip_edges()
	if cleaned.is_empty():
		return colors
	for part in cleaned.split(",", false):
		var color := _parse_color_token(part)
		if color != Color.TRANSPARENT:
			colors.append(color)
	return colors


func _parse_color_token(part: String) -> Color:
	var token := part.strip_edges()
	token = token.trim_prefix('"').trim_prefix("'")
	token = token.trim_suffix('"').trim_suffix("'")
	return Color.from_string(token, Color.TRANSPARENT)


func _on_load_bg_file_selected(path: String) -> void:
	_bg_edit.text = path


func _on_load_video_bg_file_selected(path: String) -> void:
	_video_bg_edit.text = path


func _on_browse_video_bg_button_pressed() -> void:
	_load_video_bg_dialog.popup_centered(Vector2i(600, 400))


func _on_browse_bg_path_pressed() -> void:
	_load_bg_dialog.popup_centered(Vector2i(600, 400))


func _on_end_song_value_changed(value: float) -> void:
	_end_song_label.text = _format_ms(int(value))
