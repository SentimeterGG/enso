extends VBoxContainer



# Value Tweaker
@onready var fs_button: Button = $FullscreenSetting/FSButton


func _ready() -> void:
	Global.toggle_window.connect(fullscreen_changed)
	if Global.settingsData.fullscreen == true:
		fs_button.text = "ON"
	else:
		fs_button.text = "OFF"

func _on_fs_button_button_down() -> void:
	%OsuHitSound.play()
	if Global.settingsData.fullscreen == true:
		Global.settingsData.fullscreen = false
		fs_button.text = "OFF"
	else:
		Global.settingsData.fullscreen = true
		fs_button.text = "ON"
	DisplayServer.window_set_mode(
		(
			DisplayServer.WINDOW_MODE_FULLSCREEN
			if Global.settingsData.fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)
	Global.save(Global.settingsData, Global.settingsData.save_file_name)

func fullscreen_changed():
	if Global.settingsData.fullscreen == true:
		fs_button.text = "OFF"
	else:
		fs_button.text = "ON"
