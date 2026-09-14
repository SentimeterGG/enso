# beat_point.gd — Single scrolling rhythm note (Sprite2D): moves toward the
# receptor x-position based on song time, then on hit() plays the hitsound,
# fades out and frees itself. _judged guards against double hits.
# RETURN: hit flash with sound, then frees itself
extends Sprite2D

var hit_time: float = 0.0
var receptor_x: float = 0.0
var px_per_sec: float = 600.0
var song_time: Callable

var _judged := false

@export var fade_duration := 0.3

@onready var hitsound: AudioStreamPlayer = $HitSound


func _process(_delta: float) -> void:
	if _judged:
		return

	position.x = receptor_x + (hit_time - song_time.call()) * px_per_sec


func is_judged() -> bool:
	return _judged


func hit(judgment: String) -> void:
	if _judged:
		return

	_judged = true

	print("Judgment: ", judgment)

	hitsound.play()

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)

	await tween.finished

	if hitsound.playing:
		await hitsound.finished

	queue_free()
