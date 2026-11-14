class_name NotificationToast
extends PanelContainer

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
const SLIDE_IN := 0.28
const SLIDE_OUT := 0.18
const SLIDE_DISTANCE := 48.0
const SLIDE_STEPS := 5 # stepped motion, like the HTML steps(5) animation
const SPIN_SEC := 1.1

const COLORS := {
	Kind.INFO: Color("ff0000"),
	Kind.SUCCESS: Color("00ff00"),
	Kind.WARN: Color("ffff00"),
	Kind.LOADING: Color("60c8ff"),
}

const DEFAULT_SUCCESS_TITLE := "SUCCESS"
const DEFAULT_WARN_TITLE := "FAILED"


# Returned by show_loading(). Call finish() once the background work completes
# and the loading toast will turn into a success or warn notification.
class LoadingToast:
	var token := 0
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
		gen: int,
		p_success_title: String,
		p_success_body: String,
		p_warn_title: String,
		p_warn_body: String,
		p_duration: float,
	) -> void:
		_owner = owner
		token = gen
		success_title = p_success_title
		success_body = p_success_body
		warn_title = p_warn_title
		warn_body = p_warn_body
		result_duration = p_duration

	func finish(
		ok: bool,
		title: String = "",
		body: String = "",
		duration: float = -1.0,
	) -> void:
		if finished:
			return
		finished = true
		success = ok
		finish_title = title
		finish_body = body
		finish_duration = duration
		if _owner != null:
			_owner._finish_loading(self)

	# Hides the loading toast without showing a success or warn result.
	func cancel() -> void:
		if finished:
			return
		finished = true
		if _owner != null:
			_owner._cancel_loading(self)


@export var icon_info: Texture2D
@export var icon_success: Texture2D
@export var icon_warn: Texture2D
@export var icon_loading: Texture2D

var _tween: Tween = null
var _spin_tween: Tween = null
var _gen := 0
var _rest_x := 0.0
var _rest_ready := false
var _icon_style: StyleBoxFlat = null
var _loading_toast: LoadingToast = null
var _loading_presenting := false

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
	_bar.pivot_offset = Vector2.ZERO # drain from the left edge

	var sb := _icon_panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		_icon_style = sb.duplicate()
		_icon_panel.add_theme_stylebox_override("panel", _icon_style)

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
	_prepare_new_toast()
	_gen += 1
	var my := _gen

	_apply_kind(kind)
	_set_texts(title, body)
	_bar.visible = true
	_bar.scale.x = 1.0

	# Remeasure after the labels have resized the container. The toast stays
	# anchored to the right edge, so any extra width grows toward the left.
	modulate.a = 0.0
	visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	if my != _gen:
		return
	_rest_x = get_parent_area_size().x - size.x
	_set_slide(0.0)

	_tween = create_tween()
	_tween.tween_method(_set_slide, 0.0, 1.0, SLIDE_IN)
	_tween.tween_property(_bar, "scale:x", 0.0, maxf(0.2, duration)).from(1.0)
	_tween.tween_method(_set_slide, 1.0, 0.0, SLIDE_OUT)
	await _tween.finished
	if my == _gen and is_instance_valid(self):
		visible = false


# Shows a persistent loading toast with a spinning icon. The returned handle
# lets the caller switch it into a success or warn notification later:
#
#     var toast := Notification.show_loading(
#         "Importing...", "Reading the archive.",
#         "Import Complete", "Your levels were added.",
#         "Import Failed", "The archive could not be read.",
#     )
#     var ok := await do_work()
#     toast.finish(ok)
#     # or toast.finish(false, "Import Failed", "Invalid archive file.")
func show_loading(
	title: String,
	body: String = "",
	success_title: String = DEFAULT_SUCCESS_TITLE,
	success_body: String = "",
	warn_title: String = DEFAULT_WARN_TITLE,
	warn_body: String = "",
	duration: float = SHOW_SEC,
) -> LoadingToast:
	_prepare_new_toast()
	_gen += 1
	var my := _gen

	_apply_kind(Kind.LOADING)
	_set_texts(title, body)
	_bar.visible = false

	var toast := LoadingToast.new(
		self, my, success_title, success_body, warn_title, warn_body, duration
	)
	_loading_toast = toast
	_loading_presenting = true
	_present_loading(toast)
	return toast


func dismiss() -> void:
	if not visible:
		return
	_gen += 1
	var my := _gen
	_stop_spin()
	_kill_tween()
	_loading_toast = null
	_loading_presenting = false
	_tween = create_tween()
	_tween.tween_method(_set_slide, _slide_amount(), 0.0, SLIDE_OUT)
	await _tween.finished
	if my == _gen and is_instance_valid(self):
		visible = false


func _on_button_pressed() -> void:
	dismiss()


func _present_loading(toast: LoadingToast) -> void:
	modulate.a = 0.0
	visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	if toast.token != _gen:
		_loading_presenting = false
		return
	_rest_x = get_parent_area_size().x - size.x
	_set_slide(0.0)

	_tween = create_tween()
	_tween.tween_method(_set_slide, 0.0, 1.0, SLIDE_IN)
	await _tween.finished
	if toast.token != _gen:
		_loading_presenting = false
		return

	_loading_presenting = false
	if toast.finished:
		_apply_finish_loading(toast)
	else:
		_start_spin()


func _finish_loading(toast: LoadingToast) -> void:
	if toast.token != _gen:
		return
	# The presentation coroutine applies the result once it has finished
	# measuring and sliding the toast in.
	if _loading_presenting or not _rest_ready:
		return
	_apply_finish_loading(toast)


func _cancel_loading(toast: LoadingToast) -> void:
	if toast.token != _gen:
		return
	if visible:
		dismiss()
		return
	_gen += 1
	_stop_spin()
	_loading_toast = null
	_loading_presenting = false


func _apply_finish_loading(toast: LoadingToast) -> void:
	_stop_spin()
	_loading_toast = null
	_loading_presenting = false
	_kill_tween()
	_gen += 1
	var my := _gen

	var ok := toast.success
	_apply_kind(Kind.SUCCESS if ok else Kind.WARN)

	var title := toast.finish_title
	if title.is_empty():
		title = toast.success_title if ok else toast.warn_title
	var body := toast.finish_body
	if body.is_empty():
		body = toast.success_body if ok else toast.warn_body
	_set_texts(title, body)

	_bar.visible = true
	_bar.scale.x = 1.0
	modulate.a = 1.0
	visible = true

	await get_tree().process_frame
	await get_tree().process_frame
	if my != _gen:
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
	if my == _gen and is_instance_valid(self):
		visible = false


func _prepare_new_toast() -> void:
	_stop_spin()
	_kill_tween()
	_loading_toast = null
	_loading_presenting = false
	_bar.visible = true


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _start_spin() -> void:
	_stop_spin()
	_spin_tween = create_tween()
	_spin_tween.set_loops()
	_spin_tween.set_trans(Tween.TRANS_LINEAR)
	_spin_tween.tween_property(
		_icon, "offset_transform_rotation", TAU, SPIN_SEC
	).as_relative()


func _stop_spin() -> void:
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.kill()
	_spin_tween = null
	if _icon != null:
		_icon.offset_transform_rotation = 0.0


func _set_texts(title: String, body: String) -> void:
	_title.text = title.to_upper()
	_body.text = body
	_body.visible = not body.is_empty()


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
		Kind.LOADING:
			tex = icon_loading
	if tex != null:
		_icon.texture = tex
	if kind != Kind.LOADING:
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
