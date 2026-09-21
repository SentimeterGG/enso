# game_over.gd — Fail screen (node: UI/Game Over): shown when the health bar
# depletes. Stops the song/scheduler/drawing, plays the GameOverAnim "show"
# (cracked glass + SFX + menu fade), and offers Restart (reload the scene) or
# Quit (back to the level selector), mirroring pause_screen.gd. The tree is
# left unpaused so no process_mode juggling is needed.
# RETURN: scene reload or return to the level selector
extends Control

const LEVEL_SELECTOR_PATH := "res://scenes/level_selector.tscn"

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
		# Song already over and the win screen up (or about to be): the run
		# counts as finished, not failed.
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


## Halts the run the same way song-end does (music, scheduler, drawing) and
## blocks the pause menu so it can't open over the game-over screen.
func _stop_gameplay() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var tween = %note_manager.create_tween()
	tween.tween_property(%note_manager, "modulate:a", 0.0, 1.0)
	await tween.finished
	var bg := get_node_or_null("/root/BgMusic") as AudioStreamPlayer
	if bg != null:
		bg.stop()
	# Restart/Quit during the fade reloads the scene: bail instead of
	# touching freed nodes.
	if not is_instance_valid(scene):
		return
	if "note_scheduler" in scene:
		var sched = scene.get("note_scheduler")
		if sched != null and sched.has_method("end"):
			sched.call("end")
	var draw := scene.get_node_or_null("draw")
	if draw != null and draw.has_method("stop"):
		draw.call("stop")
	var pause := scene.get_node_or_null("UI/PauseScreen")
	if pause != null:
		pause.set_process_unhandled_input(false)


func _set_buttons_disabled(value: bool) -> void:
	for b in [_restart_btn, _quit_btn]:
		if b != null:
			b.disabled = value
