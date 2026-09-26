# notification.gd — Bottom toast for import/export + list warnings.
# API: show_message(text, is_error=false, duration=2.6).
# Builds its own Margin/Label if the scene lacks them, so the .tscn stays tiny.
# Overlapping calls invalidate stale hide-timers via a generation counter.
class_name NotificationToast
extends PanelContainer

@onready var _label: Label = $Margin/Label
var _tween: Tween = null
var _gen := 0

const SHOW_SEC := 2.6
const FADE_IN := 0.18
const FADE_OUT := 0.4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false


func show_message(text: String, is_error: bool = false, duration: float = SHOW_SEC) -> void:
	if _label == null:
		return
	_gen += 1
	var my := _gen
	_label.text = text
	_label.add_theme_color_override(
		"font_color", Color(1.0, 0.45, 0.45) if is_error else Color(1, 1, 1)
	)
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.65, FADE_IN)
	_tween.tween_interval(maxf(0.2, duration))
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	await _tween.finished
	if my == _gen and is_instance_valid(self):
		visible = false


func _on_button_pressed() -> void:
	visible = false
	pass  # Replace with function body.
