extends Control

@onready var animation_player: AnimationPlayer = $AnimationPlayer

@onready var drawer: Line2D = $draw


func _ready() -> void:
	DiscordRPC.set_activity("in Settings", "Tweaking some stuff...")
	GlobalBackground.change(null)
	VolumePopup.hide_pop_up()
	VolumePopup.can_popup = false


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Out":
		get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")


func _on_draw_guessed_shape(shape: String) -> void:
	if shape == "circle":
		animation_player.play("Out")


func _on_panel_draw_mouse_entered() -> void:
	drawer.start()


func _on_panel_draw_mouse_exited() -> void:
	drawer.stop()
