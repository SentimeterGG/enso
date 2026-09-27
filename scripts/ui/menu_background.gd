extends TextureRect

@export var parallax_strength: float = 20.0
@export var smoothing_speed: float = 5.0
@export var zoom_factor: float = 1.1  # 1.1 = 10% oversized, gives you overflow margin

var origin_position: Vector2
var max_offset: Vector2

func _ready() -> void:
	# Center the pivot so scaling expands evenly in all directions
	pivot_offset = size / 2.0
	scale = Vector2(zoom_factor, zoom_factor)
	origin_position = position
	_calculate_max_offset()

func _calculate_max_offset() -> void:
	# How much overflow the scale creates, in local (unscaled) pixels
	var overflow := size * (zoom_factor - 1.0) / 2.0
	max_offset = overflow

func _physics_process(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	var center := viewport_size / 2.0

	var normalized := (mouse_pos - center) / center
	normalized = normalized.clamp(Vector2(-1, -1), Vector2(1, 1))

	var target_offset := normalized * parallax_strength
	target_offset = target_offset.clamp(-max_offset, max_offset)

	var target_position := origin_position + target_offset
	position = lerp(position, target_position, clamp(smoothing_speed * delta, 0.0, 1.0))
