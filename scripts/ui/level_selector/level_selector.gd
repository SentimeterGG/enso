# level_selector.gd — Level selector screen controller: plays the opening/closing
# animations (Out returns to main menu, or enters game.tscn after a triangle
# "play" gesture confirms the current selection via LevelLoader), leaves for
# main menu on a circle gesture, and only enables drawing while the mouse
# hovers the side panel. Enter/ui_accept also confirms the selection.
# RETURN: route to main menu or game scene; drawing gated to the side panel
extends Control

const GAME_SCENE_PATH := "res://scenes/game.tscn"
const PULSE_STRENGTH := 0.12
const PULSE_FALLOFF := 0.25

var _pending_game := false
var _preview_chart_path: String = ""
var _current_bpm: float = 0.0
var _current_offset: float = 0.0
var _last_beat: int = -1
var _pulse_tween: Tween = null
var _transitioning: bool = false
@onready var draw_here_label: Label = %"Draw Here"
@onready var beat_sound: AudioStreamPlayer = $"beat_sound"
@onready var draw_manager: Line2D = $draw
@onready var level_list: Control = $"Main Content/HBoxContainer/RSide/Level List"


func _ready() -> void:
	$AnimationPlayer.play("Opening")


func play_selected() -> void:
	if level_list == null:
		push_warning("level_selector: level list not found.")
		return
	if has_node("/root/BgMusic"):
		var bg := get_node("/root/BgMusic") as AudioStreamPlayer
		if bg != null:
			bg.change_song()
	var chart := LevelLoader.load_selected(level_list)
	if chart.is_empty():
		push_warning("level_selector: selected chart failed to load, staying put.")
		return
	_pending_game = true
	$AnimationPlayer.play("Out")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Out":
		if _pending_game:
			get_tree().change_scene_to_file(GAME_SCENE_PATH)
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_draw_guessed_shape(shape: String) -> void:
	if shape == "circle":
		_pending_game = false
		$AnimationPlayer.play("Out")
	elif shape == "triangle":
		play_selected()


func _on_l_side_mouse_entered() -> void:
	draw_manager.start()


func _on_l_side_mouse_exited() -> void:
	draw_manager.stop()


func _physics_process(_delta: float) -> void:
	if _current_bpm <= 0.0 or draw_here_label == null:
		return
	if BgMusic == null or not BgMusic.playing:
		return
	var audio_time := BgMusic.get_playback_position() - _current_offset
	if audio_time < 0.0:
		return
	var beat_duration := 1.0 / _current_bpm
	var current_beat := int(audio_time / beat_duration)
	if _transitioning:
		if current_beat > _last_beat:
			_last_beat = current_beat
			_transitioning = false
		else:
			return
	if current_beat != _last_beat and current_beat >= 0:
		_last_beat = current_beat
		_emit_beat()
		beat_sound.play()


func _emit_beat() -> void:
	if draw_here_label == null:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var target_scale := 1.0 + PULSE_STRENGTH
	var tween := create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(
			draw_here_label,
			"offset_transform_scale",
			Vector2(target_scale, target_scale),
			PULSE_FALLOFF * 0.2
		)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(draw_here_label, "offset_transform_scale", Vector2.ONE, PULSE_FALLOFF)
		. set_delay(PULSE_FALLOFF * 0.2)
		. set_ease(Tween.EASE_OUT)
	)
	_pulse_tween = tween


func _on_level_item_hovered(chart_path: String) -> void:
	if chart_path.is_empty() or chart_path == _preview_chart_path:
		return
	_preview_chart_path = chart_path
	if not has_node("/root/BgMusic"):
		return
	var bg := get_node("/root/BgMusic") as AudioStreamPlayer
	if bg == null or not bg.has_method("change_song"):
		return
	var chart := ChartParser.load(chart_path)
	if chart.is_empty():
		return
	_current_bpm = chart.get_bpm()
	_current_offset = chart.beat_offset()
	_transitioning = true
	var beat_duration := 1.0 / _current_bpm if _current_bpm > 0.0 else 0.5
	var preview := chart.preview_start()
	_last_beat = int(preview / beat_duration) - 1
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if draw_here_label != null:
		draw_here_label.offset_transform_scale = Vector2.ONE
	var song := chart.song_path()
	if song.is_empty() or not ResourceLoader.exists(song):
		return
	var stream := load(song) as AudioStream
	if stream == null:
		return
	bg.change_song(stream, chart.preview_start())
