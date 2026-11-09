extends Control

const GAME_SCENE_PATH := "res://scenes/gameplay/game.tscn"
const PULSE_STRENGTH := 0.12
const PULSE_FALLOFF := 0.25
const BEAT_MUTE_ON_SONG_CHANGE := 0.5

var _pending_game = false
var _preview_chart_path: String = ""
var _current_bpm: float = 0.0
var _current_offset: float = 0.0
var _last_beat: int = -1
var _pulse_tween: Tween = null
var _transitioning: bool = false
var _synced_stream: AudioStream = null
var _initial_select_done: bool = false
var _beat_muted_until_msec: int = 0
var _leaving: bool = false

@onready var draw_here_label: Label = %"Draw Here"
@onready var beat_sound: AudioStreamPlayer = $"beat_sound"
@onready var draw_manager: Line2D = $draw
@onready var level_list: Control = $"Main Content/HBoxContainer/RSide/MaxLevelWidth/Level List"
@onready var level_details: Control = %LevelDetails
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	DiscordRPC.set_activity("in Level Selector", "Choosing a beatmap...")
	GlobalBackground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	animation_player.play("Opening")
	GlobalBackground.set_base_alpha(0.7)
	call_deferred("_warn_skipped_incomplete")
	level_list.call_deferred("reload_levels")


func _process(_delta: float) -> void:
	if not _can_process_beats():
		return

	var current_beat := _get_current_beat()

	if _is_new_beat(current_beat):
		_process_beat(current_beat)


func _on_sign_mouse_entered() -> void:
	draw_manager.start()


func _on_sign_mouse_exited() -> void:
	draw_manager.stop()


func _warn_skipped_incomplete() -> void:
	var n := int(level_list.call("get_skipped_incomplete_count"))
	if n <= 0:
		return
	var msg := "%d incomplete level%s hidden (solo notes need setup)." % [n, "" if n == 1 else "s"]
	Notification.show_toast("Levels Hidden", msg, NotificationToast.Kind.INFO, 4.0)


func _on_level_item_hovered(chart_path: String) -> void:
	if _leaving:
		return
	if chart_path.is_empty() or chart_path == _preview_chart_path:
		return

	level_details.refresh(chart_path)
	_preview_chart_path = chart_path

	var chart := ChartData.new()
	chart.chart_path = chart_path
	chart.metadata = ChartParser.parse_metadata(chart_path)
	if chart.is_empty():
		return

	GlobalBackground.change(str(chart.get_bg()))
	_update_chart_preview(chart)
	_play_chart_preview(chart)
	if not _initial_select_done:
		_synced_stream = null
		return


func _update_chart_preview(chart: ChartData) -> void:
	_current_bpm = chart.get_bpm()
	_current_offset = chart.beat_offset()

	GlobalBackground.change(str(chart.get_bg()))

	var beat_duration := _get_beat_duration()
	var preview := chart.preview_start()
	_last_beat = int(preview / beat_duration) - 1

	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	if draw_here_label != null:
		draw_here_label.offset_transform_scale = Vector2.ONE


func _get_beat_duration() -> float:
	return 1.0 / _current_bpm if _current_bpm > 0.0 else 0.5


func _play_chart_preview(chart: ChartData) -> void:
	var song := chart.song_path()

	if song.is_empty():
		return

	var stream_call := Global.load_safely_async(song)
	var stream = await stream_call.completed
	if stream == null:
		return

	if _is_current_song(stream):
		_sync_current_song()
		return

	_mute_beats(BEAT_MUTE_ON_SONG_CHANGE)
	BgMusic.change_song(stream, chart.preview_start())


func _is_current_song(stream: AudioStream) -> bool:
	if not BgMusic.playing or BgMusic.stream == null:
		return false

	var current_path := BgMusic.stream.resource_path
	var new_path := stream.resource_path

	return (BgMusic.stream == stream or (not current_path.is_empty() and current_path == new_path))


func _sync_current_song() -> void:
	_synced_stream = BgMusic.stream
	_transitioning = false

	var audio_time := BgMusic.get_playback_position() - _current_offset
	var beat_duration := _get_beat_duration()

	_last_beat = int(audio_time / beat_duration) if audio_time >= 0.0 else -1


func _play_selected() -> void:
	if _leaving:
		return
	_leaving = true
	_mute_beats(BEAT_MUTE_ON_SONG_CHANGE)
	BgMusic.change_song()
	LevelLoader.load_selected(level_list)
	_pending_game = true
	animation_player.play("Out")


func _can_process_beats() -> bool:
	return (_current_bpm > 0.0 and BgMusic != null and BgMusic.playing)


func _get_current_beat() -> int:
	var beat_duration := _get_beat_duration()
	var audio_time := BgMusic.get_playback_position() - _current_offset

	if audio_time < 0.0:
		return -1
	return int(audio_time / beat_duration)


func _handle_stream_change(current_beat: int) -> bool:
	if BgMusic.stream == _synced_stream:
		return false

	_synced_stream = BgMusic.stream
	_last_beat = current_beat
	_transitioning = false

	return true


#
#
func _handle_transition(current_beat: int) -> bool:
	if not _transitioning and current_beat < _last_beat:
		_transitioning = true
		_last_beat = current_beat
		return true

	if not _transitioning:
		return false

	if current_beat <= _last_beat:
		return true

	_last_beat = current_beat
	_transitioning = false
	return false


func _is_new_beat(current_beat: int) -> bool:
	return current_beat >= 0 and current_beat != _last_beat


func _process_beat(current_beat: int) -> void:
	_last_beat = current_beat

	_emit_beat()
	if not _beats_muted():
		beat_sound.play()

	if level_list != null and level_list.has_method("pulse_selected"):
		level_list.call("pulse_selected")


func _mute_beats(duration: float) -> void:
	_beat_muted_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	if beat_sound != null:
		beat_sound.stop()


func _beats_muted() -> bool:
	return Time.get_ticks_msec() < _beat_muted_until_msec


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Out":
		if _pending_game:
			get_tree().change_scene_to_file(GAME_SCENE_PATH)
		else:
			get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")


func _on_draw_guessed_shape(shape: String) -> void:
	if _leaving:
		return
	if shape == "circle":
		_leaving = true
		GlobalBackground.change(null)
		animation_player.play("Out")
	elif shape == "triangle":
		if level_list.levels.is_empty():
			Notification.show_toast(
				"There's No Level Selected",
				"Install a level packs first using import button",
				NotificationToast.Kind.WARN,
			)
		else:
			_play_selected()


func _emit_beat() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var target_scale := 1.0 + PULSE_STRENGTH
	var tween := create_tween()
	tween.set_parallel(true)
	(
		tween
		.tween_property(draw_here_label, "offset_transform_scale", Vector2(
			target_scale,
			target_scale,
		), PULSE_FALLOFF * 0.2)
		.set_ease(Tween.EASE_OUT)
	)
	(
		tween
		.tween_property(draw_here_label, "offset_transform_scale", Vector2.ONE, PULSE_FALLOFF)
		.set_delay(PULSE_FALLOFF * 0.2)
		.set_ease(Tween.EASE_OUT)
	)
	_pulse_tween = tween


func _on_resized() -> void:
	pass # Replace with function body.
