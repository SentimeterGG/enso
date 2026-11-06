extends Button


func _on_button_down() -> void:
	%PauseScreen.toggle_pause()
	%PauseScreen.get_viewport().set_input_as_handled()
