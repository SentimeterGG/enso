extends Sprite2D

## Emitted when the marker's Button is pressed. mapping.gd connects this to
## select/unselect the beat (Shift held = toggle for multi-select).
signal clicked(beat_ms: int)
## Emitted on Button press/release so mapping.gd can drag the beat in time.
## Only the x position changes; y stays fixed.
signal drag_started(beat_ms: int)
signal drag_ended(beat_ms: int)

## Beat time in ms this marker represents. Set by mapping.gd on spawn.
var beat_ms: int = 0

@onready var select: Sprite2D = $Selected
@onready var circle_outline: Sprite2D = $CircleOutline
@onready var button: Button = $Button


func _ready() -> void:
	circle_outline.texture = SkinManager.beat_point_outline
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_button_pressed)
	button.button_down.connect(func() -> void: drag_started.emit(beat_ms))
	button.button_up.connect(func() -> void: drag_ended.emit(beat_ms))


func set_selected(selected: bool) -> void:
	if not is_node_ready():
		await ready
	select.visible = selected


func _on_button_pressed() -> void:
	clicked.emit(beat_ms)
