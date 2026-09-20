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
const NUDGE_MS := 10
const AUDITION_SEC := 0.05
var _preview_audition_id := 0
var _beat_audition_id := 0


func _ready() -> void:
	_on_preview_changed(_preview_slider.value)
	_on_beat_changed(_beat_slider.value)
	_on_diff_changed(_diff_spin.value)
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


## UI slot for level_creator's `chart_imported` signal.
## Fills every widget from the imported ChartData; owns all UI writes.
func when_import(chart: ChartData) -> void:
	if chart == null or chart.metadata.is_empty():
		return
	var metadata: Dictionary = chart.metadata
	if metadata.has("name"):
		_name_edit.text = str(metadata["name"])
	if metadata.has("source"):
		_source_edit.text = str(metadata["source"])
	if metadata.has("mapper"):
		_mapper_edit.text = str(metadata["mapper"])
	if metadata.has("video_bg"):
		_video_bg_edit.text = str(metadata["video_bg"])
	if metadata.has("bg"):
		_bg_edit.text = str(metadata["bg"])
	if metadata.has("song"):
		_song_edit.text = chart.song_path()
		if not _song_edit.text.is_empty():
			_load_song(_song_edit.text)
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
	var color_scheme_str := str(metadata.get("color_scheme", ""))
	for child in _list.get_children():
		if child is ColorRect:
			child.queue_free()
	if not color_scheme_str.is_empty():
		for color in _parse_color_scheme(color_scheme_str):
			_add_color_rect(color)


## Export gate for level_creator's Export button.
## Every metadata field is required except video_bg (optional).
## Sliders/spins always hold a value, so only text fields + color scheme gate.
func is_export_ready() -> bool:
	if _name_edit == null or _source_edit == null or _mapper_edit == null:
		return false
	if _name_edit.text.strip_edges().is_empty():
		return false
	if _source_edit.text.strip_edges().is_empty():
		return false
	if _mapper_edit.text.strip_edges().is_empty():
		return false
	if _song_edit == null or _song_edit.text.strip_edges().is_empty():
		return false
	if _bg_edit == null or _bg_edit.text.strip_edges().is_empty():
		return false
	if _bpm_spin != null and int(_bpm_spin.value) <= 0:
		return false
	if _list == null:
		return false
	for child in _list.get_children():
		if child is ColorRect:
			return true
	return false


## UI getter for level_creator's export flow.
## Returns plain data; file/folder IO stays in level_creator.gd.
## _dest_dir is ignored but accepted so `export_requested` signal (String) can
## still be connected without error — see level_creator.tscn.
func when_export(_dest_dir: String = "") -> Dictionary:
	return {
		"name": _name_edit.text.strip_edges() if _name_edit else "",
		"source": _source_edit.text.strip_edges() if _source_edit else "",
		"mapper": _mapper_edit.text.strip_edges() if _mapper_edit else "",
		"video_bg": _video_bg_edit.text.strip_edges() if _video_bg_edit else "",
		"bg": _bg_edit.text.strip_edges() if _bg_edit else "",
		"song_src": _song_edit.text.strip_edges() if _song_edit else "",
		"preview_start": int(_preview_slider.value) if _preview_slider else 0,
		"beat0": int(_beat_slider.value) if _beat_slider else 0,
		"bpm": int(_bpm_spin.value) if _bpm_spin else 120,
		"overall_difficulty": int(_diff_spin.value) if _diff_spin else 0,
		"color_scheme": _collect_colors(),
	}


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
	var stream := _load_audio_stream(p)
	if stream == null:
		push_error("Could not load audio: " + p)
		return
	_preview_player.stream = stream
	_beat_player.stream = stream
	_preview_player.stop()
	_beat_player.stop()
	_preview_player.stream_paused = false
	_beat_player.stream_paused = false
	var dur_ms := int(stream.get_length() * 1000.0)
	if dur_ms > 0:
		_preview_slider.max_value = dur_ms
		_beat_slider.max_value = dur_ms
	_preview_slider.set_value_no_signal(clampi(int(_preview_slider.value), 0, dur_ms))
	_beat_slider.set_value_no_signal(clampi(int(_beat_slider.value), 0, dur_ms))
	_preview_label.text = _format_ms(int(_preview_slider.value))
	_beat_label.text = _format_ms(int(_beat_slider.value))


func _load_audio_stream(path: String) -> AudioStream:
	var read_path := _resolve_song_abs(path)
	if read_path.is_empty():
		read_path = path
	if read_path.begins_with("res://") and ResourceLoader.exists(read_path):
		var res := load(read_path) as AudioStream
		if res != null:
			return res
	var ext := read_path.get_extension().to_lower()
	match ext:
		"mp3":
			var s := AudioStreamMP3.load_from_file(read_path)
			if s != null:
				return s
			var b_mp3 := FileAccess.get_file_as_bytes(read_path)
			if not b_mp3.is_empty():
				return AudioStreamMP3.load_from_buffer(b_mp3)
		"ogg", "oga":
			var o := AudioStreamOggVorbis.load_from_file(read_path)
			if o != null:
				return o
			var b_ogg := FileAccess.get_file_as_bytes(read_path)
			if not b_ogg.is_empty():
				return AudioStreamOggVorbis.load_from_buffer(b_ogg)
		"wav":
			var w := AudioStreamWAV.load_from_file(read_path)
			if w != null:
				return w
			var b_wav := FileAccess.get_file_as_bytes(read_path)
			if not b_wav.is_empty():
				return AudioStreamWAV.load_from_buffer(b_wav)
	return null


func _on_preview_play() -> void:
	_toggle(_preview_player, _beat_player, _preview_slider)


func _on_beat_play() -> void:
	_toggle(_beat_player, _preview_player, _beat_slider)


func _toggle(player: AudioStreamPlayer, other: AudioStreamPlayer, slider: HSlider) -> void:
	if player.stream == null:
		return
	_bump_audition_id(player)
	if player.playing and not player.stream_paused:
		player.stream_paused = true
		return
	if other.playing and not other.stream_paused:
		other.stop()
	if player.stream_paused:
		player.stream_paused = false
		var start_ms := int(
			clampi(floor(slider.value), floor(slider.min_value), floor(slider.max_value))
		)
		player.play(float(start_ms) / 1000.0)
	else:
		var start_ms := int(
			clampi(floor(slider.value), floor(slider.min_value), floor(slider.max_value))
		)
		player.play(float(start_ms) / 1000.0)


func _on_preview_nudge_minus() -> void:
	_do_nudge(_preview_slider, _preview_label, _preview_player, -1.0)


func _on_preview_nudge_plus() -> void:
	_do_nudge(_preview_slider, _preview_label, _preview_player, 1.0)


func _on_beat_nudge_minus() -> void:
	_do_nudge(_beat_slider, _beat_label, _beat_player, -1.0)


func _on_beat_nudge_plus() -> void:
	_do_nudge(_beat_slider, _beat_label, _beat_player, 1.0)


## Lag-free nudge audition, same style as mapping.gd's beat jumps: compute the
## target synchronously, move the slider without emitting (so
## _on_preview_changed/_on_beat_changed don't re-trigger play()), restart the
## player with a single play() (no stop-then-play gap), and let a generation
## counter invalidate stale stop-timers so spam-clicking never queues or drops.
func _do_nudge(slider: HSlider, label: LineEdit, player: AudioStreamPlayer, dir: float) -> void:
	var marker_ms := clampi(
		int(slider.value) + int(NUDGE_MS * dir), int(slider.min_value), int(slider.max_value)
	)
	slider.set_value_no_signal(marker_ms)
	label.text = _format_ms(marker_ms)
	if player.stream == null:
		return

	var play_from_ms := marker_ms
	var play_duration_sec := AUDITION_SEC

	if dir < 0.0:
		# Preview leading up to the marker, so it reads as playing backward.
		play_from_ms = maxi(int(slider.min_value), marker_ms - int(AUDITION_SEC * 1000.0))
		play_duration_sec = (marker_ms - play_from_ms) / 1000.0

	_bump_audition_id(player)
	var my_id := _audition_id(player)
	player.play(float(play_from_ms) / 1000.0)

	await get_tree().create_timer(maxf(play_duration_sec, 0.01)).timeout
	if _audition_id(player) == my_id and player.playing:
		player.stop()


func _bump_audition_id(player: AudioStreamPlayer) -> void:
	if player == _preview_player:
		_preview_audition_id += 1
	else:
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
		_preview_player.stream != null
		and _preview_player.playing
		and not _preview_player.stream_paused
	):
		_preview_player.play(float(v) / 1000.0)


func _on_beat_changed(v: float) -> void:
	_beat_label.text = _format_ms(int(v))
	if _beat_player.stream != null and _beat_player.playing and not _beat_player.stream_paused:
		_beat_player.play(float(v) / 1000.0)


## Typed playback position: Enter (or focus-out) in the time field seeks the
## slider/player. Accepts "m:ss.mmm" (e.g. 1:23.456), plain milliseconds
## (e.g. 83456 / 83456ms) or seconds (e.g. 83.456 / 83.456s).
func _on_preview_text_submitted(text: String) -> void:
	_apply_typed_time(_preview_label, _preview_slider, _preview_player, text)
	_preview_label.release_focus()


func _on_beat_text_submitted(text: String) -> void:
	_apply_typed_time(_beat_label, _beat_slider, _beat_player, text)
	_beat_label.release_focus()


func _on_preview_edit_focus_exited() -> void:
	_apply_typed_time(_preview_label, _preview_slider, _preview_player, _preview_label.text)


func _on_beat_edit_focus_exited() -> void:
	_apply_typed_time(_beat_label, _beat_slider, _beat_player, _beat_label.text)


func _apply_typed_time(
	edit: LineEdit, slider: HSlider, player: AudioStreamPlayer, text: String
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


## Parses a user-typed time into milliseconds, or -1 when invalid.
func _parse_ms(raw: String) -> int:
	var s := raw.strip_edges().to_lower().replace(",", ".")
	if s.is_empty():
		return -1
	if s.ends_with("ms"):
		s = s.trim_suffix("ms").strip_edges()
		return int(s) if s.is_valid_int() else -1
	if s.ends_with("s"):
		s = s.trim_suffix("s").strip_edges()
		return int(round(float(s) * 1000.0)) if s.is_valid_float() else -1
	if s.contains(":"):
		var parts := s.split(":")
		if parts.size() != 2:
			return -1
		var mins := parts[0].strip_edges()
		var secs := parts[1].strip_edges()
		if not mins.is_valid_int() or not secs.is_valid_float():
			return -1
		return int(mins) * 60000 + int(round(float(secs) * 1000.0))
	if s.is_valid_int():
		return int(s) # plain number = milliseconds
	if s.is_valid_float():
		return int(round(float(s) * 1000.0)) # decimal without unit = seconds
	return -1


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
		var token := part.strip_edges()
		token = token.trim_prefix('"').trim_prefix("'")
		token = token.trim_suffix('"').trim_suffix("'")
		var c := Color.from_string(token, Color.TRANSPARENT)
		if c != Color.TRANSPARENT:
			colors.append(c)
	return colors


func _on_load_bg_file_selected(path: String) -> void:
	_bg_edit.text = path


func _on_load_video_bg_file_selected(path: String) -> void:
	_video_bg_edit.text = path


func _on_browse_video_bg_button_pressed() -> void:
	_load_video_bg_dialog.popup_centered(Vector2i(600, 400))
	pass  # Replace with function body.


func _on_browse_bg_path_pressed() -> void:
	_load_bg_dialog.popup_centered(Vector2i(600, 400))
	pass # Replace with function body.

