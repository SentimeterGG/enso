extends Control

const SS_GRADE := preload("res://assets/sprites/UI/grade/SSGrade.png")
const S_GRADE := preload("res://assets/sprites/UI/grade/SGrade.png")
const A_GRADE := preload("res://assets/sprites/UI/grade/AGrade.png")
const B_GRADE := preload("res://assets/sprites/UI/grade/BGrade.png")
const C_GRADE := preload("res://assets/sprites/UI/grade/CGrade.png")
const D_GRADE := preload("res://assets/sprites/UI/grade/DGrade.png")


func _ready():
	if Global.current_chart == null:
		return
	visible = false
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	%TitleSong.text = Global.current_chart.get_song_title()
	%SourceSong.text = Global.current_chart.get_song_source()


func _on_button_pressed() -> void:
	get_tree().reload_current_scene()
	pass  # Replace with function body.


func _on_back_to_menu_pressed() -> void:
	%LoadToLevel.load_scene()
	pass  # Replace with function body.


func _show(counts: Dictionary, accuracy: float) -> void:
	visible = true
	var perfect: int = counts.get(HitResult.Kind.PERFECT, 0)
	var okay: int = counts.get(HitResult.Kind.OK, 0)
	var bad: int = counts.get(HitResult.Kind.BAD, 0)
	var miss: int = counts.get(HitResult.Kind.MISS, 0)

	%PerfectCount.text = str(perfect)
	%GoodCount.text = str(okay)
	%BadCount.text = str(bad)
	%MissCount.text = str(miss)
	%AccuracyLabel.text = "ACCURACY: " + ("%.2f" % accuracy) + "%"

	if accuracy >= 90.0 and miss == 0:
		%LetterGrade.texture = SS_GRADE
	elif accuracy >= 80.0:
		%LetterGrade.texture = S_GRADE
	elif accuracy >= 70.0:
		%LetterGrade.texture = A_GRADE
	elif accuracy >= 55.0:
		%LetterGrade.texture = B_GRADE
	elif accuracy >= 40.0:
		%LetterGrade.texture = C_GRADE
	else:
		%LetterGrade.texture = D_GRADE
	var scale_tween := create_tween()
	scale_tween.set_parallel(true)
	(
		scale_tween
		. tween_property(self, "scale", Vector2(1.0, 1.0), 0.4)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	scale_tween.tween_property(self, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	await scale_tween.finished
	%LetterGradeGhostEffect.texture = %LetterGrade.texture
	%LetterGradeAnim.play("show")
