extends Node2D

const judgement_label := preload("res://scenes/judgement_label.tscn")
var overall_difficulty: float


func _ready() -> void:
	if Global.current_chart != null:
		overall_difficulty = Global.current_chart.get_od()


func get_excellent_window_ms() -> float:
	return 50.0 - 3.0 * overall_difficulty


func get_good_window_ms() -> float:
	if overall_difficulty <= 5.0:
		return 120.0 - 8.0 * overall_difficulty
	return 110.0 - 6.0 * overall_difficulty


func get_bad_window_ms() -> float:
	if overall_difficulty <= 5.0:
		return 135.0 - 8.0 * overall_difficulty
	return 120.0 - 5.0 * overall_difficulty


func _on_beat_column_beat_hit(error_ms: float) -> void:
	var timing_error := absf(error_ms) * 1000.0

	var label: Label = judgement_label.instantiate()
	add_child(label)
	if timing_error <= get_excellent_window_ms():
		label.text = "PERFECT"
	elif timing_error <= get_good_window_ms():
		label.text = "OK"
	elif timing_error <= get_bad_window_ms():
		label.text = "BAD"
	else:
		label.text = "MISS"
	pass  # Replace with function body.
