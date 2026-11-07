extends VBoxContainer

@export var tweaker_script: Tweaker

# Value Tweaker
@onready var master_slider: HSlider = $MasterVolume/Master
@onready var music_slider: HSlider = $MusicVolume/Music
@onready var effects_slider: HSlider = $EffectsVolume/Effects

# Value Indicator
@onready var master_percent: Label = $MasterVolume/Master/VolumePercent
@onready var music_percent: Label = $MusicVolume/Music/VolumePercent
@onready var effects_percent: Label = $EffectsVolume/Effects/VolumePercent


const VOLUME_STEP := 5.0
const VOLUME_MIN := -60.0
const VOLUME_MAX := 0.0


func _ready() -> void:
	grab_volume_config()
	_sync_sliders_to_audio()

func _on_master_changed(value: float) -> void:
	_set_bus_volume("Master", value)
	tweaker_script._update_label(master_slider, master_percent)
	%HitSound.play()

func _on_music_changed(value: float) -> void:
	_set_bus_volume("Music", value)
	tweaker_script._update_label(music_slider, music_percent)
	%HitSound.play()


func _on_effects_changed(value: float) -> void:
	_set_bus_volume("Effect", value)
	tweaker_script._update_label(effects_slider, effects_percent)
	%HitSound.play()

func _sync_sliders_to_audio() -> void:
	music_slider.set_value_no_signal(_get_bus_slider_value("Music"))
	master_slider.set_value_no_signal(_get_bus_slider_value("Master"))
	effects_slider.set_value_no_signal(_get_bus_slider_value("Effect"))
	tweaker_script._update_label(music_slider, music_percent)
	tweaker_script._update_label(master_slider, master_percent)
	tweaker_script._update_label(effects_slider, effects_percent)

func _get_bus_slider_value(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return _db_to_slider(AudioServer.get_bus_volume_db(idx))
	return 100.0

func _db_to_slider(db: float) -> float:
	return (db - VOLUME_MIN) / (VOLUME_MAX - VOLUME_MIN) * 100.0

func _slider_to_db(val: float) -> float:
	return lerp(VOLUME_MIN, VOLUME_MAX, val / 100.0)

func _set_bus_volume(bus_name: String, value: float) -> void:
	_apply_bus_volume(bus_name, value)
	save_volume()

func _apply_bus_volume(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, _slider_to_db(value))

func save_volume():
	Global.settingsData.effects_volume = effects_slider.value
	Global.settingsData.master_volume = master_slider.value
	Global.settingsData.music_volume = music_slider.value
	Global.save(Global.settingsData, Global.settingsData.save_file_name)

func grab_volume_config():
	_apply_bus_volume("Effect", Global.settingsData.effects_volume)
	tweaker_script._update_label(effects_slider, effects_percent)
	_apply_bus_volume("Master", Global.settingsData.master_volume)
	tweaker_script._update_label(master_slider, master_percent)
	_apply_bus_volume("Music", Global.settingsData.music_volume)
	tweaker_script._update_label(music_slider, music_percent)
