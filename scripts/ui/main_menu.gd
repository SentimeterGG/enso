# main_menu.gd — Main menu controller: plays the logo idle + opening transition
# animations, enables free drawing after the intro, and goes to the level
# selector scene when a circle gesture is recognized.
# RETURN: route to the level selector when a circle is drawn
extends Control

enum GoTo { NONE, PLAY, SETTINGS, EDITOR }

@onready var draw_manager: Line2D = $draw
var go_to: GoTo = GoTo.NONE


func _ready() -> void:
	VolumePopup.can_popup = true
	$RB/MarginContainer/ENSO/Bobbing.play("idle")
	if Global.first_time_playing:
		Global.first_time_playing = false
		$Transition.play("first_time_opening")
	else:
		$Transition.play("Opening")
	draw_manager.start()


func _on_transition_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Opening":
		pass
	elif anim_name == "Out":
		match go_to:
			GoTo.PLAY:
				get_tree().change_scene_to_file("res://scenes/level_selector.tscn")
			GoTo.SETTINGS:
				get_tree().change_scene_to_file("res://scenes/settings_tab.tscn")
			GoTo.EDITOR:
				get_tree().change_scene_to_file("res://scenes/level_creator.tscn")
			_:
				pass


func _on_draw_guessed_shape(shape: String) -> void:
	match shape:
		"circle":
			go_to = GoTo.PLAY
			$Transition.play("Out")
		"line":
			go_to = GoTo.SETTINGS
			$Transition.play("Out")
		"square":
			go_to = GoTo.EDITOR
			$Transition.play("Out")
		"exit":
			get_tree().quit()
