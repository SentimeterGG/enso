# level_item.gd — Clickable level list row (Panel): selects itself in the parent
# list on left-click release (ignoring drags) and swaps focused/normal stylebox
# via set_selected(). Display is filled via setup(title, subtitle, chart_path)
# so level_list.gd can build rows dynamically from discovered charts.
# RETURN: selection event forwarded to the level list
extends Panel

signal hovered(chart_path: String)

const STYLE_NORMAL: StyleBox = preload("res://resources/theme/level_select_button.tres")
const STYLE_FOCUSED: StyleBox = preload("res://resources/theme/level_select_button_focused.tres")
const STYLE_FOCUSED_PULSE: StyleBox = preload(
	"res://resources/theme/level_select_button_focused_blink.tres"
)

var chart_path: String = ""
var level_title: String = ""
var level_subtitle: String = ""
var background: String = ""
var _pulse_tween: Tween
var variant: bool = false
var data_id = -1


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
	_apply_text()


func set_selected(selected: bool) -> void:
	var panel: Panel = get_node_or_null("Panel")
	if panel == null:
		return

	# Cancel any pending "pulse -> focused" swap from a previous call
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()

	if not selected:
		panel.add_theme_stylebox_override("panel", STYLE_NORMAL)
		return

	panel.add_theme_stylebox_override("panel", STYLE_FOCUSED_PULSE)
	_pulse_tween = create_tween()
	_pulse_tween.tween_interval(0.1)
	_pulse_tween.tween_callback(panel.add_theme_stylebox_override.bind("panel", STYLE_FOCUSED))

	emit_signal("hovered", chart_path)


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
	if background:
		texture_node.texture = Global.load_safely(background)
