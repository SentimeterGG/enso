extends Node2D

const judgement_label := preload("res://scenes/judgement_label.tscn")

const COLOR_PERFECT := Color(0.0, 0.906, 0.969, 1.0) # gold
const COLOR_OK := Color(0.35, 0.95, 0.55) # green
const COLOR_BAD := Color(1.0, 0.60, 0.20) # orange
const COLOR_MISS := Color(1.0, 0.30, 0.35) # red
var overall_difficulty: float
var combo: int = 0
@onready var accuracy_manager: Node2D = %accuracy_manager

enum HitAccuracy {
	PERFECT,
	OKAY,
	BAD,
	MISS
}

var perfect: int = 0
var okay: int = 0
var bad: int = 0
var miss: int = 0

@onready var perfect_count: Label = $"../../UI/HitCounter/PerfectCount"
@onready var okay_count: Label = $"../../UI/HitCounter/OkayCount"
@onready var bad_count: Label = $"../../UI/HitCounter/BadCount"
@onready var miss_count: Label = $"../../UI/HitCounter/MissCount"

signal hit_note

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
		label.modulate = COLOR_PERFECT
		accuracy_manager.add_to_avg(100.0)
		add_combo()
		hit_counter(HitAccuracy.PERFECT)
	elif timing_error <= get_good_window_ms():
		label.text = "OK"
		label.modulate = COLOR_OK
		accuracy_manager.add_to_avg(66.67)
		add_combo()
		hit_counter(HitAccuracy.OKAY)
	elif timing_error <= get_bad_window_ms():
		label.text = "BAD"
		label.modulate = COLOR_BAD
		accuracy_manager.add_to_avg(33.34)
		add_combo()
		hit_counter(HitAccuracy.BAD)
	else:
		label.text = "MISS"
		label.modulate = COLOR_MISS
		accuracy_manager.add_to_avg(0.0)
		reset_combo()
		hit_counter(HitAccuracy.MISS)
	pass  # Replace with function body.


func add_combo():
	combo += 1
	%ComboCounter.text = str(combo)+"x"
	%ComboAnims.stop()
	%ComboAnims.play("hit_anim")

func reset_combo():
	combo = 0
	%ComboCounter.text = str(combo)+"x"
	%ComboAnims.stop()
	%ComboAnims.play("miss_anim")
	

func hit_counter(accuracy: HitAccuracy):
	%Mio.note_hit(accuracy)
	if accuracy == HitAccuracy.PERFECT:
		perfect += 1
		perfect_count.text = "PERFECT: " + str(perfect)
	elif accuracy == HitAccuracy.OKAY:
		okay += 1
		okay_count.text = "OKAY: " + str(okay)
	elif accuracy == HitAccuracy.BAD:
		bad += 1
		bad_count.text = "BAD: " + str(bad)
	elif accuracy == HitAccuracy.MISS:
		miss += 1
		miss_count.text = "MISS: " + str(miss)
