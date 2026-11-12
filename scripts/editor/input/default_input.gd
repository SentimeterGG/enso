extends EditorInput
signal text_changed(new_text: String)


func _on_output_text_changed(new_text: String) -> void:
	text_changed.emit(new_text)
