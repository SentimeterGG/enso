# beat_point.gd — Single scrolling rhythm note (Sprite2D): moves toward the
# receptor x-position based on song time, then on hit() plays the hitsound,
# fades out and frees itself. _judged guards against double hits.
# RETURN: hit flash with sound, then frees itself
extends Sprite2D

var hit_time: float = 0.0
var receptor_x: float = 0.0
var px_per_sec: float = 600.0
var song_time: Callable
var beat_id: String = ""
@export var jump_height := 40.0

var _judged := false
var _pending_free := false
var _vibrate_tween: Tween
var _vibrate_offset: Vector2 = Vector2.ZERO
var _base_y: float = 0.0
var _base_y_ready: bool = false

@export var fade_duration := 0.3

@onready var hitsound: AudioStreamPlayer = $HitSound
@onready var outline : Sprite2D = $CircleOutline

func _ready() -> void:
	texture = SkinManager.beat_point_bg
	outline.texture = SkinManager.beat_point_outline
	_base_y = position.y
	_base_y_ready = true

func _physics_process(_delta: float) -> void:
	# lazy capture _base_y if _ready hasn't run yet (spawn sets pos before ready)
	if not _base_y_ready:
		_base_y = position.y
		_base_y_ready = true
	# keep scrolling while vibrating via additive offset (no lock)
	if song_time != null and song_time.is_valid():
		var base_x: float = receptor_x + (hit_time - song_time.call()) * px_per_sec
		position.x = lerp(position.x, base_x + _vibrate_offset.x, 0.7)
		position.y = _base_y + _vibrate_offset.y

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
		_vibrate_tween = null
	_vibrate_offset = Vector2.ZERO


func hit() -> void:
	if _judged:
		return
	_judged = true

	if _vibrate_tween and _vibrate_tween.is_valid():
		_vibrate_tween.kill()
		_vibrate_tween = null
	_vibrate_offset = Vector2.ZERO

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
		_vibrate_tween = null
	_vibrate_offset = Vector2.ZERO

	var tween := create_tween()
	_vibrate_tween = tween
	var step_dur := duration / float(maxi(shakes, 1))

	# tween additive offset so _process keeps scrolling base_x while shaking
	for i in shakes:
		var is_last := i == shakes - 1
		var target: Vector2
		if is_last:
			target = Vector2.ZERO
		else:
			var dir := 1.0 if i % 2 == 0 else -1.0
			var y_jitter := randf_range(-strength * 0.5, strength * 0.5)
			target = Vector2(dir * strength, y_jitter)
		tween.tween_property(self, "_vibrate_offset", target, step_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.finished.connect(func() -> void:
		if is_instance_valid(self):
			_vibrate_offset = Vector2.ZERO
			_vibrate_tween = null
	)


func _is_outside_viewport() -> bool:
	var viewport_width := get_viewport_rect().size.x
	# Notes scroll along x toward receptor_x, so check x bounds with a small margin.
	return position.x < -100.0 or position.x > viewport_width + 100.0
