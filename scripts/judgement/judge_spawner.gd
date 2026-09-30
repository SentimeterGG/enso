extends Node2D

const judgement_label := preload("res://scenes/judgement_label.tscn")

@onready var score: ScoreManager = %accuracy_manager
@onready var mio: AnimatedSprite2D = %Mio
@onready var drawing_judge_spawner: Node2D = %drawing_judge_spawner


func _ready() -> void:
	score.get_od()


func _on_beat_column_beat_hit(error_ms: float, _beat_id: String = "") -> void:
	var od := _od()
	var kind := HitResult.classify(error_ms, od)
	if kind != HitResult.Kind.MISS:
		score.combo += 1
		score._play_combo_anim(true)
	else:
		if score.combo > 20:
			%MissSound.stop()
			%MissSound.play()
		score.combo = 0
		score._play_combo_anim(false)
	_spawn_kind(kind)
	score.insert(kind)


func spawn_bad_draw(accuracy: float = 0.0) -> void:
	_spawn_kind(HitResult.Kind.BAD_DRAW, accuracy)
	score.insert(HitResult.Kind.BAD_DRAW)


func _spawn_kind(kind: int, accuracy: float = -1.0) -> void:
	var label: Label = judgement_label.instantiate()
	add_child(label)
	label.text = str(HitResult.LABELS.get(kind, "MISS"))
	label.self_modulate = HitResult.COLORS.get(kind, Color.WHITE)

	if kind == HitResult.Kind.BAD_DRAW:
		label.position = to_local(drawing_judge_spawner.global_position)
		label._set_accuracy_label(accuracy)
	mio.note_hit(kind)


func _od() -> float:
	if score != null:
		return score.od
	if Global.current_chart != null:
		return Global.current_chart.get_od()
	return 0.0
