extends Control

@onready var level_creator_group: Control = %LevelCreator
@onready var mapping_button: Button = %MappingButton
@onready var metadata_button: Button = %MetadataButton

var viewport_size: Vector2
var viewport_width: float

var _slide_tween: Tween
const SLIDE_DURATION := 0.35


func _ready() -> void:
	viewport_size = get_viewport_rect().size
	viewport_width = viewport_size.x


func _on_mapping_pressed() -> void:
	mapping_button.disabled = true
	metadata_button.disabled = false
	_slide_to(-viewport_width)


func _on_metadata_pressed() -> void:
	mapping_button.disabled = false
	metadata_button.disabled = true
	_slide_to(0.0)


func _slide_to(target_x: float) -> void:
	if _slide_tween:
		_slide_tween.kill()

	_slide_tween = create_tween()
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(level_creator_group, "position:x", target_x, SLIDE_DURATION)


func _on_import_file_pressed() -> void:
	pass # Replace with function body.


func _on_import_popup_file_selected(path: String) -> void:
	pass # Replace with function body.


func _on_export_button_pressed() -> void:
	pass # Replace with function body.
