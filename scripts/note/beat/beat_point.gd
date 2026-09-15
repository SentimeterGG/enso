# beat_point.gd — Single scrolling rhythm note (Sprite2D): moves toward the
# receptor x-position based on song time, then on hit() plays the hitsound,
# fades out and frees itself. _judged guards against double hits.
# RETURN: hit flash with sound, then frees itself
extends Sprite2D

var hit_time: float = 0.0
var receptor_x: float = 0.0
var px_per_sec: float = 600.0
var song_time: Callable
@export var jump_height := 40.0

var _judged := false
var _pending_free := false

@export var fade_duration := 0.3

@onready var hitsound: AudioStreamPlayer = $HitSound


func _process(_delta: float) -> void:
	position.x = receptor_x + (hit_time - song_time.call()) * px_per_sec

	if _pending_free and _is_outside_viewport():
		queue_free()


func is_judged() -> bool:
	return _judged


func miss() -> void:
	if _judged:
		return
	_judged = true  # flips immediately — beat_column stops calling miss() next frame
	_pending_free = true  # actual queue_free() deferred until off-screen


func hit() -> void:
	if _judged:
		return
	_judged = true

	hitsound.play()

	var start_y := position.y

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	(
		tween
		. tween_property(self, "position:y", start_y - jump_height, fade_duration)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	(
		tween
		. tween_property(self, "scale", Vector2.ONE * 2, fade_duration)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)

	await tween.finished

	if hitsound.playing:
		await hitsound.finished

	queue_free()


func _is_outside_viewport() -> bool:
	var viewport_width := get_viewport_rect().size.x
	# Notes scroll along x toward receptor_x, so check x bounds with a small margin.
	return position.x < -100.0 or position.x > viewport_width + 100.0
