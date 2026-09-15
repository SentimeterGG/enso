# beat_column.gd — Rhythm lane judge: spawns beat_point notes, matches draw
# start/direction-change inputs to the closest note within excellent/good/bad
# timing windows, flashes the receptor on input, and reads song time from the
# music player.
# RETURN: judged hits (excellent, good, bad) with receptor flash
extends Node2D

const BEAT_POINT := preload("res://scenes/beat_point.tscn")
const FLASH_DURATION := 0.1

@onready var beat_rec_clicked = $beat_receptor/clicked
@onready var judge_spawner = %judge_spawner
signal beat_hit(error_ms: float)
var click := false

var _flash_tween: Tween


func _ready() -> void:
	beat_rec_clicked.hide()


func _process(_delta: float) -> void:
	var song_time := get_song_time()

	for beat in get_children():
		if not beat.has_method("hit"):
			continue
		if beat.is_judged():
			continue

		# If the note is now further past its hit_time than the worst
		# allowed window, it's unrecoverable — auto-miss it.
		if song_time - beat.hit_time > judge_spawner.get_bad_window_ms() / 1000.0:
			beat.miss()
			emit_signal("beat_hit", INF)  # or a dedicated beat_missed signal, see below


func spawn_beat(
	hit_time: float, receptor_x: float, px_per_sec: float, color: Color = Color.WHITE
) -> void:
	var beat_point = BEAT_POINT.instantiate()

	beat_point.hit_time = hit_time
	beat_point.receptor_x = receptor_x
	beat_point.px_per_sec = px_per_sec
	beat_point.song_time = get_song_time
	beat_point.self_modulate = color
	beat_point.position = $beat_spawner.position

	add_child(beat_point)


func _try_hit_note(input_time: float) -> void:
	var best: Node2D = null
	var best_error := INF

	for beat in get_children():
		if not beat.has_method("hit"):
			continue

		if beat.is_judged():
			continue

		var timing_error: float = input_time - beat.hit_time
		var error := absf(timing_error)

		# Don't accept input outside the largest judgment window.
		if error > judge_spawner.get_bad_window_ms() / 1000.0:  # originally error > bad_window_ms / 1000.0
			continue

		# Find the note closest to the player's input time.
		if error < best_error:
			best = beat
			best_error = error

	if best != null:
		var timing_error: float = input_time - best.hit_time
		emit_signal("beat_hit", timing_error)
		best.hit()


func _on_draw_direction_changes() -> void:
	_flash_clicked()
	_try_hit_note(get_song_time())


func _on_draw_started() -> void:
	_flash_clicked()
	_try_hit_note(get_song_time())


func get_song_time() -> float:
	return BgMusic.get_playback_position()


func _flash_clicked() -> void:
	if _flash_tween:
		_flash_tween.kill()

	click = true
	beat_rec_clicked.show()

	_flash_tween = create_tween()
	_flash_tween.tween_interval(FLASH_DURATION)
	_flash_tween.tween_callback(
		func():
			beat_rec_clicked.hide()
			click = false
	)
