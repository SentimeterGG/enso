extends EditorInput
signal browse_pressed

@onready var output = %output


func _on_browse_pressed() -> void:
	browse_pressed.emit()
