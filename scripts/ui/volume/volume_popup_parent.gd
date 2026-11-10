extends CanvasLayer

@onready var volume_popup = $volume_popup

var can_popup: bool = true


func hide_pop_up():
	volume_popup._hide_popup()
