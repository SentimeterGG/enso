extends Control
@onready var _name_edit: LineEdit = %SongNameEdit
@onready var _source_edit: LineEdit = %SongAuthorEdit
@onready var _mapper_edit: LineEdit = %MapperEdit
@onready var _song_edit: LineEdit = %SongPathEdit
@onready var _picker: ColorPicker = %ColorPicker
@onready var _list: HBoxContainer = %list_colorscheme
@onready var _preview_slider: HSlider = %PreviewSlider
@onready var _preview_label: Label = %PreviewLabel
@onready var _beat_slider: HSlider = %BeatSlider
@onready var _beat_label: Label = %BeatLabel
@onready var _bpm_spin: SpinBox = %BpmSpin
@onready var _diff_spin: SpinBox = %DiffSpin
@onready var _diff_label: Label = %DiffLabel
@onready var _save_dialog: FileDialog = %ExportPopup
@onready var _load_dialog: FileDialog = %LoadSong
@onready var _preview_player: AudioStreamPlayer = $PreviewPlayer
@onready var _beat_player: AudioStreamPlayer = $BeatPlayer
const NUDGE_MS := 10
const AUDITION_SEC := 0.05
var _preview_audition_state := {"active": false}
var _beat_audition_state := {"active": false}

func _ready() -> void:
	_on_preview_changed(_preview_slider.value)
	_on_beat_changed(_beat_slider.value)
	_on_diff_changed(_diff_spin.value)
	for child in _list.get_children():
		if child is ColorRect:
			_make_removable(child)
	var initial_song := _song_edit.text.strip_edges()
	if not initial_song.is_empty():
		_load_song(initial_song)

func _process(_delta: float) -> void:
	_sync_slider(_preview_player, _preview_slider, _preview_label)
	_sync_slider(_beat_player, _beat_slider, _beat_label)
	_check_audition_end(_preview_player, _preview_audition_state, _preview_slider)
	_check_audition_end(_beat_player, _beat_audition_state, _beat_slider)

func _sync_slider(player: AudioStreamPlayer, slider: HSlider, label: Label) -> void:
	if player == null or slider == null:
		return
	if player.stream == null:
		return
	if player.playing and not player.stream_paused:
		var ms := int(player.get_playback_position() * 1000.0)
		ms = clampi(ms, int(slider.min_value), int(slider.max_value))
		slider.set_value_no_signal(ms)
		label.text = _format_ms(ms)

func _check_audition_end(player: AudioStreamPlayer, state: Dictionary, slider: HSlider) -> void:
	if not state.get("active", false):
		return
	if player.stream == null:
		return
	if not player.playing or player.stream_paused:
		_stop_audition(player)
		state["active"] = false
		return
	var remaining: float = player.stream.get_length() - player.get_playback_position()
	if remaining <= 0.0:
		_stop_audition(player)
		state["active"] = false

func _stop_audition(player: AudioStreamPlayer) -> void:
	if player.playing:
		player.stop()

func _on_browse_pressed() -> void:
	_load_dialog.popup_centered(Vector2i(600, 400))

func _on_song_file_selected(path: String) -> void:
	_song_edit.text = path
	_load_song(path)

func _on_song_text_submitted(path: String) -> void:
	_load_song(path.strip_edges())

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
	if player.playing and not player.stream_paused:
		player.stream_paused = true
		return
	if other.playing and not other.stream_paused:
		other.stop()
	if player.stream_paused:
		player.stream_paused = false
		var start_ms := int(clampi(floor(slider.value), floor(slider.min_value), floor(slider.max_value)))
		player.play(float(start_ms) / 1000.0)
	else:
		var start_ms := int(clampi(floor(slider.value), floor(slider.min_value), floor(slider.max_value)))
		player.play(float(start_ms) / 1000.0)

func _on_preview_nudge_minus() -> void:
	_do_nudge(_preview_slider, _preview_label, _preview_player, _preview_audition_state, -1.0)

func _on_preview_nudge_plus() -> void:
	_do_nudge(_preview_slider, _preview_label, _preview_player, _preview_audition_state, 1.0)

func _on_beat_nudge_minus() -> void:
	_do_nudge(_beat_slider, _beat_label, _beat_player, _beat_audition_state, -1.0)

func _on_beat_nudge_plus() -> void:
	_do_nudge(_beat_slider, _beat_label, _beat_player, _beat_audition_state, 1.0)

func _do_nudge(slider: HSlider, label: Label, player: AudioStreamPlayer, state: Dictionary, dir: float) -> void:
	slider.value = clampi(int(slider.value) + int(NUDGE_MS * dir), int(slider.min_value), int(slider.max_value))
	label.text = _format_ms(int(slider.value))
	if player.stream == null:
		return

	var marker_ms := int(slider.value)
	var play_from_ms := marker_ms
	var play_duration_sec := AUDITION_SEC

	if dir < 0.0:
		# Preview leading up to the marker, so it reads as playing backward.
		play_from_ms = maxi(int(slider.min_value), marker_ms - int(AUDITION_SEC * 1000.0))
		play_duration_sec = (marker_ms - play_from_ms) / 1000.0

	if state.get("active", false):
		player.stop()
	player.stop()
	player.play(float(play_from_ms) / 1000.0)

	if state.get("active", false):
		return

	state["active"] = true
	await get_tree().create_timer(play_duration_sec).timeout
	if player.playing:
		player.stop()
	state["active"] = false

func _format_ms(ms: int) -> String:
	var total_s := floori(ms / 1000.0)
	var m := floori(total_s / 60.0)
	var s := total_s % 60
	var left := ms % 1000
	return "%d:%02d.%03d" % [m, s, left]

func _on_preview_changed(v: float) -> void:
	_preview_label.text = _format_ms(int(v))
	if _preview_player.stream != null and _preview_player.playing and not _preview_player.stream_paused:
		_preview_player.play(float(v) / 1000.0)

func _on_beat_changed(v: float) -> void:
	_beat_label.text = _format_ms(int(v))
	if _beat_player.stream != null and _beat_player.playing and not _beat_player.stream_paused:
		_beat_player.play(float(v) / 1000.0)

func _on_export_pressed() -> void:
	_save_dialog.popup_centered(Vector2i(600, 400))

func _on_save_dir_selected(base_dir: String) -> void:
	var song_name := _name_edit.text.strip_edges()
	var song_author := _source_edit.text.strip_edges()
	var mapper := _mapper_edit.text.strip_edges()
	if song_name.is_empty():
		song_name = "untitled"
	if song_author.is_empty():
		song_author = "unknown"
	if mapper.is_empty():
		mapper = "unknown"
	var folder_name := _sanitize_folder_name("%s by %s mapped by %s" % [song_name, song_author, mapper])
	var out_dir := base_dir.path_join(folder_name)
	if not DirAccess.dir_exists_absolute(out_dir):
		var err := DirAccess.make_dir_recursive_absolute(out_dir)
		if err != OK:
			push_error("Failed to create folder: " + out_dir + " " + error_string(err))
			return
	var src_song := _song_edit.text.strip_edges()
	var song_file := "song.mp3"
	if not src_song.is_empty():
		song_file = _resolve_song_filename(src_song)
		_copy_song_into(src_song, out_dir.path_join(song_file))
	var text := _build_metadata_text("./" + song_file)
	var chart_path := out_dir.path_join("chart.enso")
	var f := FileAccess.open(chart_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to write chart: " + chart_path + " " + error_string(FileAccess.get_open_error()))
		return
	f.store_string(text)
	f.close()

func _resolve_song_filename(src: String) -> String:
	var s := src.strip_edges()
	if s.begins_with("res://") or s.begins_with("user://"):
		return s.get_file()
	return s.get_file().strip_edges()

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

func _copy_song_into(src: String, dst: String) -> void:
	var abs_src := _resolve_song_abs(src)
	if abs_src.is_empty():
		return
	if abs_src == dst:
		return
	if not FileAccess.file_exists(abs_src) and not FileAccess.file_exists(src):
		push_error("Song file not found, skipping copy: " + src)
		return
	var read_path := abs_src if FileAccess.file_exists(abs_src) else src
	if DirAccess.copy_absolute(read_path, dst) == OK:
		return
	var data := FileAccess.get_file_as_bytes(read_path)
	if data.is_empty():
		push_error("Failed to read song file: " + read_path)
		return
	var out := FileAccess.open(dst, FileAccess.WRITE)
	if out == null:
		push_error("Failed to write song copy: " + dst)
		return
	out.store_buffer(data)
	out.close()

func _sanitize_folder_name(raw: String) -> String:
	var bad := ["/", "\\", ":", "*", "?", '"', "<", ">", "|"]
	var out := raw.strip_edges()
	for ch in bad:
		out = out.replace(ch, "_")
	out = out.strip_edges().rstrip(".")
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.is_empty():
		out = "untitled"
	if out.length() > 120:
		out = out.substr(0, 120).strip_edges()
	return out

func _build_metadata_text(song_value: String) -> String:
	var name_song := _name_edit.text.strip_edges() if _name_edit else ""
	var source := _source_edit.text.strip_edges() if _source_edit else ""
	var mapper := _mapper_edit.text.strip_edges() if _mapper_edit else ""
	var colors := _collect_colors()
	var colors_str := "[" + ", ".join(colors.map(func(c): return '"' + c + '"')) + "]"
	var preview := int(_preview_slider.value) if _preview_slider else 0
	var beat0 := int(_beat_slider.value) if _beat_slider else 0
	var bpm := int(_bpm_spin.value) if _bpm_spin else 120
	var od := int(_diff_spin.value) if _diff_spin else 0
	return "[metadata]\nname = %s\nsource = %s\nmapper = %s\nsong = %s\ncolor_scheme = %s\npreview_start = %d\nbpm = %d\nbeat0 = %d\noverall_difficulty = %d\n\n[notes]\n" % [name_song, source, mapper, song_value, colors_str, preview, bpm, beat0, od]

func _collect_colors() -> Array:
	var out: Array = []
	for child in _list.get_children():
		if child is ColorRect:
			out.append("#" + child.color.to_html(false).to_upper())
	return out

func _on_add_color() -> void:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(50, 50)
	rect.color = _picker.color
	_make_removable(rect)
	_list.add_child(rect)

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
