extends Sprite2D

signal clicked(beat_ms: int)
signal drag_started(beat_ms: int)
signal drag_ended(beat_ms: int)

const SCROLL_FILTER_IDLE_MS := 150

var beat_ms: int = 0
var _restore_filter_at_ms := 0

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
	select.visible = selected


func _on_button_pressed() -> void:
	clicked.emit(beat_ms)


func _process(_delta: float) -> void:
	if ( button.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and Time.get_ticks_msec() >= _restore_filter_at_ms
	):
		button.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_button_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_restore_filter_at_ms = Time.get_ticks_msec() + SCROLL_FILTER_IDLE_MS
