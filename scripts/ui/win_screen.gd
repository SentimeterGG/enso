extends Control

const SS_GRADE := preload("res://assets/textures/ui/grade/SSGrade.png")
const S_GRADE := preload("res://assets/textures/ui/grade/SGrade.png")
const A_GRADE := preload("res://assets/textures/ui/grade/AGrade.png")
const B_GRADE := preload("res://assets/textures/ui/grade/BGrade.png")
const C_GRADE := preload("res://assets/textures/ui/grade/CGrade.png")
const D_GRADE := preload("res://assets/textures/ui/grade/DGrade.png")

const GLYPHS := "#%&*+=<>/|?0123456789ABCDEF"
const DECODE_DURATION := 0.45
const SCORE_DECODE_DELAY := 0.25
const SCORE_DECODE_DURATION := 1.5
const BAR_TWEEN_DELAY := 0.2
const BAR_TWEEN_DURATION := 1.1
const GRADE_FADE_DELAY := 0.1
const GRADE_FADE_DURATION := 0.5

var _decode_tweens: Dictionary = { } # Label -> Tween
var _decode_targets: Dictionary = { } # Label -> String

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
@onready var score_val: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/MarginContainer/VBoxContainer/Score

@onready var letter_grade: TextureRect = %LetterGrade
@onready var score_label: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/MarginContainer/VBoxContainer/Score
@onready var score_bar: ProgressBar = $MarginContainer/HBoxContainer/MarginContainer/Details/MarginContainer/VBoxContainer/VBoxContainer/ScoreBar
@onready var pp_value: Label = $MarginContainer/HBoxContainer/MarginContainer/Details/Counters2/PerformancePoints/MarginContainer/VBoxContainer/Value


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


func show_win_screen(
	counts: Dictionary,
	accuracy: float,
	score: int,
	pp: int,
	max_combo: int = 0,
) -> void:
	visible = true

	var perfect: int = counts.get(HitResult.Kind.PERFECT, 0)
	var okay: int = counts.get(HitResult.Kind.OK, 0)
	var bad: int = counts.get(HitResult.Kind.BAD, 0)
	var miss: int = counts.get(HitResult.Kind.MISS, 0)

	# Decode every value, staggering the counters slightly so they cascade.
	if perfect_val != null:
		decode_text(perfect_val, str(perfect), 0.0, DECODE_DURATION, true)
	if ok_val != null:
		decode_text(ok_val, str(okay), 0.05, DECODE_DURATION, true)
	if bad_val != null:
		decode_text(bad_val, str(bad), 0.1, DECODE_DURATION, true)
	if miss_val != null:
		decode_text(miss_val, str(miss), 0.15, DECODE_DURATION, true)

	if accuracy_val != null:
		decode_text(accuracy_val, "%.2f%%" % accuracy, 0.1, 0.7, true)
	if pp_value != null:
		decode_text(pp_value, str(pp), 0.2, 0.7, true)
	if max_combo_val != null:
		decode_text(max_combo_val, str(max_combo), 0.2, 0.7, true)

	# The score gets a noticeably longer decode than everything else.
	if score_val != null:
		decode_text(
			score_val,
			_format_score(score),
			SCORE_DECODE_DELAY,
			SCORE_DECODE_DURATION,
			true,
		)

	if score_bar != null:
		score_bar.min_value = 40.0
		score_bar.max_value = 100.0
		score_bar.value = 40.0
		var bar_target := clampf(accuracy, 40.0, 100.0)
		var bar_tween := create_tween()
		bar_tween.tween_interval(BAR_TWEEN_DELAY)
		bar_tween.tween_property(score_bar, "value", bar_target, BAR_TWEEN_DURATION).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_OUT)

	if letter_grade != null:
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

	# Wait for the longest animation (the score decode), then fade the grade out.
	var longest := maxf(
		maxf(SCORE_DECODE_DELAY + SCORE_DECODE_DURATION, BAR_TWEEN_DELAY + BAR_TWEEN_DURATION),
		0.4,
	)
	await get_tree().create_timer(longest + GRADE_FADE_DELAY).timeout
	if not is_inside_tree():
		return


func _set_decoded(t: float, label: Label, target: String, digits_only: bool) -> void:
	label.text = _scramble(target, t, digits_only)


func _format_score(value: int) -> String:
	# Formats 1000000 as "1.000.000".
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if value < 0 else "") + out


func _scramble(target: String, t: float, digits_only: bool) -> String:
	if t >= 1.0:
		return target
	var revealed := int(t * target.length())
	var out := ""
	for i in target.length():
		var ch := target[i]
		if i < revealed or ch == " " or (digits_only and not ch.is_valid_int()):
			out += ch
		elif digits_only:
			out += str(randi() % 10)
		else:
			out += GLYPHS[randi() % GLYPHS.length()]
	return out



func decode_text(
	label: Label,
	target: String,
	delay: float = 0.0,
	duration: float = 0.48,
	digits_only: bool = false,
) -> void:
	if _decode_targets.get(label, null) == target:
		return
	_decode_targets[label] = target

	var old: Tween = _decode_tweens.get(label, null)
	if old != null and old.is_valid():
		old.kill()

	if target.is_empty():
		label.text = ""
		return

	var tw := create_tween()
	_decode_tweens[label] = tw
	tw.tween_interval(delay)
	tw.tween_method(_set_decoded.bind(label, target, digits_only), 0.0, 1.0, duration)
