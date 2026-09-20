# score_manager.gd (node: accuracy_manager) — Single owner of all gameplay scoring.
#
# Model (multiply): each finished shape scores
#   shape_score = timing_mean(0..1) * draw_acc(0..1)
# `combined_acc` (headline %) is the mean of shape_scores. Rhythm and draw
# means are tracked separately for HUD / results screens. Never negative.
#
# Shape lifecycle (keyed by shape_id = beat.beat_id, no global temp buffer):
#   beat hit/miss   -> register_hit(kind, shape_id)   (lazy-creates pending;
#                    never-drawn shapes auto-finish with draw 0 once all beats judged)
#   draw started    -> begin_shape(shape_id)          (sets active, from beat_column lock)
#   draw released   -> _on_draw_shape_accuracy_ready  (finish active with draw 0..100)
#   draw aborted    -> _on_draw_ended                 (leftovers finish with draw 0)
extends Node2D
class_name ScoreManager

signal score_changed(rhythm_acc: float, draw_acc: float, combined_acc: float, combo: int, counts: Dictionary)

const DRAW_BAD_THRESHOLD := 60.0

var od: float = 0.0

var counts := {
	HitResult.Kind.PERFECT: 0,
	HitResult.Kind.OK: 0,
	HitResult.Kind.BAD: 0,
	HitResult.Kind.MISS: 0,
}
var combo := 0
var max_combo := 0

var rhythm_sum := 0.0
var rhythm_n := 0
var draw_sum := 0.0
var draw_n := 0
var combined_sum := 0.0
var combined_n := 0

# shape_id -> Array[float] of timing weights collected since begin
var _pending: Dictionary = {}
var _active_shape: String = ""
# shape_id -> beats judged so far (hit or miss). Lets never-drawn shapes
# auto-finish once every beat is judged, so all-miss runs still move the score.
var _judged_count: Dictionary = {}
# shape_id -> true once the player started drawing it. Drawn shapes stay
# owned by the draw-ended flow (real accuracy), never by the auto-finish.
var _begun: Dictionary = {}

@onready var avg_accuracy_label: Label = $avg_accuracy
var _combo_label: Label = null
var _combo_anims: AnimationPlayer = null
var _perfect_label: Label = null
var _okay_label: Label = null
var _bad_label: Label = null
var _miss_label: Label = null
@onready var _miss_player: AudioStreamPlayer = $MissSound


func _ready() -> void:
	_resolve_ui()
	refresh_od()
	reset()


func refresh_od() -> void:
	if Global.current_chart != null:
		od = Global.current_chart.get_od()


func reset() -> void:
	for k in counts:
		counts[k] = 0
	combo = 0
	max_combo = 0
	rhythm_sum = 0.0
	rhythm_n = 0
	draw_sum = 0.0
	draw_n = 0
	combined_sum = 0.0
	combined_n = 0
	_pending.clear()
	_judged_count.clear()
	_begun.clear()
	_active_shape = ""
	_update_ui()
	score_changed.emit(rhythm_acc(), draw_acc(), combined_acc(), combo, counts.duplicate())


func begin_shape(shape_id: String) -> void:
	if shape_id.is_empty():
		return
	_active_shape = shape_id
	_begun[shape_id] = true
	if not _pending.has(shape_id):
		_pending[shape_id] = []


func set_active_shape(shape_id: String) -> void:
	begin_shape(shape_id)


func register_hit(kind: int, shape_id: String = "") -> void:
	if not shape_id.is_empty():
		_active_shape = shape_id
		if not _pending.has(shape_id):
			_pending[shape_id] = []
	var target: String = shape_id if not shape_id.is_empty() else _active_shape
	if not target.is_empty():
		if not _pending.has(target):
			_pending[target] = []
		(_pending[target] as Array).append(HitResult.weight_of(kind))
		_judged_count[target] = int(_judged_count.get(target, 0)) + 1

	counts[kind] = int(counts.get(kind, 0)) + 1
	rhythm_sum += HitResult.weight_of(kind)
	rhythm_n += 1
	if kind == HitResult.Kind.MISS:
		# Miss SFX only when breaking a real combo (was above 20 before reset).
		if combo > 20 and _miss_player != null:
			_miss_player.play()
		combo = 0
		_play_combo_anim(false)
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
		_play_combo_anim(true)
	_update_ui()
	score_changed.emit(rhythm_acc(), draw_acc(), combined_acc(), combo, counts.duplicate())
	_maybe_finish_undrawn_shape(target)


func register_miss(shape_id: String = "") -> void:
	register_hit(HitResult.Kind.MISS, shape_id)


func finish_shape(shape_id: String, draw_acc_01: float) -> float:
	var draw := clampf(draw_acc_01, 0.0, 1.0)
	var key: String = shape_id
	if key.is_empty():
		key = _active_shape
	var timing_mean := 0.0
	if not key.is_empty() and _pending.has(key):
		timing_mean = _mean(_pending[key] as Array)
	elif _pending.size() == 1 and key.is_empty():
		# Single open shape with no id tracked — consume it.
		key = str((_pending.keys() as Array)[0])
		timing_mean = _mean(_pending[key] as Array)
	var shape_score := timing_mean * draw
	draw_sum += draw
	draw_n += 1
	combined_sum += shape_score
	combined_n += 1
	if not key.is_empty():
		_pending.erase(key)
		_judged_count.erase(key)
		_begun.erase(key)
	if key == _active_shape:
		_active_shape = ""
	_update_ui()
	score_changed.emit(rhythm_acc(), draw_acc(), combined_acc(), combo, counts.duplicate())
	return shape_score


func cancel_shape(shape_id: String) -> void:
	# Aborted draw: rhythm hits happened but no drawing -> draw counts as 0.
	var key: String = shape_id if not shape_id.is_empty() else _active_shape
	if key.is_empty():
		# No id known: score every leftover pending with 0.
		for k in (_pending.keys() as Array).duplicate():
			finish_shape(str(k), 0.0)
		return
	if _pending.has(key):
		finish_shape(key, 0.0)
	elif key == _active_shape:
		_active_shape = ""


func rhythm_acc() -> float:
	return 100.0 * rhythm_sum / float(maxi(rhythm_n, 1)) if rhythm_n > 0 else 100.0


func draw_acc() -> float:
	return 100.0 * draw_sum / float(maxi(draw_n, 1)) if draw_n > 0 else 100.0


func combined_acc() -> float:
	return 100.0 * combined_sum / float(maxi(combined_n, 1)) if combined_n > 0 else 100.0


# --- Scene signal adapters (wired in game.tscn, do not rename) ---

func _on_draw_shape_accuracy_ready(accuracy: float) -> void:
	# recognizer.compare() returns 0..100
	var key := _active_shape
	if key.is_empty() and _pending.size() == 1:
		key = str((_pending.keys() as Array)[0])
	if key.is_empty() and _pending.is_empty():
		# Ghost tapping: drew with no nearby notes — ignore it entirely.
		# Only notes that pass the receptor unhit can miss (via auto-miss).
		return
	if accuracy < DRAW_BAD_THRESHOLD:
		_spawn_bad_draw()
	finish_shape(key, accuracy / 100.0)


func _on_draw_ended() -> void:
	# Normal release emits shape_accuracy_ready BEFORE draw_ended, so pending
	# is already consumed and this is a no-op. Only aborted draws (null line,
	# no accuracy signal) leave leftovers — score those as draw 0.
	if _pending.is_empty():
		_active_shape = ""
		return
	for k in (_pending.keys() as Array).duplicate():
		finish_shape(str(k), 0.0)
	_active_shape = ""


# --- internals ---

## Floating BAD DRAWING label for sloppy drawings (visual + Mio reaction only;
## scoring is untouched — finish_shape already recorded the draw accuracy).
func _spawn_bad_draw() -> void:
	var spawner := get_node_or_null("judge_spawner")
	if spawner != null and spawner.has_method("spawn_bad_draw"):
		spawner.call("spawn_bad_draw")

## Scores a shape the player never drew: once every beat is judged (hit or
## miss) the shape can never gain draw accuracy, so finish it with draw 0.
## Drawn shapes (_begun) are skipped — the draw-ended flow owns their finish
## with the real recognizer accuracy. Unknown beat counts (total <= 0) fall
## back to the old draw-flow-only behavior.
func _maybe_finish_undrawn_shape(shape_id: String) -> void:
	if shape_id.is_empty():
		return
	if not _pending.has(shape_id):
		return
	if bool(_begun.get(shape_id, false)):
		return
	var total := _shape_total_beats(shape_id)
	if total <= 0:
		return
	if int(_judged_count.get(shape_id, 0)) >= total:
		_judged_count.erase(shape_id)
		finish_shape(shape_id, 0.0)


## Expected beat count for a shape from the chart's runtime index.
func _shape_total_beats(shape_id: String) -> int:
	var chart := Global.current_chart
	if chart != null and chart.has_method("shape_group"):
		var group: Dictionary = chart.shape_group(shape_id)
		return int(group.get("count", 0))
	return 0

func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


func _resolve_ui() -> void:
	var root: Node = owner if owner != null else get_tree().current_scene
	_combo_label = get_node_or_null("%ComboCounter") as Label
	_combo_anims = get_node_or_null("%ComboAnims") as AnimationPlayer
	if root != null:
		if _combo_label == null:
			_combo_label = root.get_node_or_null("UI/ComboCounter") as Label
		if _combo_anims == null:
			_combo_anims = root.get_node_or_null("UI/ComboCounter/ComboAnims") as AnimationPlayer
		_perfect_label = root.get_node_or_null("UI/HitCounter/PerfectCount") as Label
		_okay_label = root.get_node_or_null("UI/HitCounter/OkayCount") as Label
		_bad_label = root.get_node_or_null("UI/HitCounter/BadCount") as Label
		_miss_label = root.get_node_or_null("UI/HitCounter/MissCount") as Label


func _update_ui() -> void:
	if not is_node_ready():
		return
	if avg_accuracy_label != null:
		avg_accuracy_label.text = ("%.2f" % combined_acc()) + "%"
	if _combo_label != null:
		_combo_label.text = str(combo) + "x"
	if _perfect_label != null:
		_perfect_label.text = "PERFECT: " + str(int(counts.get(HitResult.Kind.PERFECT, 0)))
	if _okay_label != null:
		_okay_label.text = "OKAY: " + str(int(counts.get(HitResult.Kind.OK, 0)))
	if _bad_label != null:
		_bad_label.text = "BAD: " + str(int(counts.get(HitResult.Kind.BAD, 0)))
	if _miss_label != null:
		_miss_label.text = "MISS: " + str(int(counts.get(HitResult.Kind.MISS, 0)))


func _play_combo_anim(hit: bool) -> void:
	if _combo_anims == null:
		return
	_combo_anims.stop()
	_combo_anims.play("hit_anim" if hit else "miss_anim")
