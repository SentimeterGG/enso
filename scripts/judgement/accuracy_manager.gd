# accuracy_manager.gd — Score tracker: collects per-shape accuracy values from
# the draw manager, computes the running mean, and displays it as a percentage
# on the avg_accuracy label.
# RETURN: running average accuracy shown on screen
extends Node2D
@onready var avg_accuracy_label: Label = $avg_accuracy
var accuracies := []


func _on_draw_shape_accuracy_ready(accuracy: float) -> void:
	accuracies.append(accuracy)
	var total: float = accuracies.reduce(func(accum, number): return accum + number, 0.0)
	var mean: float = total / accuracies.size() if accuracies.size() > 0 else 0.0
	avg_accuracy_label.text = ("%.2f" % mean) + "%"
