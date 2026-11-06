extends Sprite2D

signal clicked(beat_ms: int)
signal drag_started(beat_ms: int)
signal drag_ended(beat_ms: int)

var beat_ms: int = 0

@onready var select: Sprite2D = $Selected
@onready var circle_outline: Sprite2D = $CircleOutline
@onready var button: Button = $Button


func _ready() -> void:
	circle_outline.texture = SkinManager.beat_point_outline
	# Hidden Controls are skipped by GUI picking. Keep the hitbox visible but
	# fully transparent so clicks reach this marker's Button.
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
