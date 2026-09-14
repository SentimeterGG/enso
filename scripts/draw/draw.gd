# draw.gd — Player drawing input handler (Line2D): creates smoothed, fading stroke
# lines on fire press/drag/release, tracks sharp direction changes for rhythm
# input, and on release either guesses the shape or scores accuracy via the
# GestureRecognizer against the target shape.
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
	emit_signal("draw_ended")
	drawing = false
	if current_line == null:
		return
	var line := current_line
	#TODO change to target data
	if guess_mode:
		var shape: String = recognizer.guess(line.points)
		emit_signal("guessed_shape", shape)
	else:
		var shape_accuracy := recognizer.compare(line.points, target_shape.points)
		emit_signal("shape_accuracy_ready", shape_accuracy)
	current_line = null
	var tween := owner.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, fade_duration)
	tween.finished.connect(line.queue_free)


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
	if event.is_action_pressed("fire"):
		begin(get_global_mouse_position())
	elif event.is_action_released("fire"):
		end()
	elif event is InputEventMouseMotion:
		motion(event.position)
