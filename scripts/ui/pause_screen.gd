extends Control

const LEVEL_SELECTOR_PATH := "res://scenes/level_selector.tscn"
const OPEN_DUR := 0.25
const CLOSE_DUR := 0.2

var _paused := false
var _busy := false
var _resuming := false
var _tween: Tween = null

@onready var _dim: ColorRect = $ColorRect
@onready var _menu: VBoxContainer = $VBoxContainer
@onready var _continue_btn: Button = $VBoxContainer/Continue
@onready var _restart_btn: Button = $VBoxContainer/Restart
@onready var _quit_btn: Button = $VBoxContainer/Quit

@onready var animator: AnimationPlayer = %animator


func _ready() -> void:
	# Must keep processing while the tree is paused, otherwise the
	# Continue/Restart/Quit buttons freeze along with the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_paused = false
	_busy = false
	_resuming = false
	hide()
	_reset_anim_state()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if _busy or _resuming:
		return
	set_paused(not _paused)


func set_paused(value: bool) -> void:
	if value == _paused and visible == value:
		return
	if value:
		_open()
	else:
		# Plain unpause (e.g. external call): close with no follow-up action.
		close_then(Callable())


func _on_continue_pressed() -> void:
	if _busy or not _paused or _resuming:
		return
	# 1. Hide the pause menu (close tween, stay paused).
	_resuming = true
	_busy = true
	_set_buttons_disabled(true)
	_play_close()
	await _tween.finished
	visible = false
	_busy = false
	# 2. Play the countdown animator while still paused.
	if animator != null:
		animator.play("CountdownAfterPause")
	else:
		_finish_resume()

func _on_restart_pressed() -> void:
	if _busy or _resuming or not _paused:
		return
	close_then(func() -> void: get_tree().reload_current_scene())


func _on_quit_pressed() -> void:
	if _busy or _resuming or not _paused:
		return
	close_then(func() -> void: get_tree().change_scene_to_file(LEVEL_SELECTOR_PATH))


## Plays the close tween first, then runs the action (continue = empty).
func close_then(action: Callable) -> void:
	if _busy or _resuming:
		return
	_busy = true
	_set_buttons_disabled(true)
	_play_close()
	await _tween.finished
	visible = false
	_paused = false
	get_tree().paused = false
	_set_audio_paused(false)
	_set_video_paused(false)
	_busy = false
	_set_buttons_disabled(false)
	if action.is_valid():
		action.call()


func _open() -> void:
	if _busy or _resuming:
		return
	_paused = true
	get_tree().paused = true
	_set_audio_paused(true)
	_set_video_paused(true)
	visible = true
	_reset_anim_state()
	_play_open()
	await _tween.finished


func _reset_anim_state() -> void:
	if _dim != null:
		_dim.modulate.a = 0.0
	if _menu != null:
		_menu.pivot_offset = _menu.size * 0.5
		_menu.scale = Vector2(0.9, 0.9)
		_menu.modulate.a = 0.0


func _play_open() -> void:
	_kill_tween()
	_menu.pivot_offset = _menu.size * 0.5
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_dim, "modulate:a", 1.0, OPEN_DUR)
	_tween.tween_property(_menu, "modulate:a", 1.0, OPEN_DUR)
	_tween.tween_property(_menu, "scale", Vector2.ONE, OPEN_DUR)


func _play_close() -> void:
	_kill_tween()
	_menu.pivot_offset = _menu.size * 0.5
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_IN)
	_tween.tween_property(_dim, "modulate:a", 0.0, CLOSE_DUR)
	_tween.tween_property(_menu, "modulate:a", 0.0, CLOSE_DUR)
	_tween.tween_property(_menu, "scale", Vector2(0.9, 0.9), CLOSE_DUR)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_buttons_disabled(value: bool) -> void:
	for b in [_continue_btn, _restart_btn, _quit_btn]:
		if b != null:
			b.disabled = value


func _set_audio_paused(value: bool) -> void:
	var bg := get_node_or_null("/root/BgMusic") as AudioStreamPlayer
	if bg != null and bg.playing:
		bg.stream_paused = value


func _set_video_paused(value: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var vp := scene.get_node_or_null("%VideoStreamPlayer")
	if vp != null and "paused" in vp:
		vp.paused = value


func _on_animator_animation_finished(anim_name: StringName) -> void:
	if anim_name == "CountdownAfterPause":
		if not _resuming:
			return
		# 3. Countdown done -> actually continue (unpause).
		_finish_resume()
	pass # Replace with function body.


## Shared unpause after the countdown (menu already hidden).
func _finish_resume() -> void:
	_resuming = false
	visible = false
	_paused = false
	get_tree().paused = false
	_set_audio_paused(false)
	_set_video_paused(false)
	_busy = false
	_set_buttons_disabled(false)
