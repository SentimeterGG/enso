extends TextureRect

@export var parallax_strength: float = 20.0
@export var smoothing_speed: float = 5.0
@export var zoom_factor: float = 1.1  # 1.1 = 10% oversized, gives you overflow margin
@export var fade_duration: float = 0.35
@export var parallax_toggle_duration: float = 0.4

var origin_position: Vector2
var max_offset: Vector2
var _base_alpha: float = 1.0
var _fade_tween: Tween = null
var parallax_enabled: bool = true
var _parallax_tween: Tween = null


func _ready() -> void:
	# Center the pivot so scaling expands evenly in all directions
	pivot_offset = size / 2.0
	scale = Vector2(zoom_factor, zoom_factor)
	origin_position = position
	_base_alpha = modulate.a
	_calculate_max_offset()

func disable_parallax() -> void:
	if not parallax_enabled and (_parallax_tween == null or not _parallax_tween.is_valid()):
		return
	parallax_enabled = false
	_kill_parallax_tween()
	_parallax_tween = create_tween().set_parallel(true)
	(
		_parallax_tween
		. tween_property(self, "position", origin_position, parallax_toggle_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_parallax_tween
		. tween_property(self, "scale", Vector2.ONE, parallax_toggle_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


func enable_parallax() -> void:
	if parallax_enabled and (_parallax_tween == null or not _parallax_tween.is_valid()):
		return
	_kill_parallax_tween()
	# Tween first, then hand control back to _physics_process so they don't fight.
	_parallax_tween = create_tween().set_parallel(true)
	(
		_parallax_tween
		. tween_property(self, "scale", Vector2(zoom_factor, zoom_factor), parallax_toggle_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_parallax_tween
		. tween_property(self, "position", origin_position, parallax_toggle_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_parallax_tween.chain().tween_callback(_on_parallax_tween_finished)


func _on_parallax_tween_finished() -> void:
	parallax_enabled = true


func _kill_parallax_tween() -> void:
	if _parallax_tween != null and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = null
	
func _calculate_max_offset() -> void:
	# How much overflow the scale creates, in local (unscaled) pixels
	var overflow := size * (zoom_factor - 1.0) / 2.0
	max_offset = overflow


func _physics_process(delta: float) -> void:
	if not parallax_enabled:
		return
	if _parallax_tween != null and _parallax_tween.is_valid():
		return
	var viewport_size := get_viewport_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	var center := viewport_size / 2.0

	var normalized := (mouse_pos - center) / center
	normalized = normalized.clamp(Vector2(-1, -1), Vector2(1, 1))

	var target_offset := normalized * parallax_strength
	target_offset = target_offset.clamp(-max_offset, max_offset)

	var target_position := origin_position + target_offset
	position = lerp(position, target_position, clamp(smoothing_speed * delta, 0.0, 1.0))


func change(path: Variant = null) -> void:
	if path == null or (path is String and (path as String).is_empty()) or (path is StringName and String(path).is_empty()):
		clear_background()
		return
	var path_str := String(path)
	var new_tex := Global.load_safely(path_str) as Texture2D if path_str else null
	if new_tex == null:
		push_error("menu_background.change: failed to load '%s'" % path_str)
		return
	if new_tex == texture:
		# Coming back from a cleared (faded-out) state: fade back in.
		if modulate.a < _base_alpha - 0.01:
			if _fade_tween != null and _fade_tween.is_valid():
				_fade_tween.kill()
			_fade_tween = create_tween()
			(
				_fade_tween
				. tween_property(self, "modulate:a", _base_alpha, fade_duration)
				. set_trans(Tween.TRANS_QUAD)
				. set_ease(Tween.EASE_OUT)
			)
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	(
		_fade_tween
		. tween_property(self, "modulate:a", 0.0, fade_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_fade_tween.tween_callback(_apply_texture.bind(new_tex))
	(
		_fade_tween
		. tween_property(self, "modulate:a", _base_alpha, fade_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


func set_base_alpha(new: float):
	_base_alpha = clampf(new, 0.0, 1.0)
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	(
		_fade_tween
		. tween_property(self, "modulate:a", _base_alpha, fade_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


func clear_background() -> void:
	if texture == null and modulate.a <= 0.01:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	(
		_fade_tween
		. tween_property(self, "modulate:a", 0.0, fade_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_fade_tween.tween_callback(_apply_texture.bind(null))


func _apply_texture(new_tex: Texture2D) -> void:
	texture = new_tex
