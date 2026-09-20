# beat_column.gd — Rhythm lane judge: spawns beat_point notes, matches draw
# start/direction-change inputs to the closest note within excellent/good/bad
# timing windows, flashes the receptor on input, and reads song time from the
# music player.
# RETURN: judged hits (excellent, good, bad) with receptor flash
extends Node2D

const BEAT_POINT := preload("res://scenes/beat_point.tscn")
const FLASH_DURATION := 0.1

@onready var beat_receptor = $beat_receptor
@onready var beat_receptor_clicked = $beat_receptor_clicked
@onready var judge_spawner = %judge_spawner
# Accessible as %draw in game.tscn (unique_name_in_owner = true on game/draw)
var _draw: Line2D = null
@export var input_cooldown_sec := 0.05  # tune this — smaller = more spam-tolerant, larger = stricter
signal beat_hit(error_ms: float, beat_id: String)
var click := false

var _last_input_time := -INF
var _flash_tween: Tween

# --- note lock (per shape id) ---
var _locked_id: String = ""
var _is_locked: bool = false


func _ready() -> void:
	beat_receptor.texture = SkinManager.beat_receptor
	beat_receptor_clicked.texture = SkinManager.beat_receptor_clicked
	beat_receptor_clicked.hide()
	_draw = _get_draw_node()


func _process(_delta: float) -> void:
	var song_time := get_song_time()
	var bad_window := HitResult.bad_window_ms(_od()) / 1000.0

	for beat in get_children():
		if not beat.has_method("hit"):
			continue
		if beat.is_judged():
			continue

		# If the note is now further past its hit_time than the worst
		# allowed window, it's unrecoverable — auto-miss it.
		if song_time - beat.hit_time > bad_window:
			var miss_id: String = str(beat.beat_id) if beat.has_method("vibrate") else ""
			beat.miss()
			emit_signal("beat_hit", INF, miss_id)


func spawn_beat(
	hit_time: float, receptor_x: float, px_per_sec: float, color: Color = Color.WHITE, beat_id: String = ""
) -> void:
	var beat_point = BEAT_POINT.instantiate()

	beat_point.hit_time = hit_time
	beat_point.receptor_x = receptor_x
	beat_point.px_per_sec = px_per_sec
	beat_point.song_time = get_song_time
	beat_point.self_modulate = color
	beat_point.beat_id = beat_id
	beat_point.position = $beat_spawner.position

	add_child(beat_point)


func _try_hit_note(input_time: float) -> void:
	# Debounce: ignore attempts that come in faster than a human could
	# realistically intend as separate hits.
	if input_time - _last_input_time < input_cooldown_sec:
		return

	var best: Node2D = null
	var best_error := INF
	# Also track closest locked vs non-locked for vibrate feedback
	var best_other: Node2D = null
	var best_other_error := INF
	var bad_window := HitResult.bad_window_ms(_od()) / 1000.0

	for beat in get_children():
		if not beat.has_method("hit"):
			continue
		if beat.is_judged():
			continue

		var timing_error: float = input_time - beat.hit_time
		var error := absf(timing_error)

		if error > bad_window:
			continue

		# When locked, only beats with matching id are hittable
		var bid: String = str(beat.beat_id) if beat.has_method("vibrate") else ""
		if _is_locked and bid != _locked_id:
			if error < best_other_error:
				best_other = beat
				best_other_error = error
			continue

		if error < best_error:
			best = beat
			best_error = error

	# Locked: no hittable beat of locked id in window, but a different id tried -> vibrate
	if best == null and _is_locked and best_other != null:
		if best_other.has_method("vibrate"):
			best_other.vibrate()
		# vibrate all other locked-out beats in window for visual feedback
		for beat in get_children():
			if not beat.has_method("vibrate") or beat.is_judged():
				continue
			var bid2: String = str(beat.beat_id)
			if bid2 == _locked_id:
				continue
			var err2 := absf(input_time - beat.hit_time)
			if err2 <= bad_window and beat != best_other:
				beat.vibrate()
		return

	# Also if locked and best is from different id (should not happen due to filter, but safe)
	if best != null and _is_locked:
		var best_bid: String = str(best.beat_id)
		if best_bid != _locked_id:
			if best.has_method("vibrate"):
				best.vibrate()
			return

	if best != null:
		_last_input_time = input_time  # only update cooldown on an actual judged attempt
		var timing_error: float = input_time - best.hit_time
		var hit_id: String = str(best.beat_id) if best.has_method("vibrate") else ""
		emit_signal("beat_hit", timing_error, hit_id)
		best.hit()
		# --- lock to this beat's id so other ids vibrate instead of hitting (L96-L98) ---
		if not hit_id.is_empty():
			_is_locked = true
			_locked_id = hit_id


func _on_draw_direction_changes() -> void:
	_flash_clicked()
	_try_hit_note(get_song_time())


func _on_draw_started() -> void:
	_flash_clicked()
	# --- change %draw (Line2D) color into the beat's color + update target_shape (L144-148) ---
	# target_shape was previously time-driven in note_scheduler.gd, now beat-driven here
	var best_for_draw := _find_best_beat(get_song_time())
	if best_for_draw != null:
		if _draw == null:
			_draw = _get_draw_node()
		if _draw != null:
			_draw.default_color = (best_for_draw as CanvasItem).self_modulate
		_update_target_shape_for_beat(best_for_draw)
		_notify_shape_begin(best_for_draw)
	elif _is_locked:
		# no window beat but locked — keep locked beat's visual
		var locked_beat := _find_locked_beat()
		if locked_beat != null:
			if _draw == null:
				_draw = _get_draw_node()
			if _draw != null:
				_draw.default_color = (locked_beat as CanvasItem).self_modulate
			_update_target_shape_for_beat(locked_beat)
			_notify_shape_begin(locked_beat)
	_try_hit_note(get_song_time())


func get_song_time() -> float:
	return BgMusic.get_playback_position()


func _od() -> float:
	if Global.current_chart != null:
		return Global.current_chart.get_od()
	return 0.0


func _score() -> ScoreManager:
	var n := get_node_or_null("%accuracy_manager")
	if n is ScoreManager:
		return n as ScoreManager
	var root := get_tree().current_scene if get_tree() else null
	if root != null:
		n = root.get_node_or_null("%accuracy_manager")
		if n is ScoreManager:
			return n as ScoreManager
	return null


func _notify_shape_begin(beat: Node2D) -> void:
	if beat == null or not beat.has_method("vibrate"):
		return
	var bid := str(beat.beat_id)
	if bid.is_empty():
		return
	var sc := _score()
	if sc != null:
		sc.begin_shape(bid)


func _get_draw_node() -> Line2D:
	# %draw is unique in game.tscn (unique_name_in_owner = true)
	# beat_column runs under game/owner, so % lookup should succeed.
	var n := get_node_or_null("%draw")
	if n is Line2D:
		return n as Line2D
	# fallback: search via owner (game.tscn root)
	var owner_node := owner
	if owner_node != null:
		n = owner_node.get_node_or_null("%draw")
		if n is Line2D:
			return n as Line2D
	# last fallback: absolute scene path search
	n = get_tree().current_scene.get_node_or_null("%draw") if get_tree() and get_tree().current_scene else null
	if n is Line2D:
		return n as Line2D
	return null


func _get_target_shape_node() -> Line2D:
	# prefer draw's exported target_shape, fallback to %target_shape unique or tree search
	if _draw != null and _draw.get("target_shape") != null and _draw.target_shape is Line2D:
		return _draw.target_shape as Line2D
	var n := get_node_or_null("%target_shape")
	if n is Line2D:
		return n as Line2D
	var owner_node2 := owner
	if owner_node2 != null:
		n = owner_node2.get_node_or_null("%target_shape")
		if n is Line2D:
			return n as Line2D
	n = get_tree().current_scene.get_node_or_null("%target_shape") if get_tree() and get_tree().current_scene else null
	if n is Line2D:
		return n as Line2D
	# last fallback: find sibling via note_manager -> game
	var root := get_tree().current_scene
	if root != null and root.has_node("target_shape"):
		n = root.get_node("target_shape")
		if n is Line2D:
			return n as Line2D
	return null


func _find_best_beat(t: float) -> Node2D:
	var best: Node2D = null
	var best_err := INF
	var bad_window := HitResult.bad_window_ms(_od()) / 1000.0
	for beat in get_children():
		if not beat.has_method("hit") or beat.is_judged():
			continue
		var bid: String = str(beat.beat_id) if beat.has_method("vibrate") else ""
		if _is_locked and bid != _locked_id:
			continue
		var err := absf(t - beat.hit_time)
		if err > bad_window:
			continue
		if err < best_err:
			best = beat
			best_err = err
	return best


func _find_locked_beat() -> Node2D:
	for beat in get_children():
		if not beat.has_method("hit") or beat.is_judged():
			continue
		if str(beat.beat_id) == _locked_id:
			return beat
	return null


func _update_target_shape_for_beat(beat: Node2D) -> void:
	if beat == null:
		return
	var bid: String = str(beat.beat_id) if beat.has_method("vibrate") else ""
	if bid.is_empty():
		return
	if Global.current_chart == null:
		return
	var pts := Global.current_chart.shape_points_by_id(bid)
	if pts.is_empty():
		return
	var target := _get_target_shape_node()
	if target != null and target.has_method("change"):
		target.change(pts)


func _update_draw_color() -> void:
	if _draw == null:
		_draw = _get_draw_node()
		if _draw == null:
			return
	var t := get_song_time()
	var best: Node2D = null
	var best_err := INF
	var bad_window := HitResult.bad_window_ms(_od()) / 1000.0
	# respect lock: only beats of locked_id are considered target
	for beat in get_children():
		if not beat.has_method("hit") or beat.is_judged():
			continue
		var bid: String = str(beat.beat_id) if beat.has_method("vibrate") else ""
		if _is_locked and bid != _locked_id:
			continue
		var err := absf(t - beat.hit_time)
		if err > bad_window:
			continue
		if err < best_err:
			best = beat
			best_err = err
	if best != null:
		_draw.default_color = (best as CanvasItem).self_modulate
	elif _is_locked:
		# no hittable beat in window but locked — keep locked beat's color for continuity
		for beat in get_children():
			if not beat.has_method("hit") or beat.is_judged():
				continue
			if str(beat.beat_id) == _locked_id:
				_draw.default_color = (beat as CanvasItem).self_modulate
				break


func _flash_clicked() -> void:
	if _flash_tween:
		_flash_tween.kill()

	click = true
	beat_receptor.hide()
	beat_receptor_clicked.show()

	_flash_tween = create_tween()
	_flash_tween.tween_interval(FLASH_DURATION)
	_flash_tween.tween_callback(
		func():
			beat_receptor_clicked.hide()
			beat_receptor.show()
			click = false
	)


func _on_draw_draw_ended() -> void:
	# --- unlock note lock (L123-L124) ---
	_is_locked = false
	_locked_id = ""
