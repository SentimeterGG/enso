extends ColorRect

signal hold_started()

const SCROLL_FILTER_IDLE_MS := 150

var max_width = Transform2D().scaled(Vector2(120.0, 120.0))
var _restore_filter_at_ms := 0
var _left_press_ms: int = -1
var _hold_ignore := false
var _is_selected := false

@onready var line2D: Line2D = $Line2D


func init(points: PackedVector2Array):
	line2D.points = points * max_width


func set_selected(selected: bool) -> void:
	_is_selected = selected


func _process(_delta: float) -> void:
	if (
		mouse_filter == Control.MOUSE_FILTER_IGNORE and not _hold_ignore
		and Time.get_ticks_msec() >= _restore_filter_at_ms
	):
		mouse_filter = Control.MOUSE_FILTER_STOP

	if (
		not _is_selected and _left_press_ms >= 0
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		and Time.get_ticks_msec() - _left_press_ms >= 150
	):
		_left_press_ms = -1
		_hold_ignore = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		hold_started.emit()

	if _hold_ignore and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_hold_ignore = false
		mouse_filter = Control.MOUSE_FILTER_STOP


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null:
		return

	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_left_press_ms = Time.get_ticks_msec()
		else:
			_left_press_ms = -1
		return

	if not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_restore_filter_at_ms = Time.get_ticks_msec() + SCROLL_FILTER_IDLE_MS
