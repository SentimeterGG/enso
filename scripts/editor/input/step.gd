extends EditorInput


func _take_data() -> String:
	return str(%output.value)


func _put_data(input: Variant) -> void:
	%output.value = input.to_int()
