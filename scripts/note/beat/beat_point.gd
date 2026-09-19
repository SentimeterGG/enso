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
var _vibrating := false
var _vibrate_tween: Tween
var _vibrate_origin: Vector2

@export var fade_duration := 0.3

@onready var hitsound: AudioStreamPlayer = $HitSound
@onready var outline : Sprite2D = $CircleOutline

func _ready() -> void:
	texture = SkinManager.beat_point_bg
	outline.texture = SkinManager.beat_point_outline
func _process(_delta: float) -> void:
	if not _vibrating:
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
	if _vibrate_tween and _vibrate_tween.is_valid():
		_vibrate_tween.kill()
		_vibrating = false
		_vibrate_tween = null


func hit() -> void:
	if _judged:
		return
	_judged = true

	if _vibrate_tween and _vibrate_tween.is_valid():
		_vibrate_tween.kill()
		_vibrating = false
		_vibrate_tween = null

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


func vibrate(duration: float = 0.12, strength: float = 4.0, shakes: int = 6) -> void:
	if _judged:
		return
	if _vibrate_tween and _vibrate_tween.is_valid():
		_vibrate_tween.kill()
		position = _vibrate_origin

	# lock current world pos — _process will stop driving position.x while vibrating
	_vibrate_origin = position
	_vibrating = true

	var tween := create_tween()
	_vibrate_tween = tween
	var step_dur := duration / float(maxi(shakes, 1))

	# alternate left/right (+ small y jitter) around locked origin, end exactly on origin
	for i in shakes:
		var is_last := i == shakes - 1
		var target: Vector2
		if is_last:
			target = _vibrate_origin
		else:
			var dir := 1.0 if i % 2 == 0 else -1.0
			var y_jitter := randf_range(-strength * 0.5, strength * 0.5)
			target = _vibrate_origin + Vector2(dir * strength, y_jitter)
		tween.tween_property(self, "position", target, step_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.finished.connect(func() -> void:
		if is_instance_valid(self):
			_vibrating = false
			_vibrate_tween = null
			# snap back to live scroll pos (avoids 1-frame stale pop); keep locked y
			if song_time != null and song_time.is_valid():
				position.x = receptor_x + (hit_time - song_time.call()) * px_per_sec
				position.y = _vibrate_origin.y
			else:
				position = _vibrate_origin
	)


func _is_outside_viewport() -> bool:
	var viewport_width := get_viewport_rect().size.x
	# Notes scroll along x toward receptor_x, so check x bounds with a small margin.
	return position.x < -100.0 or position.x > viewport_width + 100.0
