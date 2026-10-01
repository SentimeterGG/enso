extends Sprite2D
@onready var beat_receptor_clicked: Sprite2D = $beat_receptor_clicked
var FLASH_DURATION = 0.1
var _flash_time_left: float = 0.0

@onready var _judge: Node = %judge_spawner
@onready var _score: ScoreManager = %accuracy_manager
@onready var _column: Control = %beat_column
@onready var _target_shape: Line2D = %target_shape
@onready var _draw: Line2D = %draw
var last_beat_id = ""


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


## Draw input happened: judge the nearest unjudged beat within the OD window.
func try_hit() -> void:
	if not BgMusic.playing:
		return
	var music_time: float = BgMusic.get_playback_position()
	var window_sec := HitResult.bad_window_ms(_od()) / 1000.0
	var best: Node = null
	var best_err := window_sec + 1.0
	for child in _column.get_children():
		if not child.has_method("is_judged") or child.call("is_judged"):
			continue
		var ht := float(child.get("hit_time"))
		var err: float = music_time - ht
		if absf(err) <= window_sec and absf(err) < absf(best_err):
			best = child
			best_err = err
	if best != null:
		# locking if beat_id different
		if last_beat_id != "" and last_beat_id != best.get("beat_id"):
			best.call("vibrate")
		else:
			var id = str(best.get("beat_id"))
			last_beat_id = id
			best.call("hit")
			_target_shape.change(Global.current_chart.shape_points_by_id(id))
			_judge.call("_on_beat_column_beat_hit", best_err, str(best.get("beat_id")))
	_flash()


## Auto-miss beats that scrolled past the receptor unhit, and free spent ones.
func _sweep_misses() -> void:
	if _column == null or _judge == null:
		return
	if not BgMusic.playing:
		return
	var music_time: float = BgMusic.get_playback_position()
	var window_sec := HitResult.bad_window_ms(_od()) / 1000.0
	for child in _column.get_children():
		if not is_instance_valid(child):
			continue
		if child.has_method("is_awaiting_free") and bool(child.call("is_awaiting_free")):
			if child.has_method("is_offscreen") and bool(child.call("is_offscreen")):
				child.queue_free()
			continue
		if not child.has_method("is_judged") or bool(child.call("is_judged")):
			continue
		var err: float = music_time - float(child.get("hit_time"))
		if err > window_sec:
			child.call("miss")
			_judge.call("_on_beat_column_beat_hit", err, str(child.get("beat_id")))


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
		# set the color to the last_beat point color
		var col := Color.WHITE
		if Global.current_chart != null:
			col = Global.current_chart.shape_colors.get(last_beat_id, Color.WHITE)
		_draw.get_child(0).modulate = col
	last_beat_id = ""
