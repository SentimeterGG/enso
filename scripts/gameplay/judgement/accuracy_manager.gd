extends Node2D
class_name ScoreManager

signal hit_applied(kind: int)

const DRAW_BAD_ACCURACY := 65.0
const PP_REFERENCE_NOTES := 300.0
const PP_BASE := 20.0

var counts := {
	HitResult.Kind.PERFECT: 0,
	HitResult.Kind.OK: 0,
	HitResult.Kind.BAD: 0,
	HitResult.Kind.MISS: 0,
}
var BASE_SCORES := {
	HitResult.Kind.PERFECT: 300,
	HitResult.Kind.OK: 100,
	HitResult.Kind.BAD: 50,
	HitResult.Kind.MISS: 0,
}
var od: float = 0.0
var combo := 0
var max_combo := 0
var avg_accuracy = 0.0

@onready var avg_accuracy_label = %avg_accuracy
@onready var _combo_label = %ComboCounter
@onready var _combo_anims = %ComboAnims
@onready var _perfect_label = %PerfectCount
@onready var _okay_label = %OkayCount
@onready var _bad_label = %BadCount
@onready var _miss_label = %MissCount
@onready var _judge_spawner = %judge_spawner


func reset() -> void:
	for kind in counts:
		counts[kind] = 0
	combo = 0
	avg_accuracy = 100.0
	_update_ui()


func get_od():
	if Global.current_chart != null:
		od = Global.current_chart.get_od()


func insert(kind: int):
	counts[kind] = int(counts.get(kind, 0)) + 1
	var total := 0
	var weighted := 0.0
	for k in counts:
		var c := int(counts[k])
		total += c
		weighted += HitResult.weight_of(k) * c
	avg_accuracy = 100.0 * weighted / float(maxi(total, 1)) if total > 0 else 0.0
	_update_ui()
	hit_applied.emit(kind)


func get_counts() -> Dictionary:
	return counts.duplicate()


func calculate_score(accuracy: float, p_combo: int, p_max_combo: int) -> int:
	var accuracy_score := (accuracy / 100.0) * 0.3
	var combo_score := 0.0
	if p_max_combo > 0:
		combo_score = clampf(float(p_combo) / float(p_max_combo), 0.0, 1.0) * 0.7
	return int(1_000_000 * (accuracy_score + combo_score))


func calculate_pp(accuracy: float, score: int, p_max_combo: int) -> int:
	if Global.current_chart == null:
		return 0

	var notes := maxi(Global.current_chart.note_count(), 1)
	var p_od := GestureRecognizer.od_from_chart(Global.current_chart) # 1.0 .. 10.0

	var acc := clampf(accuracy / 100.0, 0.0, 1.0)
	var score_ratio := clampf(float(score) / 1_000_000.0, 0.0, 1.0)
	var combo_ratio := clampf(float(p_max_combo) / float(notes), 0.0, 1.0)
	var length := sqrt(float(notes) / PP_REFERENCE_NOTES)

	var performance := score_ratio * (0.8 + 0.2 * combo_ratio)
	return int(round(PP_BASE * p_od * length * pow(acc, 2.0) * performance))


func _update_ui() -> void:
	avg_accuracy_label.text = ("%.2f" % avg_accuracy) + "%"
	_combo_label.text = str(combo) + "x"
	_perfect_label.text = "PERFECT: " + str(int(counts.get(HitResult.Kind.PERFECT, 0)))
	_okay_label.text = "OK: " + str(int(counts.get(HitResult.Kind.OK, 0)))
	_bad_label.text = "BAD: " + str(int(counts.get(HitResult.Kind.BAD, 0)))
	_miss_label.text = "MISS: " + str(int(counts.get(HitResult.Kind.MISS, 0)))


func _play_combo_anim(hit: bool) -> void:
	_combo_anims.stop()
	_combo_anims.play("hit_anim" if hit else "miss_anim")


func _on_draw_shape_accuracy_ready(accuracy: float) -> void:
	var receptor := get_node_or_null("%beat_receptor")
	if receptor == null or str(receptor.get("last_beat_id")).is_empty():
		return
	if accuracy < DRAW_BAD_ACCURACY:
		_judge_spawner.spawn_bad_draw()
