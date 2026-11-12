class_name EditorInput
extends Control


func _take_data() -> Variant:
	var output_line_edit = get_node_or_null("%output")
	return output_line_edit.text


func _put_data(input: Variant) -> void:
	var output_line_edit = get_node_or_null("%output")
	output_line_edit.text = input
