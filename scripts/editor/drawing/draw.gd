extends Line2D

signal shape_accuracy_ready(accuracy: float)
signal draw_started
signal draw_ended
signal draw_direction_changes
signal guessed_shape(shape: String)

const RECOGNIZER_CONFIG := [
	&"tolerance",
	&"line_tolerance",
	&"complex_tolerance",
	&"open_tolerance",
	&"open_unit_tolerance",
	&"open_tail_trim",
	&"enable_unit_square_open",
	&"open_structural_weight",
	&"open_rotation_reject",
	&"open_rot_exact_dist",
	&"open_rot_moderate_dist",
	&"open_rot_struct_gate",
	&"open_rot_angle_deg",
	&"open_turn_tol_deg",
	&"open_corner_tol",
	&"rotation_tolerance_deg",
	&"structural_weight",
	&"line_angle_tol_deg",
	&"straight_turn_tol_deg",
	&"sample_points",
	&"line_flatness",
	&"closed_path_threshold",
	&"near_closed_gap",
	&"guess_score_threshold",
	&"guess_early_exit_score",
	&"unfinished_gap",
	&"enable_rotation_alignment",
	&"corner_angle",
	&"corner_weight",
	&"radial_bins",
	&"peak_min_separation",
	&"min_peak_depth",
	&"peak_depth_tolerance",
	&"circle_distinct",
]

@export var weight := 0.2
@export var fade_duration := 0.3
@export var min_direction_sample := 5.0
@export var direction_threshold_degrees := 60.0
@export var guess_mode := false
@export var recognizer: GestureRecognizer
@export var target_shape: Line2D

var drawing := false
var can_draw := false
var current_line: Line2D
var smooth_pos := Vector2.ZERO
var previous_mouse_position := Vector2.ZERO
var previous_mouse_direction := Vector2.ZERO

var _stroke_seq := 0
var _dead := false

@onready var draw_particles: GPUParticles2D = %DrawParticles


func _ready() -> void:
	end()


func _process(_delta: float) -> void:
	draw_particles.position = get_global_mouse_position()
	if drawing and not Input.is_action_pressed("fire"):
		cancel()


func _input(event: InputEvent) -> void:
	if not can_draw:
		return
	if event.is_action_pressed("fire") and not drawing:
		if event is InputEventMouseButton and _pointer_over_button():
			return
		begin(get_global_mouse_position())
		VolumePopup.get_child(0).call_deferred("_hide_popup")
	elif event.is_action_released("fire") and drawing:
		end()
	elif event is InputEventMouseMotion:
		_motion(event.position)


func _pointer_over_button() -> bool:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control is BaseButton and not (control as BaseButton).disabled:
			return true
		control = control.get_parent_control()
	return false


func start() -> void:
	can_draw = true


func stop() -> void:
	can_draw = false
	end()


func begin(global_mouse_pos: Vector2) -> void:
	drawing = true

	_reset_direction_tracking(global_mouse_pos)
	_create_line(global_mouse_pos)
	_start_drawing_effects()

	draw_started.emit()


func _create_line(pos: Vector2) -> void:
	current_line = Line2D.new()

	current_line.width = width
	current_line.default_color = default_color
	current_line.begin_cap_mode = begin_cap_mode
	current_line.end_cap_mode = end_cap_mode
	current_line.joint_mode = joint_mode

	add_child(current_line)

	smooth_pos = pos
	current_line.add_point(smooth_pos)


func _start_drawing_effects() -> void:
	%EnsoHold.play()
	%DrawParticles.emitting = true


func _stop_drawing_effects() -> void:
	%EnsoHold.stop()
	%DrawParticles.emitting = false


func end() -> void:
	_stop_drawing_effects()
	drawing = false

	if current_line == null:
		draw_ended.emit()
		return

	var line := current_line
	current_line = null

	_fade_line(line)
	Global.call_if_exists(recognizer, "apply_chart_od", [Global.current_chart])

	_stroke_seq += 1
	var stroke := _stroke_seq

	_submit_recognition(line, stroke)


func cancel() -> void:
	if not drawing and current_line == null:
		return

	_stop_drawing_effects()
	drawing = false

	if current_line != null:
		current_line.queue_free()
		current_line = null


func _submit_recognition(line: Line2D, stroke: int):
	if recognizer == null:
		_emit_empty_result()
		return

	var player_pts := line.points.duplicate()
	var cfg := _snapshot_config()

	if guess_mode:
		_submit_guess(player_pts, cfg, stroke)
	else:
		_submit_comparison(player_pts, cfg, stroke)


func _emit_empty_result():
	if guess_mode:
		guessed_shape.emit("other")
	else:
		shape_accuracy_ready.emit(0.0)

	draw_ended.emit()


func _submit_guess(player_pts: PackedVector2Array, cfg: Dictionary, stroke: int) -> void:
	var callback := Callable(self, "_on_guess_done")

	WorkerThreadPool.add_task(
		Callable(self, "_thread_guess").bind(player_pts, cfg, stroke, callback),
		true,
		"draw-guess-%d" % stroke,
	)


func _submit_comparison(player_pts: PackedVector2Array, cfg: Dictionary, stroke: int) -> void:
	var target_pts := PackedVector2Array()

	if target_shape != null:
		target_pts = target_shape.points.duplicate()

	var callback := Callable(self, "_on_compare_done")

	WorkerThreadPool.add_task(
		Callable(self, "_thread_compare").bind(player_pts, target_pts, cfg, stroke, callback),
		true,
		"draw-compare-%d" % stroke,
	)


func _reset_direction_tracking(pos: Vector2) -> void:
	previous_mouse_position = pos
	previous_mouse_direction = Vector2.ZERO


func _thread_compare(
	player_pts: PackedVector2Array,
	target_pts: PackedVector2Array,
	cfg: Dictionary,
	stroke: int,
	cb: Callable,
) -> void:
	var worker := GestureRecognizer.new()
	_apply_config(worker, cfg)
	var acc := 0.0
	if player_pts.size() >= 2 and target_pts.size() >= 2:
		acc = worker.compare(player_pts, target_pts)
	if cb.is_valid():
		cb.call_deferred(stroke, acc)


func _thread_guess(
	player_pts: PackedVector2Array,
	cfg: Dictionary,
	stroke: int,
	cb: Callable,
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
	shape_accuracy_ready.emit(acc)
	draw_ended.emit()


func _on_guess_done(_stroke: int, shape: String) -> void:
	if _dead:
		return
	guessed_shape.emit(shape)
	draw_ended.emit()


func _fade_line(line: Line2D) -> void:
	var tween_owner := owner if owner != null else self
	var tween := tween_owner.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, fade_duration)
	tween.finished.connect(line.queue_free)


func _snapshot_config() -> Dictionary:
	var config := { }

	for property: StringName in RECOGNIZER_CONFIG:
		config[property] = recognizer.get(property)

	return config


static func _apply_config(worker: GestureRecognizer, config: Dictionary) -> void:
	for property: StringName in RECOGNIZER_CONFIG:
		if config.has(property):
			worker.set(property, config[property])

	worker.debug_enabled = false
	worker.debug_print_on_compare = false


func _motion(pos: Vector2) -> void:
	if not drawing or current_line == null:
		return
	smooth_pos = smooth_pos.lerp(pos, weight)
	if current_line.points.is_empty() or current_line.points[-1].distance_to(smooth_pos) > 2.0:
		current_line.add_point(smooth_pos)
	_track_direction(pos)


func _track_direction(pos: Vector2) -> void:
	var movement := pos - previous_mouse_position
	previous_mouse_position = pos

	if movement.length() < min_direction_sample:
		return

	var new_direction := movement.normalized()

	if previous_mouse_direction != Vector2.ZERO:
		var angle := rad_to_deg(previous_mouse_direction.angle_to(new_direction))

		if absf(angle) >= direction_threshold_degrees:
			draw_direction_changes.emit()

	previous_mouse_direction = new_direction


func _exit_tree() -> void:
	_dead = true
