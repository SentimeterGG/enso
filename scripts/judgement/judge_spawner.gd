# judge_spawner.gd — Thin classifier + view: turns beat timing errors into
# HitResult kinds, spawns the floating judgement label, plays the Mio
# reaction, and delegates ALL scoring (counts/combo/accuracy) to ScoreManager.
extends Node2D

const judgement_label := preload("res://scenes/judgement_label.tscn")

@onready var score: ScoreManager = %accuracy_manager
@onready var mio: AnimatedSprite2D = %Mio
@onready var drawing_judge_spawner: Node2D = get_node_or_null("%drawing_judge_spawner")


func _ready() -> void:
	if score != null:
		score.refresh_od()


func _on_beat_column_beat_hit(error_ms: float, beat_id: String = "") -> void:
	var od := _od()
	var kind := HitResult.classify(error_ms, od)

	_spawn_kind(kind)

	if score != null:
		score.register_hit(kind, beat_id)


## Draw judgement: call with the recognizer accuracy (0-100) when shape
## drawing accuracy falls below threshold.
func spawn_bad_draw(accuracy: float = 0.0) -> void:
	_spawn_kind(HitResult.Kind.BAD_DRAW, accuracy)
	score.register_hit(HitResult.Kind.BAD_DRAW, "")


func _spawn_kind(kind: int, accuracy: float = -1.0) -> void:
	var label: Label = judgement_label.instantiate()
	add_child(label)
	label.text = str(HitResult.LABELS.get(kind, "MISS"))
	label.self_modulate = HitResult.COLORS.get(kind, Color.WHITE)
	# BAD DRAWING is a drawing judgement, not a beat judgement: float it at the
	# drawing marker instead of the beat receptor, showing the draw accuracy
	# from accuracy_manager. Falls back to this spawner's own position when
	# the marker node is missing.
	if kind == HitResult.Kind.BAD_DRAW and drawing_judge_spawner != null:
		label.position = to_local(drawing_judge_spawner.global_position)
		label._set_accuracy_label(accuracy)

	if mio != null and mio.has_method("note_hit"):
		mio.note_hit(kind)


func _od() -> float:
	if score != null:
		return score.od
	if Global.current_chart != null:
		return Global.current_chart.get_od()
	return 0.0


# --- Deprecated: timing windows now live in HitResult. Kept so any stray
# --- caller (e.g. old beat_column) keeps working until scenes are re-saved.
func get_excellent_window_ms() -> float:
	return HitResult.excellent_window_ms(_od())


func get_good_window_ms() -> float:
	return HitResult.good_window_ms(_od())


func get_bad_window_ms() -> float:
	return HitResult.bad_window_ms(_od())
