extends EditorInput


func _take_data() -> Variant:
	var out: Array = []
	for child in %output.get_children():
		if child is ColorRect:
			out.append("#" + child.color.to_html(false).to_upper())
	return out


func _add_color_rect(color: Color) -> void:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(150, 150)
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.gui_input.connect(_on_rect_gui_input.bind(rect))
	%output.add_child(rect)


func _on_rect_gui_input(event: InputEvent, rect: ColorRect):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		rect.queue_free()


func _on_add_color_button_pressed() -> void:
	_add_color_rect(%picker.color)
	pass # Replace with function body.


func _parse_color_token(part: String) -> Color:
	var token := part.strip_edges()
	token = token.trim_prefix('"').trim_prefix("'")
	token = token.trim_suffix('"').trim_suffix("'")
	return Color.from_string(token, Color.TRANSPARENT)


func _parse_color_scheme(raw: String) -> Array[Color]:
	var colors: Array[Color] = []
	var cleaned := raw.trim_prefix("[").trim_suffix("]").strip_edges()
	if cleaned.is_empty():
		return colors
	for part in cleaned.split(",", false):
		var color := _parse_color_token(part)
		if color != Color.TRANSPARENT:
			colors.append(color)
	return colors


func _put_data(input: Variant) -> void:
	for child in %output.get_children():
		if child is ColorRect:
			child.queue_free()
	if input.is_empty():
		return
	for color in _parse_color_scheme(input):
		_add_color_rect(color)
