class_name NotificationToast
extends PanelContainer

signal dismissed(toast: NotificationToast)

enum Kind {
	INFO,
	SUCCESS,
	WARN,
	LOADING,
}

const STYLES := {
	Kind.INFO: preload("res://resources/themes/Notification/info.tres"),
	Kind.SUCCESS: preload("res://resources/themes/Notification/success.tres"),
	Kind.WARN: preload("res://resources/themes/Notification/warn.tres"),
	Kind.LOADING: preload("res://resources/themes/Notification/loading.tres"),
}

const SHOW_SEC := 3.6
const MIN_WIDTH := 0.0
const MAX_WIDTH := 900.0
const SLIDE_IN := 0.28
const SLIDE_OUT := 0.18
const SLIDE_DISTANCE := 48.0
const SLIDE_STEPS := 5

const SPIN_SEC := 1.1

const COLORS := {
	Kind.INFO: Color("ff0000"),
	Kind.SUCCESS: Color("00ff00"),
	Kind.WARN: Color("ffff00"),
	Kind.LOADING: Color("60c8ff"),
}

const DEFAULT_SUCCESS_TITLE := "SUCCESS"
const DEFAULT_WARN_TITLE := "FAILED"


# Returned by show_loading().
# Call finish() when the background operation completes.
class LoadingToast:
	var finished := false
	var success := false

	var finish_title := ""
	var finish_body := ""
	var finish_duration := -1.0

	var success_title := ""
	var success_body := ""

	var warn_title := ""
	var warn_body := ""

	var result_duration := 0.0

	var _owner: NotificationToast


	func _init(
		owner: NotificationToast,
		p_success_title: String,
		p_success_body: String,
		p_warn_title: String,
		p_warn_body: String,
		p_duration: float,
	) -> void:
		_owner = owner

		success_title = p_success_title
		success_body = p_success_body

		warn_title = p_warn_title
		warn_body = p_warn_body

		result_duration = p_duration


	func finish(ok: bool, title: String = "", body: String = "", duration: float = -1.0) -> void:
		if finished:
			return

		finished = true
		success = ok

		finish_title = title
		finish_body = body
		finish_duration = duration

		if is_instance_valid(_owner):
			_owner._finish_loading(self)


	func cancel() -> void:
		if finished:
			return

		finished = true

		if is_instance_valid(_owner):
			_owner._cancel_loading(self)


@export var icon_info: Texture2D
@export var icon_success: Texture2D
@export var icon_warn: Texture2D
@export var icon_loading: Texture2D

var _tween: Tween
var _spin_tween: Tween

var _rest_x := 0.0
var _icon_style: StyleBoxFlat

var _loading_toast: LoadingToast
var _loading_presenting := false

var _closing := false

@onready var _title: Label = $Margin/HBoxContainer/VBoxContainer/Title
@onready var _body: Label = $Margin/HBoxContainer/VBoxContainer/Body

@onready var _icon: TextureRect = $Margin/HBoxContainer/AspectRatioContainer/Panel/MarginContainer/TextureRect
@onready var _icon_panel: Panel = $Margin/HBoxContainer/AspectRatioContainer/Panel

@onready var _button: Button = $Button
@onready var _bar: Control = $DurationVisual


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_button.mouse_entered.connect(_set_paused.bind(true))
	_button.mouse_exited.connect(_set_paused.bind(false))

	_bar.pivot_offset = Vector2.ZERO

	var sb := _icon_panel.get_theme_stylebox("panel")

	if sb is StyleBoxFlat:
		_icon_style = sb.duplicate()
		_icon_panel.add_theme_stylebox_override("panel", _icon_style)

	visible = false

# --------------------------------------------------
# NORMAL NOTIFICATION
# --------------------------------------------------


func show_toast(
	title: String,
	body: String = "",
	kind: Kind = Kind.INFO,
	duration: float = SHOW_SEC,
) -> void:
	_apply_kind(kind)
	_set_texts(title, body)

	_bar.visible = true
	_bar.scale.x = 1.0

	modulate.a = 1.0
	visible = true

	await _wait_for_layout()

	if _closing:
		return

	_rest_x = get_parent_area_size().x - size.x
	_set_slide(0.0)

	_tween = create_tween()

	_tween.tween_method(_set_slide, 0.0, 1.0, SLIDE_IN)

	_tween.tween_property(_bar, "scale:x", 0.0, maxf(0.2, duration)).from(1.0)

	_tween.tween_method(_set_slide, 1.0, 0.0, SLIDE_OUT)

	await _tween.finished

	if not _closing:
		_close_toast()

# --------------------------------------------------
# LOADING NOTIFICATION
# --------------------------------------------------


func show_loading(
	title: String,
	body: String = "",
	success_title: String = DEFAULT_SUCCESS_TITLE,
	success_body: String = "",
	warn_title: String = DEFAULT_WARN_TITLE,
	warn_body: String = "",
	duration: float = SHOW_SEC,
) -> LoadingToast:
	_apply_kind(Kind.LOADING)
	_set_texts(title, body)

	_bar.visible = false

	var toast := LoadingToast.new(
		self,
		success_title,
		success_body,
		warn_title,
		warn_body,
		duration,
	)

	_loading_toast = toast
	_loading_presenting = true

	_present_loading(toast)

	return toast


func _present_loading(toast: LoadingToast) -> void:
	modulate.a = 0.0
	visible = true

	await _wait_for_layout()

	if _closing:
		return

	_rest_x = get_parent_area_size().x - size.x
	_set_slide(0.0)

	_tween = create_tween()

	_tween.tween_method(_set_slide, 0.0, 1.0, SLIDE_IN)

	await _tween.finished

	if _closing:
		return

	_loading_presenting = false

	if toast.finished:
		_apply_finish_loading(toast)
		return
	_start_spin()


func _finish_loading(toast: LoadingToast) -> void:
	if _loading_toast != toast:
		return

	# Wait until the entrance animation finishes.
	if _loading_presenting:
		return

	_apply_finish_loading(toast)


func _cancel_loading(toast: LoadingToast) -> void:
	if _loading_toast != toast:
		return

	_loading_toast = null
	dismiss()


func _apply_finish_loading(toast: LoadingToast) -> void:
	if _closing:
		return

	_stop_spin()
	_kill_tween()

	_loading_toast = null

	var ok := toast.success

	_apply_kind(Kind.SUCCESS if ok else Kind.WARN)

	var title := toast.finish_title
	var body := toast.finish_body

	if title.is_empty():
		title = toast.success_title if ok else toast.warn_title

	if body.is_empty():
		body = toast.success_body if ok else toast.warn_body

	_set_texts(title, body)

	_bar.visible = true
	_bar.scale.x = 1.0

	modulate.a = 1.0
	visible = true

	await _wait_for_layout()

	if _closing:
		return

	_rest_x = get_parent_area_size().x - size.x
	_set_slide(1.0)

	var duration := toast.finish_duration

	if duration < 0.0:
		duration = toast.result_duration

	_tween = create_tween()

	_tween.tween_property(_bar, "scale:x", 0.0, maxf(0.2, duration)).from(1.0)

	_tween.tween_method(_set_slide, 1.0, 0.0, SLIDE_OUT)

	await _tween.finished

	if not _closing:
		_close_toast()

# --------------------------------------------------
# DISMISSAL
# --------------------------------------------------


func dismiss() -> void:
	if _closing:
		return

	_closing = true

	_stop_spin()
	_kill_tween()

	_loading_toast = null
	_loading_presenting = false

	if not visible:
		_close_toast()
		return

	_tween = create_tween()

	_tween.tween_method(_set_slide, _slide_amount(), 0.0, SLIDE_OUT)

	await _tween.finished

	_close_toast()


func _close_toast() -> void:
	if not is_inside_tree():
		return

	_closing = true

	_stop_spin()
	_kill_tween()

	dismissed.emit(self)


func _on_button_pressed() -> void:
	dismiss()

# --------------------------------------------------
# ANIMATIONS
# --------------------------------------------------


func _start_spin() -> void:
	_stop_spin()

	_spin_tween = create_tween()
	_spin_tween.set_loops()
	_spin_tween.set_trans(Tween.TRANS_LINEAR)

	_spin_tween.tween_property(_icon, "offset_transform_rotation", TAU, SPIN_SEC).as_relative()


func _stop_spin() -> void:
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.kill()

	_spin_tween = null

	if is_instance_valid(_icon):
		_icon.offset_transform_rotation = 0.0


func _set_slide(t: float) -> void:
	var s := floorf(t * SLIDE_STEPS) / SLIDE_STEPS

	position.x = _rest_x + (1.0 - s) * SLIDE_DISTANCE
	modulate.a = s


func _slide_amount() -> float:
	return clampf(1.0 - (position.x - _rest_x) / SLIDE_DISTANCE, 0.0, 1.0)


func _set_paused(paused: bool) -> void:
	if _loading_toast != null:
		return

	if _tween == null or not _tween.is_valid():
		return

	if paused:
		_tween.pause()
	else:
		_tween.play()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = null


func _set_texts(title: String, body: String) -> void:
	_title.text = title.to_upper()

	_body.text = body
	_body.visible = not body.is_empty()
	_update_width()


func _apply_kind(kind: Kind) -> void:
	var color: Color = COLORS[kind]

	_bar.color = color
	_icon.modulate = color

	if _icon_style != null:
		_icon_style.border_color = color

	add_theme_stylebox_override("panel", STYLES[kind])

	var tex: Texture2D = null

	match kind:
		Kind.INFO:
			tex = icon_info
		Kind.SUCCESS:
			tex = icon_success
		Kind.WARN:
			tex = icon_warn
		Kind.LOADING:
			tex = icon_loading

	if tex != null:
		_icon.texture = tex

	if kind != Kind.LOADING:
		_icon.offset_transform_rotation = 0.0


func _wait_for_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _update_width() -> void:
	var text_width := maxf(_get_text_width(_title), _get_text_width(_body))

	var required_width := text_width + 156.0

	var target_width := clampf(required_width, MIN_WIDTH, MAX_WIDTH)

	custom_minimum_size.x = target_width
	size.x = target_width


func _get_text_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")

	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

