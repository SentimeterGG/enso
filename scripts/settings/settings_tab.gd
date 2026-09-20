extends Control

@onready var exit_button: Button = $setting/ExitButton
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var fs_button: Button = $setting/FSButton
@onready var bg_button: Button = $setting/BGButton


@onready var drawer: Line2D = $draw

@onready var master_slider: HSlider = $setting/Master
@onready var music_slider: HSlider = $setting/Music
@onready var effects_slider: HSlider = $setting/Effects
@onready var bg_dim_slider: HSlider = $setting/BG_Dim


@onready var master_label: Label = $setting/Master/VolumePercent
@onready var music_label: Label = $setting/Music/VolumePercent
@onready var effects_label: Label = $setting/Effects/VolumePercent
@onready var dim_percent_label: Label = $setting/BG_Dim/DimPercent

var can_play_hitsound: bool = false

const VOLUME_STEP := 5.0
const VOLUME_MIN := -60.0
const VOLUME_MAX := 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	VolumePopup.hide_pop_up()
	_sync_sliders_to_audio()
	Global.toggle_window.connect(fullscreen_changed)
	VolumePopup.can_popup = false
	if Global.settingsData.fullscreen == true:
		fs_button.text = "ON"
	else: 
		fs_button.text = "OFF"
	if Global.settingsData.video_bg == true:
		bg_button.text = "ON"
	else: 
		bg_button.text = "OFF"
	grab_volume_config()
	_connect_sliders()
	bg_dim_slider.value = 100.0 - Global.settingsData.bg_visibilty
	_update_label(bg_dim_slider, dim_percent_label)
	can_play_hitsound = true


func _connect_sliders() -> void:
	music_slider.value_changed.connect(_on_music_changed)
	master_slider.value_changed.connect(_on_master_changed)
	effects_slider.value_changed.connect(_on_effects_changed)

func grab_volume_config():
	_apply_bus_volume("Effect", Global.settingsData.effects_volume)
	_update_label(effects_slider, effects_label)
	_apply_bus_volume("Master", Global.settingsData.master_volume)
	_update_label(master_slider, master_label)
	_apply_bus_volume("Music", Global.settingsData.music_volume)
	_update_label(music_slider, music_label)

func _update_label(slider: HSlider, label: Label) -> void:
	label.text = "%d%%" % roundi(slider.value)


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Out":
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _sync_sliders_to_audio() -> void:
	music_slider.set_value_no_signal(_get_bus_slider_value("Music"))
	master_slider.set_value_no_signal(_get_bus_slider_value("Master"))
	effects_slider.set_value_no_signal(_get_bus_slider_value("Effect"))
	_update_label(music_slider, music_label)
	_update_label(master_slider, master_label)
	_update_label(effects_slider, effects_label)

func _get_bus_slider_value(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return _db_to_slider(AudioServer.get_bus_volume_db(idx))
	return 100.0

func _db_to_slider(db: float) -> float:
	return (db - VOLUME_MIN) / (VOLUME_MAX - VOLUME_MIN) * 100.0

func _on_fs_button_button_down() -> void:
	%OsuHitSound.play()
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

func fullscreen_changed():
	if Global.settingsData.fullscreen == true:
		fs_button.text = "OFF"
	else:
		fs_button.text = "ON"


func _on_music_changed(value: float) -> void:
	_set_bus_volume("Music", value)
	_update_label(music_slider, music_label)
	%OsuHitSound.play()


func _on_master_changed(value: float) -> void:
	_set_bus_volume("Master", value)
	_update_label(master_slider, master_label)
	%OsuHitSound.play()


func _on_effects_changed(value: float) -> void:
	_set_bus_volume("Effect", value)
	_update_label(effects_slider, effects_label)
	%OsuHitSound.play()
	

func _set_bus_volume(bus_name: String, value: float) -> void:
	_apply_bus_volume(bus_name, value)
	save_volume()

# Just pushes to AudioServer — no Global writes, no disk saves.
func _apply_bus_volume(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, _slider_to_db(value))
		
func save_volume():
	Global.settingsData.effects_volume = effects_slider.value
	Global.settingsData.master_volume = master_slider.value
	Global.settingsData.music_volume = music_slider.value
	Global.save(Global.settingsData, Global.settingsData.save_file_name)

func _slider_to_db(val: float) -> float:
	return lerp(VOLUME_MIN, VOLUME_MAX, val / 100.0)


func _on_draw_guessed_shape(shape: String) -> void:
	if shape == "circle":
		animation_player.play("Out")


func _on_panel_draw_mouse_entered() -> void:
	drawer.start()


func _on_panel_draw_mouse_exited() -> void:
	drawer.stop()


func _on_bg_button_button_down() -> void:
	if Global.settingsData.video_bg == true:
		Global.settingsData.video_bg = false
		bg_button.text = "OFF"
	else: 
		Global.settingsData.video_bg = true
		bg_button.text = "ON"
	Global.save(Global.settingsData, Global.settingsData.save_file_name)
	%OsuHitSound.play()


func _on_bg_dim_value_changed(value: float) -> void:
	Global.settingsData.bg_visibilty = 100.0 - value
	Global.save(Global.settingsData, Global.settingsData.save_file_name)
	_update_label(bg_dim_slider, dim_percent_label)
	if can_play_hitsound:
		%OsuHitSound.play()
