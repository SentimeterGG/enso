# score_manager.gd (node: accuracy_manager) — Single owner of all gameplay scoring.
#
# Model (multiply): each finished shape scores
#   shape_score = timing_mean(0..1) * draw_acc(0..1)
# `combined_acc` (headline %) is the mean of shape_scores. Rhythm and draw
# means are tracked separately for HUD / results screens. Never negative.
#
# Draw accuracy is judged against the 65% threshold: a drawing that reaches
# it is counted as a fully accurate drawing (100% draw), anything below is
# counted as 0%.
#
# Shape lifecycle (keyed by shape_id = beat.beat_id, no global temp buffer):
#   beat hit/miss   -> register_hit(kind, shape_id)   (lazy-creates pending;
#                    never-drawn shapes auto-finish with draw 0 once all beats judged)
#   draw started    -> begin_shape(shape_id)          (sets active, from beat_column lock)
#   draw released   -> _on_draw_shape_accuracy_ready  (finish active with draw 0..100)
#   draw aborted    -> _on_draw_ended                 (leftovers finish with draw 0)
extends Node2D
class_name ScoreManager
## Emitted once per judgement (fed by the health bar).
signal hit_applied(kind: int)
@onready var avg_accuracy_label = %avg_accuracy
@onready var _combo_label = %ComboCounter
@onready var _combo_anims = %ComboAnims
@onready var _perfect_label = %PerfectCount
@onready var _okay_label = %OkayCount
@onready var _bad_label = %BadCount
@onready var _miss_label = %MissCount
@onready var _judge_spawner = %judge_spawner
const DRAW_BAD_ACCURACY := 65.0
var od: float = 0.0
var counts := {
	HitResult.Kind.PERFECT: 0,
	HitResult.Kind.OK: 0,
	HitResult.Kind.BAD: 0,
	HitResult.Kind.MISS: 0,
}
var combo := 0
var avg_accuracy = 0.0


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


func _get_counts() -> Dictionary:
	return counts.duplicate()


func _on_draw_shape_accuracy_ready(accuracy: float) -> void:
	var receptor := get_node_or_null("%beat_receptor")
	if receptor == null or str(receptor.get("last_beat_id")).is_empty():
		return
	if accuracy < DRAW_BAD_ACCURACY:
		_judge_spawner.spawn_bad_draw()
