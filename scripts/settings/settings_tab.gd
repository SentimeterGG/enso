extends Control

@onready var exit_button: Button = $setting/ExitButton
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var fs_button: Button = $setting/FSButton
@onready var drawer: Line2D = $draw

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	VolumePopup.can_popup = false
	drawer.start()
	if Global.settingsData.fullscreen == true:
		fs_button.text = "ON"
	else: 
		fs_button.text = "OFF"

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_exit_button_button_down() -> void:
	animation_player.play("Out")
	exit_button.disabled = true


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Out":
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_fs_button_button_down() -> void:
	if Global.settingsData.fullscreen == true:
		Global.settingsData.fullscreen = false
		fs_button.text = "OFF"
	else: 
		Global.settingsData.fullscreen = true
		fs_button.text = "ON"
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if Global.settingsData.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	Global.save(Global.settingsData, Global.settingsData.save_file_name)
