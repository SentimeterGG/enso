extends Label

const LIFT := 60.0
const DURATION := 0.8
@onready var accuracy_label : Label = $Accuracy


func _ready() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - LIFT, DURATION).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, DURATION).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
	accuracy_label.visible = false

func _set_accuracy_label(accuracy : float) -> void:
	accuracy_label.visible = true
	accuracy_label.text = "%.2f%%" % accuracy
