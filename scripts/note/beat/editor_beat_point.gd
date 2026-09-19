extends Sprite2D

## Emitted when the marker's Button is pressed. mapping.gd connects this to
## select/unselect the beat (Shift held = toggle for multi-select).
signal clicked(beat_ms: int)

## Beat time in ms this marker represents. Set by mapping.gd on spawn.
var beat_ms: int = 0

@onready var select: Sprite2D = $Selected
@onready var button: Button = $Button


func _ready() -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_button_pressed)


func set_selected(selected: bool) -> void:
	if not is_node_ready():
		await ready
	select.visible = selected


func _on_button_pressed() -> void:
	clicked.emit(beat_ms)
