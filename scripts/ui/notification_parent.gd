class_name NotificationParent
extends Control

const TOAST_SCENE: PackedScene = preload("res://scenes/ui/notification_item.tscn")
const REPOSITION_DURATION := 0.2

var _toasts: Array[NotificationToast] = []
var _position_tweens: Dictionary = { }


func show_toast(
	title: String,
	body: String = "",
	kind: NotificationToast.Kind = NotificationToast.Kind.INFO,
	duration: float = NotificationToast.SHOW_SEC,
) -> void:
	var toast := _create_toast()

	toast.show_toast(title, body, kind, duration)


func show_loading(
	title: String,
	body: String = "",
	success_title: String = NotificationToast.DEFAULT_SUCCESS_TITLE,
	success_body: String = "",
	warn_title: String = NotificationToast.DEFAULT_WARN_TITLE,
	warn_body: String = "",
	duration: float = NotificationToast.SHOW_SEC,
) -> NotificationToast.LoadingToast:
	var toast := _create_toast()

	return toast.show_loading(
		title,
		body,
		success_title,
		success_body,
		warn_title,
		warn_body,
		duration,
	)


func _create_toast() -> NotificationToast:
	var toast := TOAST_SCENE.instantiate() as NotificationToast

	add_child(toast)
	_toasts.push_front(toast)
	toast.dismissed.connect(_on_toast_dismissed)

	return toast


func _on_toast_dismissed(toast: NotificationToast) -> void:
	_toasts.erase(toast)
	_position_tweens.erase(toast)
	toast.queue_free()

