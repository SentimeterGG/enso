# level_item.gd — Clickable level list row (Panel): selects itself in the parent
# list on left-click release (ignoring drags) and swaps focused/normal stylebox
# via set_selected(). Display is filled via setup(title, subtitle, chart_path)
# so level_list.gd can build rows dynamically from discovered charts.
# RETURN: selection event forwarded to the level list
extends Panel

signal hovered(chart_path: String)

const STYLE_NORMAL: StyleBox = preload("res://resources/theme/level_select_button.tres")
const STYLE_FOCUSED: StyleBox = preload("res://resources/theme/level_select_button_focused.tres")

var chart_path: String = ""
var level_title: String = ""
var level_subtitle: String = ""


func _ready() -> void:
	_apply_text()


func setup(p_title: String, p_subtitle: String, p_chart_path: String) -> void:
	level_title = p_title
	level_subtitle = p_subtitle
	chart_path = p_chart_path
	_apply_text()


func _apply_text() -> void:
	# Labels may not exist yet if setup() runs before _ready(); resolve lazily.
	var title_node: Label = get_node_or_null("MarginContainer/VBoxContainer/Label")
	var subtitle_node: Label = get_node_or_null("MarginContainer/VBoxContainer/Label2")
	if title_node:
		title_node.text = level_title.to_upper() if not level_title.is_empty() else "UNTITLED"
	if subtitle_node:
		subtitle_node.text = level_subtitle.to_upper() if not level_subtitle.is_empty() else ""


func _on_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and not event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var list := get_parent().get_parent()
		if list.has_method("is_dragged") and list.is_dragged():
			return
		if list.has_method("select"):
			list.select(get_index())
		var list_control := list as Control
		if list_control:
			list_control.grab_focus()


func set_selected(selected: bool) -> void:
	add_theme_stylebox_override("panel", STYLE_FOCUSED if selected else STYLE_NORMAL)
	if selected:
		emit_signal("hovered", chart_path)
