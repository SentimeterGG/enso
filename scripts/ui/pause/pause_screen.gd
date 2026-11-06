extends Control

const LEVEL_SELECTOR_PATH := "res://scenes/menus/level_selector.tscn"

enum PauseState {
	CLOSED,
	OPENING,
	PAUSED,
	CLOSING,
	RESUMING,
}

var _state: PauseState = PauseState.CLOSED
var _pending_action: Callable = Callable()
var _intro_finished = false

@onready var _menu: VBoxContainer = $VBoxContainer
@onready var _continue_btn: Button = $VBoxContainer/Continue
@onready var _restart_btn: Button = $VBoxContainer/Restart
@onready var _quit_btn: Button = $VBoxContainer/Quit
@onready var pause_animator: AnimationPlayer = $AfterPause
@onready var animator: AnimationPlayer = %animator
@onready var media: Node = $MediaController


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_state = PauseState.CLOSED
	_pending_action = Callable()

	hide()
	_reset_anim_state()
	_set_buttons_disabled(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if _state == PauseState.CLOSED:
		set_paused(true)
	elif _state == PauseState.PAUSED:
		set_paused(false)


func set_paused(value: bool) -> void:
	if value:
		if _state == PauseState.CLOSED:
			_open()
	else:
		if _state == PauseState.PAUSED:
			_begin_close()


func _on_continue_pressed() -> void:
	if _state != PauseState.PAUSED:
		return

	_state = PauseState.RESUMING
	_set_buttons_disabled(true)

	_play_animation("Close")


func _on_restart_pressed() -> void:
	if _state != PauseState.PAUSED:
		return

	_begin_close(
		func() -> void:
			get_tree().reload_current_scene(),
	)


func _on_quit_pressed() -> void:
	if _state != PauseState.PAUSED:
		return

	_play_animation("Close")
	_begin_close(
		func() -> void:
			get_tree().change_scene_to_file(LEVEL_SELECTOR_PATH),
	)


func _open() -> void:
	if _state != PauseState.CLOSED:
		return

	_state = PauseState.OPENING

	get_tree().paused = true
	media.set_media_paused(true)

	visible = true
	_set_buttons_disabled(true)
	_reset_anim_state()

	_play_animation("Open")


func _begin_close(action: Callable = Callable()) -> void:
	if _state != PauseState.PAUSED:
		return

	_state = PauseState.CLOSING
	_pending_action = action

	_set_buttons_disabled(true)
	_play_animation("Close")


func _finish_close() -> void:
	visible = false

	_state = PauseState.CLOSED

	get_tree().paused = false
	media.set_media_paused(false)

	_set_buttons_disabled(false)

	var action := _pending_action
	_pending_action = Callable()

	if action.is_valid():
		action.call()


func _finish_resume() -> void:
	visible = false

	_state = PauseState.CLOSED
	_pending_action = Callable()

	get_tree().paused = false
	media.set_media_paused(false)

	if animator != null and not _intro_finished:
		animator.play()

	_set_buttons_disabled(false)


func _play_animation(anim_name: StringName) -> void:
	if pause_animator == null:
		_on_after_pause_animation_finished(anim_name)
		return

	if not pause_animator.has_animation(anim_name):
		push_warning("PauseMenu: Missing animation '%s'." % anim_name)
		_on_after_pause_animation_finished(anim_name)
		return

	pause_animator.play(anim_name)


func _reset_anim_state() -> void:
	if _menu != null:
		_menu.pivot_offset = _menu.size * 0.5
		_menu.scale = Vector2(0.9, 0.9)
		_menu.modulate.a = 0.0


func _on_after_pause_animation_finished(anim_name: StringName) -> void:
	match anim_name:
		"Open":
			if _state != PauseState.OPENING:
				return

			_state = PauseState.PAUSED
			_set_buttons_disabled(false)

			if animator != null:
				animator.pause()

		"Close":
			if _state == PauseState.RESUMING:
				_play_animation("CountdownAfterPause")

			elif _state == PauseState.CLOSING:
				_finish_close()

		"CountdownAfterPause":
			if _state != PauseState.RESUMING:
				return

			_finish_resume()


func _set_buttons_disabled(value: bool) -> void:
	for button in [_continue_btn, _restart_btn, _quit_btn]:
		if button != null:
			button.disabled = value


func _on_animator_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Intro":
		_intro_finished = true
	pass # Replace with function body.
