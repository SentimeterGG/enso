# main_menu.gd — Main menu controller: plays the logo idle + opening transition
# animations, enables free drawing after the intro, and goes to the level
# selector scene when a circle gesture is recognized.
# RETURN: route to the level selector when a circle is drawn
extends Control

@onready var draw_manager: Line2D = $draw


func _ready() -> void:
	$RB/MarginContainer/ENSO/Bobbing.play("idle")
	$Transition.play("Opening")
	draw_manager.start()


func _on_transition_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Opening":
		pass
	elif anim_name == "Out":
		get_tree().change_scene_to_file("res://scenes/level_selector.tscn")
	elif anim_name == "Out_settings":
		get_tree().change_scene_to_file("res://scenes/settings_tab.tscn")


func _on_draw_guessed_shape(shape: String) -> void:
	if shape == "circle":
		$Transition.play("Out")
	elif shape == "line":
		$Transition.play("Out")
	pass  # Replace with function body.
