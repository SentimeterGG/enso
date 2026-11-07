class_name Tweaker extends Node



func _update_label(slider: HSlider, label: Label) -> void:
	label.text = "%d%%" % roundi(slider.value)
