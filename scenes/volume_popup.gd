extends CanvasLayer

@onready var volume_popup = $volume_popup
var test = false

var can_popup: bool = true:
	set = change_popup


func change_popup(pop_up_value: bool):
	volume_popup.can_popup = pop_up_value

func hide_pop_up():
	volume_popup._hide_popup()
