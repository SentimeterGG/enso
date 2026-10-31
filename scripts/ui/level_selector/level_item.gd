# level_item.gd — Clickable level list row (Panel): selects itself in the parent
# list on left-click release (ignoring drags) and swaps focused/normal stylebox
# via set_selected(). Display is filled via setup(title, subtitle, chart_path)
# so level_list.gd can build rows dynamically from discovered charts.
# RETURN: selection event forwarded to the level list
extends Panel

signal hovered(chart_path: String)

const STYLE_NORMAL: StyleBox = preload("res://resources/theme/level_select_button.tres")
const STYLE_FOCUSED: StyleBox = preload("res://resources/theme/level_select_button_focused.tres")
const STYLE_PARENT_FOCUSED: StyleBox = preload(
	"res://resources/theme/level_select_button_focused.tres"
)
const STYLE_VARIANT_NORMAL: StyleBox = preload(
	"res://resources/theme/level_select_button_variant.tres"
)
const STYLE_FOCUSED_PULSE: StyleBox = preload(
	"res://resources/theme/level_select_button_focused_blink.tres"
)
## Variant rows tint their background strip with the chart's difficulty:
## blue -> green -> yellow -> red -> purple as overall_difficulty goes 1 -> 10.
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
var _pulse_tween: Tween
var variant: bool = false
var data_id = -1
var _is_selected: bool = false
var _parent_focused: bool = false


func _ready() -> void:
	_apply_text()


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
	_apply_text()


## Reads the chart's overall_difficulty (1-10). Older charts store it scaled by
## 1000, so values like 8000 are normalised back down.
func _read_overall_difficulty(path: String) -> int:
	if path.is_empty():
		return 0
	var metadata := ChartParser.parse_metadata(path)
	var od := int(str(metadata.get("overall_difficulty", 0)))
	if od >= 8000:
		od = int(od / 1000.0)
	return clampi(od, 1, 10)


## Smooth 1 -> 10 gradient through blue, green, yellow, red, purple.
func _od_color(od: int) -> Color:
	var t := clampf(float(od - 1) / 9.0, 0.0, 1.0) * float(OD_COLORS.size() - 1)
	var i := int(t)
	if i >= OD_COLORS.size() - 1:
		return OD_COLORS[OD_COLORS.size() - 1]
	return (OD_COLORS[i] as Color).lerp(OD_COLORS[i + 1] as Color, t - float(i))


## Tints the variant's background strip (and its idle border) with the chart's
## difficulty colour. The selected row keeps a white panel so its red focused
## border stays red.
func _apply_style() -> void:
	var texture_node: TextureRect = get_node_or_null("TextureRect")
	var panel: Panel = get_node_or_null("Panel")
	var tint := Color.WHITE
	var pip_parent: HBoxContainer = get_node_or_null(
		"MarginContainer/VariantDifficulty/MarginContainer/Pipe"
	)
	var difficulty_label: Label = get_node_or_null("MarginContainer/VariantDifficulty/Difficulty")

	if not variant:
		texture_node.modulate = Color.WHITE
		panel.modulate = Color.WHITE
		panel.add_theme_stylebox_override("panel", STYLE_NORMAL)
		%VariantDifficulty.visible = false
		return

	%VariantDifficulty.visible = true
	if overall_difficulty > 0:
		tint = _od_color(overall_difficulty)
	texture_node.modulate = tint
	panel.modulate = Color.WHITE if _is_selected else tint
	panel.add_theme_stylebox_override("panel", STYLE_VARIANT_NORMAL)
	for i in range(0, overall_difficulty):
		var pip: ColorRect = pip_parent.get_child(i)
		pip.color = tint
		difficulty_label.text = str(overall_difficulty) + ".0" + " ☆" # NOTE: Temporary until diffculty calculation is implimented


func set_selected(selected: bool) -> void:
	var panel: Panel = get_node_or_null("Panel")
	if panel == null:
		return
	# Scrolling re-applies this every step; ignore no-op changes so the red
	# border does not re-pulse and the details are not re-emitted.
	if _is_selected == selected:
		return
	_is_selected = selected
	_apply_style()

	# Cancel any pending "pulse -> focused" swap from a previous call
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()

	if not selected:
		panel.add_theme_stylebox_override(
			"panel",
			STYLE_PARENT_FOCUSED if _parent_focused else STYLE_NORMAL,
		)
		return

	panel.add_theme_stylebox_override("panel", STYLE_FOCUSED_PULSE)
	_pulse_tween = create_tween()
	_pulse_tween.tween_interval(0.1)
	_pulse_tween.tween_callback(panel.add_theme_stylebox_override.bind("panel", STYLE_FOCUSED))

	emit_signal("hovered", chart_path)


## The owning level row is drawn with the focused border while one of its
## variants is the selected row, without becoming selected itself.
func set_parent_focused(focused: bool) -> void:
	if _parent_focused == focused:
		return
	_parent_focused = focused
	if _is_selected:
		return
	var panel: Panel = get_node_or_null("Panel")
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", STYLE_PARENT_FOCUSED if focused else STYLE_NORMAL)


func play_pulse() -> void:
	var player := get_node_or_null("level_item_animation") as AnimationPlayer
	if player == null or not player.has_animation("pulse"):
		return
	player.stop()
	player.play("pulse")


func _apply_text() -> void:
	# Labels may not exist yet if setup() runs before _ready(); resolve lazily.
	var title_node: Label = get_node_or_null("MarginContainer/VBoxContainer/Label")
	var subtitle_node: Label = get_node_or_null("MarginContainer/VBoxContainer/Label2")
	var texture_node: TextureRect = get_node_or_null("TextureRect")
	if title_node:
		title_node.text = level_title.to_upper() if not level_title.is_empty() else "UNTITLED"
	if subtitle_node:
		subtitle_node.text = level_subtitle.to_upper() if not level_subtitle.is_empty() else ""
	# Variant rows carry their chart's difficulty colour on the background strip.
	_apply_style()
	if background and texture_node:
		texture_node.texture = Global.load_safely(background)
