@tool
extends TextureRect


signal generation_started
signal generation_progress(normalized_progress)
signal generation_completed

var voice_preview_generator
var stream : AudioStreamWAV = null
var stream_length := 0.0

@export var px_per_sec: float = 100.0:
	set(new_value):
		px_per_sec = maxf(1.0, new_value)
		if is_node_ready():
			_update_preview()

@export_file("*.wav") var stream_path: String:
	set(new_path):
		stream_path = new_path
		_update_preview()


func _ready():
	voice_preview_generator = preload("res://addons/audio_preview/voice_preview_generator.tscn").instantiate()
	add_child(voice_preview_generator)
	voice_preview_generator.generation_progress.connect(_on_generation_progress)
	voice_preview_generator.texture_ready.connect(_on_texture_ready)
	
	
	_update_preview()


func _update_preview():
	if not voice_preview_generator:
		return
	
	if stream_path in ["", "res://", "user://"]:
		texture = null
		return

	stream = load(stream_path)
	stream_length = stream.get_length() if stream else 0.0
	_apply_width()
	voice_preview_generator.generate_preview(stream, _target_width())
	emit_signal("generation_started")


func _target_width() -> int:
	return maxi(1, int(round(stream_length * px_per_sec)))


func _apply_width() -> void:
	var target := _target_width()
	custom_minimum_size.x = float(target)
	size.x = float(target)
	# Let the texture fill the rect even while (re)generating at a new width.
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE


## Cheap zoom for fast scroll-wheel scaling: resizes the rect to display
## `new_px_per_sec` by stretching the CURRENT texture instead of regenerating
## it (no per-column decode, no image alloc — just a layout change).
## Use the px_per_sec setter when full-resolution re-render is actually needed.
func set_display_zoom(new_px_per_sec: float) -> void:
	if stream_length <= 0.0:
		return
	var target := maxi(1, int(round(stream_length * maxf(1.0, new_px_per_sec))))
	custom_minimum_size.x = float(target)
	size.x = float(target)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE

func _on_generation_progress(normalized_progress: float):
	emit_signal("generation_progress", normalized_progress)

func _on_texture_ready(image_texture):
	texture = image_texture
	_apply_width()
	emit_signal("generation_completed")





