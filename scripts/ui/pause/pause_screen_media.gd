extends Node


func set_media_paused(value: bool) -> void:
	_set_audio_paused(value)
	_set_video_paused(value)


func _set_audio_paused(value: bool) -> void:
	var bg := get_node_or_null("/root/BgMusic") as AudioStreamPlayer

	if bg != null:
		bg.stream_paused = value


func _set_video_paused(value: bool) -> void:
	var scene := get_tree().current_scene

	if scene == null:
		return

	var video := scene.get_node_or_null("%VideoStreamPlayer") as VideoStreamPlayer

	if video != null:
		video.paused = value
