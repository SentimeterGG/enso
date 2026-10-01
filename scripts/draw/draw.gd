# draw.gd — Player drawing input handler (Line2D): creates smoothed, fading stroke
# lines on fire press/drag/release, tracks sharp direction changes for rhythm
# input, and on release either guesses the shape or scores accuracy via the
# GestureRecognizer against the target shape.
# Scoring runs on a WorkerThreadPool thread so the main thread never hitches;
# result signals are emitted deferred, with draw_ended always AFTER the result.
# RETURN: shape accuracy, guessed shape name and stroke signals
extends Line2D

@export var weight := 0.2
@export var fade_duration := 0.3
@export var min_direction_sample := 5.0
@export var direction_threshold_degrees := 60.0
@export var guess_mode := false

var drawing := false
var can_draw := false
var current_line: Line2D
var smooth_pos := Vector2.ZERO
var previous_mouse_position := Vector2.ZERO
var mouse_direction := Vector2.ZERO
@export var recognizer: GestureRecognizer
@export var target_shape: Line2D

# Monotonic stroke id so late worker results can be matched to their stroke.
var _stroke_seq := 0
# Set in _exit_tree so in-flight workers drop their results instead of
# emitting into a dead scene.
var _dead := false

signal shape_accuracy_ready(accuracy: float)
signal draw_started
signal draw_ended
signal draw_direction_changes
signal guessed_shape(shape: String)


func start() -> void:
	can_draw = true


func stop() -> void:
	can_draw = false
	end()


func begin(global_mouse_pos: Vector2) -> void:
	emit_signal("draw_started")
	drawing = true
	previous_mouse_position = global_mouse_pos
	mouse_direction = Vector2.ZERO
	current_line = Line2D.new()
	current_line.width = self.width
	current_line.default_color = self.default_color
	current_line.begin_cap_mode = begin_cap_mode
	current_line.end_cap_mode = end_cap_mode
	current_line.joint_mode = joint_mode
	add_child(current_line)
	smooth_pos = global_mouse_pos
	current_line.add_point(smooth_pos)


func end() -> void:
	drawing = false
	if current_line == null:
		emit_signal("draw_ended")
		return
	var line := current_line
	current_line = null
	_fade_line(line)
	if recognizer != null and recognizer.has_method("apply_chart_od"):
		recognizer.apply_chart_od(Global.current_chart)
	_stroke_seq += 1
	var stroke := _stroke_seq
	if guess_mode:
		if recognizer == null:
			emit_signal("guessed_shape", "other")
			emit_signal("draw_ended")
			return
		var player_pts := line.points.duplicate()
		var cfg := _snapshot_config()
		var cb := Callable(self, "_on_guess_done")
		WorkerThreadPool.add_task(
			Callable(self, "_thread_guess").bind(player_pts, cfg, stroke, cb),
			true,
			"draw-guess-%d" % stroke
		)
	else:
		if recognizer == null:
			emit_signal("shape_accuracy_ready", 0.0)
			emit_signal("draw_ended")
			return
		var player_pts := line.points.duplicate()
		var target_pts := PackedVector2Array()
		if target_shape != null:
			target_pts = target_shape.points.duplicate()
		var cfg := _snapshot_config()
		var cb := Callable(self, "_on_compare_done")
		WorkerThreadPool.add_task(
			Callable(self, "_thread_compare").bind(player_pts, target_pts, cfg, stroke, cb),
			true,
			"draw-compare-%d" % stroke
		)


func _thread_compare(
	player_pts: PackedVector2Array,
	target_pts: PackedVector2Array,
	cfg: Dictionary,
	stroke: int,
	cb: Callable
) -> void:
	var worker := GestureRecognizer.new()
	_apply_config(worker, cfg)
	var acc := 0.0
	if player_pts.size() >= 2 and target_pts.size() >= 2:
		acc = worker.compare(player_pts, target_pts)
	if cb.is_valid():
		cb.call_deferred(stroke, acc)


func _thread_guess(
	player_pts: PackedVector2Array, cfg: Dictionary, stroke: int, cb: Callable
) -> void:
	var worker := GestureRecognizer.new()
	_apply_config(worker, cfg)
	var shape := "other"
	if player_pts.size() >= 2:
		shape = worker.guess(player_pts)
	if cb.is_valid():
		cb.call_deferred(stroke, shape)


func _on_compare_done(_stroke: int, acc: float) -> void:
	if _dead:
		return
	# accuracy_manager expects accuracy BEFORE draw_ended.
	emit_signal("shape_accuracy_ready", acc)
	emit_signal("draw_ended")


func _on_guess_done(_stroke: int, shape: String) -> void:
	if _dead:
		return
	emit_signal("guessed_shape", shape)

	emit_signal("draw_ended")


# --- Helpers ---


func _fade_line(line: Line2D) -> void:
	var tween_owner := owner if owner != null else self
	var tween := tween_owner.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, fade_duration)
	tween.finished.connect(line.queue_free)


# Copies every tuning value that influences scoring so the worker can use a
# private GestureRecognizer instance. Must be called on the main thread while
# `recognizer` is valid. The worker never reads the shared recognizer.
func _snapshot_config() -> Dictionary:
	var r := recognizer
	return {
		"tolerance": r.tolerance,
		"line_tolerance": r.line_tolerance,
		"complex_tolerance": r.complex_tolerance,
		"open_tolerance": r.open_tolerance,
		"open_unit_tolerance": r.open_unit_tolerance,
		"open_tail_trim": r.open_tail_trim,
		"enable_unit_square_open": r.enable_unit_square_open,
		"open_structural_weight": r.open_structural_weight,
		"open_rotation_reject": r.open_rotation_reject,
		"open_rot_exact_dist": r.open_rot_exact_dist,
		"open_rot_moderate_dist": r.open_rot_moderate_dist,
		"open_rot_struct_gate": r.open_rot_struct_gate,
		"open_rot_angle_deg": r.open_rot_angle_deg,
		"open_turn_tol_deg": r.open_turn_tol_deg,
		"open_corner_tol": r.open_corner_tol,
		"rotation_tolerance_deg": r.rotation_tolerance_deg,
		"structural_weight": r.structural_weight,
		"line_angle_tol_deg": r.line_angle_tol_deg,
		"straight_turn_tol_deg": r.straight_turn_tol_deg,
		"sample_points": r.sample_points,
		"line_flatness": r.line_flatness,
		"closed_path_threshold": r.closed_path_threshold,
		"near_closed_gap": r.near_closed_gap,
		"guess_score_threshold": r.guess_score_threshold,
		"guess_early_exit_score": r.guess_early_exit_score,
		"unfinished_gap": r.unfinished_gap,
		"enable_rotation_alignment": r.enable_rotation_alignment,
		"corner_angle": r.corner_angle,
		"corner_weight": r.corner_weight,
		"radial_bins": r.radial_bins,
		"peak_min_separation": r.peak_min_separation,
		"min_peak_depth": r.min_peak_depth,
		"peak_depth_tolerance": r.peak_depth_tolerance,
		"circle_distinct": r.circle_distinct,
	}


static func _apply_config(worker: GestureRecognizer, cfg: Dictionary) -> void:
	worker.tolerance = float(cfg.get("tolerance", worker.tolerance))
	worker.line_tolerance = float(cfg.get("line_tolerance", worker.line_tolerance))
	worker.complex_tolerance = float(cfg.get("complex_tolerance", worker.complex_tolerance))
	worker.open_tolerance = float(cfg.get("open_tolerance", worker.open_tolerance))
	worker.open_unit_tolerance = float(cfg.get("open_unit_tolerance", worker.open_unit_tolerance))
	worker.open_tail_trim = float(cfg.get("open_tail_trim", worker.open_tail_trim))
	worker.enable_unit_square_open = bool(
		cfg.get("enable_unit_square_open", worker.enable_unit_square_open)
	)
	worker.open_structural_weight = float(
		cfg.get("open_structural_weight", worker.open_structural_weight)
	)
	worker.open_rotation_reject = bool(cfg.get("open_rotation_reject", worker.open_rotation_reject))
	worker.open_rot_exact_dist = float(cfg.get("open_rot_exact_dist", worker.open_rot_exact_dist))
	worker.open_rot_moderate_dist = float(
		cfg.get("open_rot_moderate_dist", worker.open_rot_moderate_dist)
	)
	worker.open_rot_struct_gate = float(
		cfg.get("open_rot_struct_gate", worker.open_rot_struct_gate)
	)
	worker.open_rot_angle_deg = float(cfg.get("open_rot_angle_deg", worker.open_rot_angle_deg))
	worker.open_turn_tol_deg = float(cfg.get("open_turn_tol_deg", worker.open_turn_tol_deg))
	worker.open_corner_tol = float(cfg.get("open_corner_tol", worker.open_corner_tol))
	worker.rotation_tolerance_deg = float(
		cfg.get("rotation_tolerance_deg", worker.rotation_tolerance_deg)
	)
	worker.structural_weight = float(cfg.get("structural_weight", worker.structural_weight))
	worker.line_angle_tol_deg = float(cfg.get("line_angle_tol_deg", worker.line_angle_tol_deg))
	worker.straight_turn_tol_deg = float(
		cfg.get("straight_turn_tol_deg", worker.straight_turn_tol_deg)
	)
	worker.sample_points = int(cfg.get("sample_points", worker.sample_points))
	worker.line_flatness = float(cfg.get("line_flatness", worker.line_flatness))
	worker.closed_path_threshold = float(
		cfg.get("closed_path_threshold", worker.closed_path_threshold)
	)
	worker.near_closed_gap = float(cfg.get("near_closed_gap", worker.near_closed_gap))
	worker.guess_score_threshold = float(
		cfg.get("guess_score_threshold", worker.guess_score_threshold)
	)
	worker.guess_early_exit_score = float(
		cfg.get("guess_early_exit_score", worker.guess_early_exit_score)
	)
	worker.unfinished_gap = float(cfg.get("unfinished_gap", worker.unfinished_gap))
	worker.enable_rotation_alignment = bool(
		cfg.get("enable_rotation_alignment", worker.enable_rotation_alignment)
	)
	worker.corner_angle = float(cfg.get("corner_angle", worker.corner_angle))
	worker.corner_weight = float(cfg.get("corner_weight", worker.corner_weight))
	worker.radial_bins = int(cfg.get("radial_bins", worker.radial_bins))
	worker.peak_min_separation = int(cfg.get("peak_min_separation", worker.peak_min_separation))
	worker.min_peak_depth = float(cfg.get("min_peak_depth", worker.min_peak_depth))
	worker.peak_depth_tolerance = float(
		cfg.get("peak_depth_tolerance", worker.peak_depth_tolerance)
	)
	worker.circle_distinct = float(cfg.get("circle_distinct", worker.circle_distinct))
	# Debug captures mutate shared arrays; workers never write them.
	worker.debug_enabled = false
	worker.debug_print_on_compare = false


func motion(pos: Vector2) -> void:
	if not drawing or current_line == null:
		return
	smooth_pos = smooth_pos.lerp(pos, weight)
	if current_line.points.is_empty() or current_line.points[-1].distance_to(smooth_pos) > 2.0:
		current_line.add_point(smooth_pos)
	_track_direction(pos)


func _track_direction(pos: Vector2) -> void:
	var move := pos - previous_mouse_position
	previous_mouse_position = pos
	if move.length() < min_direction_sample:
		return
	if mouse_direction == Vector2.ZERO:
		mouse_direction = move.normalized()
		return
	if absf(rad_to_deg(mouse_direction.angle_to(move))) >= direction_threshold_degrees:
		mouse_direction = move.normalized()
		emit_signal("draw_direction_changes")


func _input(event: InputEvent) -> void:
	if not can_draw:
		return
	if Input.is_action_just_pressed("fire") and not drawing:
		begin(get_global_mouse_position())
		VolumePopup.hide_pop_up()
	elif Input.is_action_just_released("fire") and drawing:
		end()
	elif event is InputEventMouseMotion:
		motion(event.position)


func _exit_tree() -> void:
	_dead = true
	
