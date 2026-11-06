extends Control

const LEVEL_SELECTOR_PATH := "res://scenes/menus/level_selector.tscn"

var _shown := false

@onready var _anim: AnimationPlayer = $GameOverAnim
@onready var _restart_btn: Button = $Menu/VBoxContainer2/VBoxContainer/Restart
@onready var _quit_btn: Button = $Menu/VBoxContainer2/VBoxContainer/Quit


func _ready() -> void:
	_shown = false
	_set_buttons_disabled(true)
	hide()


func _on_health_bar_health_depleted() -> void:
	if _shown:
		return
	var scene := get_tree().current_scene
	if scene != null:
		var win := scene.get_node_or_null("UI/WinScreen")
		if win != null and win.visible:
			return
	_shown = true
	_stop_gameplay()
	_set_buttons_disabled(false)
	visible = true
	if _anim != null and _anim.has_animation("show"):
		_anim.play("show")


func _on_restart_pressed() -> void:
	if not _shown:
		return
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	if not _shown:
		return
	get_tree().change_scene_to_file(LEVEL_SELECTOR_PATH)


func _stop_gameplay() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return
	await _hide_note_column()
	_cleanup(scene)


func _hide_note_column():
	var tween = %note_column.create_tween()
	tween.tween_property(%note_column, "modulate:a", 0.0, 1.0)
	await tween.finished


func _cleanup(scene: Node):
	BgMusic.stop()

	Global.call_if_exists(scene.get_node_or_null("note_scheduler"), "end")
	Global.call_if_exists(scene.get_node_or_null("draw"), "stop")

	var pause := scene.get_node_or_null("UI/PauseScreen")
	pause.set_process_unhandled_input(false)


func _set_buttons_disabled(value: bool) -> void:
	for b in [_restart_btn, _quit_btn]:
		if b != null:
			b.disabled = value
