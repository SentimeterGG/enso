extends VBoxContainer


# Value Tweaker
@onready var scroll_speed: HSlider = $ScrollSpeed/Scroll_Speed

# Value Indicator
@onready var scroll_percent: Label = $ScrollSpeed/Scroll_Speed/ScrollPercent


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	scroll_speed.value = Global.settingsData.scroll_speed
	_update_label_scroll(scroll_speed, scroll_percent)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _update_label_scroll(slider: HSlider, label: Label) -> void:
	label.text = str(roundi(slider.value)) + "px"


func _on_scroll_speed_value_changed(value: float) -> void:
	Global.settingsData.scroll_speed = value
	_update_label_scroll(scroll_speed, scroll_percent)
