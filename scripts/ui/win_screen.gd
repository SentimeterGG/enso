extends Control

const SS_GRADE := preload("res://assets/textures/ui/grade/SSGrade.png")
const S_GRADE := preload("res://assets/textures/ui/grade/SGrade.png")
const A_GRADE := preload("res://assets/textures/ui/grade/AGrade.png")
const B_GRADE := preload("res://assets/textures/ui/grade/BGrade.png")
const C_GRADE := preload("res://assets/textures/ui/grade/CGrade.png")
const D_GRADE := preload("res://assets/textures/ui/grade/DGrade.png")

@onready var title_song: Label = %TitleSong
@onready var source_value: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Profile/ProfileDetails/SourceContainer/SourceValue
@onready var mapper_value: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Profile/ProfileDetails/MapperContainer/MapperValue
@onready var song_banner: TextureRect = $MarginContainer/HBoxContainer/MarginContainer/Details/Profile/SongBanner

@onready var perfect_val: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Counters/Perfect/MarginContainer/VBoxContainer/Value
@onready var ok_val: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Counters/OK/MarginContainer/VBoxContainer/Value
@onready var bad_val: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Counters/Bad/MarginContainer/VBoxContainer/Value
@onready var miss_val: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Counters/Miss/MarginContainer/VBoxContainer/Value

@onready var accuracy_val: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Counters2/Accuracy/MarginContainer/VBoxContainer/Value
@onready var max_combo_val: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Counters2/MaxCombo/MarginContainer/VBoxContainer/Value

@onready var letter_grade: TextureRect = %LetterGrade
@onready var score_label: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/MarginContainer/VBoxContainer/Score
@onready var score_bar: ProgressBar = $MarginContainer/HBoxContainer/MarginContainer/Details/MarginContainer/VBoxContainer/VBoxContainer/ScoreBar
@onready var pp_panel: Panel = $MarginContainer/HBoxContainer/MarginContainer/Details/Counters2/PerformancePoints


func _ready() -> void:
	if Global.current_chart == null:
		return
	visible = false
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)

	title_song.text = Global.current_chart.get_song_title()
	source_value.text = Global.current_chart.get_song_source()
	mapper_value.text = Global.current_chart.get_mapper()

	var bg_path := Global.current_chart.get_bg()
	if bg_path != "":
		var tex = Global.load_safely(bg_path)
		if tex is Texture2D:
			song_banner.texture = tex


func _on_button_pressed() -> void:
	get_tree().reload_current_scene()


func _on_back_to_menu_pressed() -> void:
	%LoadToLevel.load_scene()


func show_win_screen(counts: Dictionary, accuracy: float, max_combo: int = 0) -> void:
	visible = true

	var perfect: int = counts.get(HitResult.Kind.PERFECT, 0)
	var okay: int = counts.get(HitResult.Kind.OK, 0)
	var bad: int = counts.get(HitResult.Kind.BAD, 0)
	var miss: int = counts.get(HitResult.Kind.MISS, 0)

	if perfect_val != null:
		perfect_val.text = str(perfect)
	if ok_val != null:
		ok_val.text = str(okay)
	if bad_val != null:
		bad_val.text = str(bad)
	if miss_val != null:
		miss_val.text = str(miss)

	if accuracy_val != null:
		accuracy_val.text = ("%.2f" % accuracy) + "%"

	if max_combo_val != null:
		max_combo_val.text = str(max_combo)

	if accuracy >= 100.0 and miss == 0:
		letter_grade.texture = SS_GRADE
	elif accuracy >= 95.0:
		letter_grade.texture = S_GRADE
	elif accuracy >= 90.0:
		letter_grade.texture = A_GRADE
	elif accuracy >= 80.0:
		letter_grade.texture = B_GRADE
	elif accuracy >= 70.0:
		letter_grade.texture = C_GRADE
	else:
		letter_grade.texture = D_GRADE

	var scale_tween := create_tween()
	scale_tween.set_parallel(true)
	scale_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	scale_tween.tween_property(self, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	await scale_tween.finished
