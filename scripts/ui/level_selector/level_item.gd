extends Panel

signal hovered(chart_path: String)

const STYLE_NORMAL: StyleBox = preload("res://resources/themes/level_select_button.tres")
const STYLE_FOCUSED: StyleBox = preload("res://resources/themes/level_select_button_focused.tres")
const STYLE_PARENT_FOCUSED: StyleBox = preload(
	"res://resources/themes/level_select_button_focused.tres"
)
const STYLE_VARIANT_NORMAL: StyleBox = preload(
	"res://resources/themes/level_select_button_variant.tres"
)
const STYLE_FOCUSED_PULSE: StyleBox = preload(
	"res://resources/themes/level_select_button_focused_blink.tres"
)
const OD_COLORS := [
	Color(0.29, 0.55, 1.0), # 1  blue
	Color(0.30, 0.85, 0.40), #    green
	Color(1.0, 0.86, 0.25), #    yellow
	Color(1.0, 0.28, 0.28), #    red
	Color(0.69, 0.35, 1.0), # 10 purple
]

var chart_path: String = ""
var level_title: String = ""
var level_subtitle: String = ""
var background: String = ""
var overall_difficulty: int = 0
var variant: bool = false
var data_id = -1

var _pulse_tween: Tween
var _is_selected: bool = false
var _parent_focused: bool = false

@onready var title_node: Label = %TitleChart
@onready var subtitle_node: Label = $MarginContainer/VBoxContainer/Label2
@onready var level_bg: TextureRect = $TextureRect
@onready var outline_node: Panel = $Panel
@onready var anim_player: AnimationPlayer = $level_item_animation
@onready var pip_parent: HBoxContainer = $MarginContainer/VariantDifficulty/MarginContainer/Pipe
@onready var difficulty_label: Label = $MarginContainer/VariantDifficulty/Difficulty
@onready var variant_difficulty: VBoxContainer = %VariantDifficulty
@onready var title_group: VBoxContainer = $MarginContainer/VBoxContainer


func _ready() -> void:
	_apply()


func setup(
	p_id: int,
	p_title: String,
	p_subtitle: String,
	p_chart_path: String,
	p_background: String,
	p_variant: bool = false,
) -> void:
	data_id = p_id
	level_title = p_title
	level_subtitle = p_subtitle
	chart_path = p_chart_path
	variant = p_variant
	if not variant:
		background = p_background
		overall_difficulty = 0
	else:
		overall_difficulty = _read_overall_difficulty(p_chart_path)
	_apply()


func set_parent_focused(focused: bool) -> void:
	if _is_selected or _parent_focused == focused:
		return
	_parent_focused = focused
	outline_node.add_theme_stylebox_override(
		"panel",
		STYLE_PARENT_FOCUSED if focused else STYLE_NORMAL,
	)


func play_pulse() -> void:
	anim_player.stop()
	anim_player.play("pulse")


func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	_apply()
	if _pulse_tween:
		_pulse_tween.kill()

	if not selected:
		outline_node.add_theme_stylebox_override(
			"panel",
			STYLE_PARENT_FOCUSED if _parent_focused else STYLE_NORMAL,
		)
		return

	outline_node.add_theme_stylebox_override("panel", STYLE_FOCUSED_PULSE)
	_pulse_tween = create_tween()
	_pulse_tween.tween_interval(0.1)
	_pulse_tween.tween_callback(
		outline_node.add_theme_stylebox_override.bind("panel", STYLE_FOCUSED)
	)

	emit_signal("hovered", chart_path)


func _read_overall_difficulty(path: String) -> int:
	if path.is_empty():
		return 0
	var metadata := ChartParser.parse_metadata(path)
	var od := int(str(metadata.get("overall_difficulty", 0)))
	if od >= 8000:
		od = int(od / 1000.0)
	return clampi(od, 1, 10)


func _od_color(od: int) -> Color:
	var t := clampf(float(od - 1) / 9.0, 0.0, 1.0) * float(OD_COLORS.size() - 1)
	var i := int(t)
	if i >= OD_COLORS.size() - 1:
		return OD_COLORS[OD_COLORS.size() - 1]
	return (OD_COLORS[i] as Color).lerp(OD_COLORS[i + 1] as Color, t - float(i))


func _apply() -> void:
	var tint := Color.WHITE
	title_node.text = level_title.to_upper() if not level_title.is_empty() else "UNTITLED"
	subtitle_node.text = level_subtitle.to_upper() if not level_subtitle.is_empty() else ""
	if background:
		level_bg.texture = Global.load_safely(background)
	if not variant:
		level_bg.modulate = Color.WHITE
		outline_node.modulate = Color.WHITE
		outline_node.add_theme_stylebox_override("panel", STYLE_NORMAL)
		variant_difficulty.visible = false
		title_node.custom_maximum_size.x = -1
		title_group.add_theme_constant_override("separation", 12)
		return
	
	title_group.add_theme_constant_override("separation", 4)
	variant_difficulty.visible = true
	title_node.custom_maximum_size.x = 450
	if overall_difficulty > 0:
		tint = _od_color(overall_difficulty)
	level_bg.modulate = tint
	outline_node.modulate = Color.WHITE if _is_selected else tint
	outline_node.add_theme_stylebox_override("panel", STYLE_VARIANT_NORMAL)
	for i in range(0, overall_difficulty):
		var pip: ColorRect = pip_parent.get_child(i)
		pip.color = tint
		difficulty_label.text = str(overall_difficulty) + ".0" + " ☆" # NOTE: Temporary until diffculty calculation is implimented
