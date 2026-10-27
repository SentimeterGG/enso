# notification.gd — Pixel-style toast: steps in from the right, color-coded by
# kind, with a draining timer bar that pauses on hover. Press the Button to dismiss.
# API: show_toast(title, body = "", kind = Kind.INFO, duration = 2.6)
#      show_message(text, is_error = false, duration = 2.6)   (legacy wrapper)
class_name NotificationToast
extends Control

enum Kind {
	INFO,
	SUCCESS,
	WARN,
}
const STYLES := {
	Kind.INFO: preload("res://resources/theme/Notification/info.tres"),
	Kind.SUCCESS: preload("res://resources/theme/Notification/success.tres"),
	Kind.WARN: preload("res://resources/theme/Notification/warn.tres"),
}
const SHOW_SEC := 3.6
const SLIDE_IN := 0.28
const SLIDE_OUT := 0.18
const SLIDE_DISTANCE := 48.0
const SLIDE_STEPS := 5 # stepped motion, like the HTML steps(5) animation

const COLORS := {
	Kind.INFO: Color("ff0000"),
	Kind.SUCCESS: Color("00ff00"),
	Kind.WARN: Color("ffff00"),
}

## Optional per-kind icons. Leave empty to keep the icon already in the scene.
@export var icon_info: Texture2D
@export var icon_success: Texture2D
@export var icon_warn: Texture2D

@onready var _title: Label = $Margin/HBoxContainer/VBoxContainer/Title
@onready var _body: Label = $Margin/HBoxContainer/VBoxContainer/Body
@onready var _icon: TextureRect = $Margin/HBoxContainer/AspectRatioContainer/Panel/MarginContainer/TextureRect
@onready var _icon_panel: Panel = $Margin/HBoxContainer/AspectRatioContainer/Panel
@onready var _button: Button = $Button
@onready var _bar: Control = $DurationVisual

var _tween: Tween = null
var _gen := 0
var _rest_x := 0.0
var _rest_ready := false
var _icon_style: StyleBoxFlat = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.mouse_entered.connect(_set_paused.bind(true))
	_button.mouse_exited.connect(_set_paused.bind(false))
	_bar.pivot_offset = Vector2.ZERO # drain from the left edge

	# Own copy of the icon box style so the border can change color per kind.
	var sb := _icon_panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		_icon_style = sb.duplicate()
		_icon_panel.add_theme_stylebox_override("panel", _icon_style)

	# Anchors resolve on the first frame; remember where the toast rests.
	await get_tree().process_frame
	_rest_x = position.x
	_rest_ready = true
	visible = false


func show_toast(
	title: String,
	body: String = "",
	kind: Kind = Kind.INFO,
	duration: float = SHOW_SEC,
) -> void:
	if not _rest_ready:
		await get_tree().process_frame
	_gen += 1
	var my := _gen
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_apply_kind(kind)
	_title.text = title.to_upper()
	_body.text = body
	_body.visible = not body.is_empty()
	_bar.scale.x = 1.0
	_set_slide(0.0)
	visible = true

	# One timeline: slide in -> drain the bar -> slide out. Pausing it on hover
	# freezes the bar and the timer together.
	_tween = create_tween()
	_tween.tween_method(_set_slide, 0.0, 1.0, SLIDE_IN)
	_tween.tween_property(_bar, "scale:x", 0.0, maxf(0.2, duration)).from(1.0)
	_tween.tween_method(_set_slide, 1.0, 0.0, SLIDE_OUT)
	await _tween.finished
	if my == _gen and is_instance_valid(self):
		visible = false


func dismiss() -> void:
	if not visible:
		return
	_gen += 1
	var my := _gen
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_slide, _slide_amount(), 0.0, SLIDE_OUT)
	await _tween.finished
	if my == _gen and is_instance_valid(self):
		visible = false


func _on_button_pressed() -> void:
	dismiss()


func _apply_kind(kind: Kind) -> void:
	var color: Color = COLORS[kind]
	_bar.color = color
	_icon.modulate = color
	if _icon_style != null:
		_icon_style.border_color = color
	var tex: Texture2D = null
	add_theme_stylebox_override("panel", STYLES[kind])
	match kind:
		Kind.INFO:
			tex = icon_info
		Kind.SUCCESS:
			tex = icon_success
		Kind.WARN:
			tex = icon_warn
	if tex != null:
		_icon.texture = tex


## t: 0 = off to the right and hidden, 1 = resting position. Quantized to steps.
func _set_slide(t: float) -> void:
	var s := floorf(t * SLIDE_STEPS) / SLIDE_STEPS
	position.x = _rest_x + (1.0 - s) * SLIDE_DISTANCE
	modulate.a = s


func _slide_amount() -> float:
	return clampf(1.0 - (position.x - _rest_x) / SLIDE_DISTANCE, 0.0, 1.0)


func _set_paused(paused: bool) -> void:
	if _tween == null or not _tween.is_valid():
		return
	if paused:
		_tween.pause()
	else:
		_tween.play()
