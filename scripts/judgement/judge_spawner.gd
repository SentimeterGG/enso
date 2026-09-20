# judge_spawner.gd — Thin classifier + view: turns beat timing errors into
# HitResult kinds, spawns the floating judgement label, plays the Mio
# reaction, and delegates ALL scoring (counts/combo/accuracy) to ScoreManager.
extends Node2D

const judgement_label := preload("res://scenes/judgement_label.tscn")

@onready var score: ScoreManager = %accuracy_manager
@onready var mio: AnimatedSprite2D = %Mio


func _ready() -> void:
	if score != null:
		score.refresh_od()


func _on_beat_column_beat_hit(error_ms: float, beat_id: String = "") -> void:
	var od := _od()
	var kind := HitResult.classify(error_ms, od)

	_spawn_kind(kind)

	if score != null:
		score.register_hit(kind, beat_id)


## Draw judgement: call when shape drawing accuracy falls below threshold.
func spawn_bad_draw() -> void:
	_spawn_kind(HitResult.Kind.BAD_DRAW)


func _spawn_kind(kind: int) -> void:
	var label: Label = judgement_label.instantiate()
	add_child(label)
	label.text = str(HitResult.LABELS.get(kind, "MISS"))
	label.modulate = HitResult.COLORS.get(kind, Color.WHITE)

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
