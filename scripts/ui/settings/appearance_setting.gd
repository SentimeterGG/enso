extends VBoxContainer

@export var tweaker_script: Tweaker

# Value Tweaker
@onready var bg_button: Button = $VideoBackground/BGButton
@onready var bg_dim: HSlider = $BackgroundDim/BG_Dim

# Value Indicator
@onready var dim_percent: Label = $BackgroundDim/BG_Dim/DimPercent

var can_play_hitsound: bool = false


func _ready() -> void:
	bg_dim.value = 100.0 - Global.settingsData.bg_visibilty
	tweaker_script._update_label(bg_dim, dim_percent)
	can_play_hitsound = true
	if Global.settingsData.video_bg == true:
		bg_button.text = "ON"
	else:
		bg_button.text = "OFF"

func _on_bg_button_button_down() -> void:
	if Global.settingsData.video_bg == true:
		Global.settingsData.video_bg = false
		bg_button.text = "OFF"
	else:
		Global.settingsData.video_bg = true
		bg_button.text = "ON"
	Global.save(Global.settingsData, Global.settingsData.save_file_name)
	%HitSound.play()

func _on_bg_dim_value_changed(value: float) -> void:
	Global.settingsData.bg_visibilty = 100.0 - value
	Global.save(Global.settingsData, Global.settingsData.save_file_name)
	tweaker_script._update_label(bg_dim, dim_percent)
	if can_play_hitsound:
		%HitSound.play()
