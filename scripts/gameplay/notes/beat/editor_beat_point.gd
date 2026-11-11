extends Sprite2D

signal clicked(beat_ms: int)
signal drag_started(beat_ms: int)
signal drag_ended(beat_ms: int)
signal hold_started(beat_ms: int)

const SCROLL_FILTER_IDLE_MS := 150

var beat_ms: int = 0
var _restore_filter_at_ms := 0
var _left_press_ms: int = -1
var _hold_ignore := false
var _suppress_click := false
var _is_selected := false

@onready var select: Sprite2D = $Selected
@onready var circle_outline: Sprite2D = $CircleOutline
@onready var button: Button = $Button


func _ready() -> void:
	circle_outline.texture = SkinManager.beat_point_outline
	button.visible = true
	button.self_modulate = Color(1, 1, 1, 0)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_button_pressed)
	button.button_down.connect(
		func() -> void:
			drag_started.emit(beat_ms),
	)
	button.button_up.connect(
		func() -> void:
			drag_ended.emit(beat_ms),
	)


func set_selected(selected: bool) -> void:
	if not is_node_ready():
		await ready
	_is_selected = selected
	select.visible = selected


func _on_button_pressed() -> void:
	if _suppress_click:
		_suppress_click = false
		return
	clicked.emit(beat_ms)


func _process(_delta: float) -> void:
	if (
		button.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and not _hold_ignore
		and Time.get_ticks_msec() >= _restore_filter_at_ms
	):
		button.mouse_filter = Control.MOUSE_FILTER_STOP

	if (
		not _is_selected
		and _left_press_ms >= 0
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		and Time.get_ticks_msec() - _left_press_ms >= 300
	):
		_left_press_ms = -1
		_hold_ignore = true
		_suppress_click = true
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hold_started.emit(beat_ms)

	if _hold_ignore and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_hold_ignore = false
		button.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_button_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null:
		return

	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_suppress_click = false
			_left_press_ms = Time.get_ticks_msec()
		else:
			_left_press_ms = -1
		return

	if not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_restore_filter_at_ms = Time.get_ticks_msec() + SCROLL_FILTER_IDLE_MS
