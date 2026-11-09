extends Sprite2D
@onready var beat_receptor_clicked: Sprite2D = $beat_receptor_clicked
var FLASH_DURATION = 0.1
var _flash_time_left: float = 0.0

@onready var _judge: Node = %judge_spawner
@onready var _score: ScoreManager = %accuracy_manager
@onready var _column: Control = %beat_column
@onready var _target_shape: Line2D = %target_shape
@onready var _draw: Line2D = %draw
var note_splash_scene = preload("res://scenes/ui/splash_note.tscn")
var last_beat_id = ""

var _pool: Array = []
var _cursor: int = 0
var _pool_ready: bool = false
var _pending_free: Array = []


func _ready() -> void:
	beat_receptor_clicked.texture = SkinManager.beat_receptor_clicked
	texture = SkinManager.beat_receptor
	beat_receptor_clicked.visible = false


func _process(delta: float) -> void:
	if beat_receptor_clicked.visible:
		_flash_time_left -= delta
		if _flash_time_left <= 0.0:
			beat_receptor_clicked.visible = false
	_sweep_misses()


func _on_draw_draw_started() -> void:
	_draw.modulate = Color.WHITE
	try_hit()


func _on_draw_draw_direction_changes() -> void:
	try_hit()


func _ensure_pool() -> void:
	if _pool_ready:
		return
	if _column == null or _column.get_child_count() == 0:
		return
	_pool_ready = true
	_pool.clear()
	for child in _column.get_children():
		if child.has_method("is_judged") and child.has_method("hit"):
			_pool.append(child)
	_pool.sort_custom(
		func(a, b):
			return float(a.hit_time) < float(b.hit_time),
	)
	_cursor = 0


func _advance_cursor(music_time: float, window_sec: float) -> void:
	_ensure_pool()
	var n := _pool.size()
	var i := _cursor
	while i < n:
		var node = _pool[i]
		if not is_instance_valid(node):
			i += 1
			continue
		if node.has_method("is_judged") and bool(node.call("is_judged")):
			i += 1
			continue
		var ht := float(node.get("hit_time"))
		var err := music_time - ht
		if err > window_sec:
			node.call("miss")
			_pending_free.append(node)
			_judge.call("_on_beat_column_beat_hit", err, str(node.get("beat_id")))
			i += 1
			continue
		break
	_cursor = i


func try_hit() -> void:
	var note_splash = note_splash_scene.instantiate()
	if not BgMusic.playing:
		return
	var music_time: float = BgMusic.get_playback_position()
	var window_sec := HitResult.bad_window_ms(_od()) / 1000.0
	_advance_cursor(music_time, window_sec)

	var best: Node = null
	var best_err := window_sec + 1.0
	var i := _cursor
	var n := _pool.size()
	while i < n:
		var node = _pool[i]
		if not is_instance_valid(node):
			i += 1
			continue
		if node.has_method("is_judged") and bool(node.call("is_judged")):
			i += 1
			continue
		var ht := float(node.get("hit_time"))
		if ht > music_time + window_sec:
			break
		var err: float = music_time - ht
		if absf(err) <= window_sec and absf(err) < absf(best_err):
			best = node
			best_err = err
		i += 1

	if best != null:
		if last_beat_id != "" and last_beat_id != best.get("beat_id"):
			best.call("vibrate")
		else:
			var id = str(best.get("beat_id"))
			last_beat_id = id
			best.call("hit")
			add_child(note_splash)
			_target_shape.change(Global.current_chart.shape_points_by_id(id))
			_judge.call("_on_beat_column_beat_hit", best_err, str(best.get("beat_id")))
	_flash()


func _sweep_misses() -> void:
	if _column == null or _judge == null:
		return
	if not BgMusic.playing:
		return
	var music_time: float = BgMusic.get_playback_position()
	var window_sec := HitResult.bad_window_ms(_od()) / 1000.0
	_advance_cursor(music_time, window_sec)

	var i := 0
	while i < _pending_free.size():
		var node = _pending_free[i]
		if not is_instance_valid(node):
			_pending_free.remove_at(i)
			continue
		if node.has_method("is_offscreen") and bool(node.call("is_offscreen")):
			node.queue_free()
			_pending_free.remove_at(i)
			continue
		i += 1


func _flash() -> void:
	beat_receptor_clicked.visible = true
	_flash_time_left = FLASH_DURATION


func _od() -> float:
	if _score != null:
		return _score.od
	if Global.current_chart != null:
		return Global.current_chart.get_od()
	return 0.0


func _on_draw_shape_accuracy_ready(accuracy: float) -> void:
	if _score != null and accuracy > _score.DRAW_BAD_ACCURACY:
		var col := Color.WHITE
		if Global.current_chart != null:
			col = Global.current_chart.shape_colors.get(last_beat_id, Color.WHITE)
		_draw.get_child(2).modulate = col
	last_beat_id = ""
