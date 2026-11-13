extends Button

@export var custom_tooltip_text: String = ""


func _on_mouse_exited() -> void:
	if custom_tooltip_text != "":
		Tooltip.hide_tooltip()
	pass # Replace with function body.


func _on_mouse_entered() -> void:
	if custom_tooltip_text != "":
		Tooltip.show_tooltip(custom_tooltip_text)
	pass # Replace with function body.
