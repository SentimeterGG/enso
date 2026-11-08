extends ColorRect

const SCROLL_FILTER_IDLE_MS := 150

var max_width = Transform2D().scaled(Vector2(120.0, 120.0))
var _restore_filter_at_ms := 0

@onready var line2D: Line2D = $Line2D


func init(points: PackedVector2Array):
	line2D.points = points * max_width


func _process(_delta: float) -> void:
	if (
		mouse_filter == Control.MOUSE_FILTER_IGNORE
		and Time.get_ticks_msec() >= _restore_filter_at_ms
	):
		mouse_filter = Control.MOUSE_FILTER_STOP


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_restore_filter_at_ms = Time.get_ticks_msec() + SCROLL_FILTER_IDLE_MS
