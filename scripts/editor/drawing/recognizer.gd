class_name GestureRecognizer
extends Resource


@export_group("Base Tolerance")
@export_range(0.01, 0.5, 0.01) var base_tolerance: float = 0.3

@export_range(0.01, 0.5, 0.01) var base_line_tolerance: float = 0.35

@export_range(0.01, 0.5, 0.01) var base_complex_tolerance: float = 0.46

@export_range(0.01, 0.5, 0.01) var base_open_tolerance: float = 0.38

@export_range(0.1, 1.0, 0.01) var base_open_unit_tolerance: float = 0.7

@export_range(0.0, 0.2, 0.01) var base_open_tail_trim: float = 0.08

var tolerance: float = 0.3
var line_tolerance: float = 0.35
var complex_tolerance: float = 0.46
var open_tolerance: float = 0.38
var open_unit_tolerance: float = 0.7
var open_tail_trim: float = 0.08

@export_group("Matching Behavior")
@export var enable_unit_square_open: bool = true

@export_range(0.0, 1.0, 0.05) var open_structural_weight: float = 0.65

@export var open_rotation_reject: bool = true

@export_group("Open Rotation Rejection")
@export_range(0.01, 0.3, 0.01) var open_rot_exact_dist: float = 0.06
@export_range(0.05, 0.5, 0.01) var open_rot_moderate_dist: float = 0.18
@export_range(0.0, 100.0, 5.0) var open_rot_struct_gate: float = 60.0
@export_range(15.0, 90.0, 5.0) var open_rot_angle_deg: float = 45.0

@export_range(5.0, 60.0, 1.0) var open_turn_tol_deg: float = 45.0

@export_range(0.5, 3.0, 0.1) var open_corner_tol: float = 2.5

@export_range(0.0, 45.0, 1.0) var rotation_tolerance_deg: float = 15.0

@export_range(0.0, 1.0, 0.05) var structural_weight: float = 0.5

@export_group("Difficulty (overall_difficulty 1-10)")
@export_range(1.0, 10.0, 1.0) var base_od: float = 5.0
@export_range(0.02, 0.2, 0.01) var od_step_scale: float = 0.1
@export_range(1.0, 10.0, 1.0) var od_min: float = 1.0
@export_range(1.0, 10.0, 1.0) var od_max: float = 10.0
@export_range(1.0, 2.0, 0.05) var od_max_scale: float = 1.1
@export_range(0.3, 1.0, 0.05) var od_min_scale: float = 0.5

@export_group("Draw Quality Bands (0-100)")
@export_range(0.0, 100.0, 1.0) var bad_threshold: float = 60.0
@export_range(0.0, 100.0, 1.0) var good_threshold: float = 75.0
@export_range(0.0, 100.0, 1.0) var perfect_threshold: float = 90.0

@export_group("Line Orientation")
@export_range(10.0, 45.0, 1.0) var line_angle_tol_deg: float = 25.0
@export_range(5.0, 30.0, 1.0) var straight_turn_tol_deg: float = 12.0

@export_group("Resampling & Preprocessing")
@export var sample_points: int = 64

@export_range(0.05, 0.5, 0.01) var line_flatness: float = 0.3

@export_range(0.05, 0.5, 0.01) var closed_path_threshold: float = 0.25

@export_range(0.25, 1.0, 0.05) var near_closed_gap: float = 0.5

@export_range(10.0, 90.0, 1.0) var guess_score_threshold: float = 50.0

@export_range(50.0, 100.0, 1.0) var guess_early_exit_score: float = 92.0

@export_range(0.5, 1.0, 0.05) var unfinished_gap: float = 0.75

@export var enable_rotation_alignment: bool = false

@export_group("Feature & Corner Detection")
@export_range(0.1, 2.0, 0.01) var corner_angle: float = 0.9599

@export_range(0.0, 5.0, 0.1) var corner_weight: float = 1.0

@export_group("Radial Signature")
@export var radial_bins: int = 72

@export var peak_min_separation: int = 6

@export_range(0.01, 0.5, 0.01) var min_peak_depth: float = 0.08

@export_range(0.01, 0.5, 0.01) var peak_depth_tolerance: float = 0.15

@export_range(0.1, 1.0, 0.05) var circle_distinct: float = 0.3

@export_group("Debug Capture")
@export var debug_enabled: bool = false
@export var debug_print_on_compare: bool = false
@export_range(1, 200, 1) var debug_max_captures: int = 20

var debug_last: Dictionary = { }
var debug_captures: Array[Dictionary] = []

var _unit_circle_cache: PackedVector2Array = PackedVector2Array()

var _template_cache: Dictionary = { }
var _template_names: Array[String] = []
var _templates_ready := false
var _suppress_rotation_penalty := false


class TargetData:
	var raw_points: PackedVector2Array
	var normalized_points: PackedVector2Array
	var is_line: bool
	var circle_dist: float
	var corners: Array[float]
	var rev_points: PackedVector2Array
	var rev_corners: Array[float]
	var radial_peaks: Array[Vector3]
	var corner_count: int
	var is_closed: bool
	var max_radius: float
	var total_turn_deg: float
	var open_corner_count: int
	var unit_points: PackedVector2Array
	var unit_rev_points: PackedVector2Array
	var unit_max_radius: float


	func _init(points: PackedVector2Array, recognizer: GestureRecognizer) -> void:
		raw_points = points
		normalized_points = recognizer.normalize(points)
		is_line = recognizer.is_line_like(normalized_points)
		circle_dist = recognizer.circle_distance_to(normalized_points)
		corners = recognizer.corner_mask(normalized_points)
		rev_points = recognizer.reverse_points(normalized_points)
		rev_corners = recognizer.corner_mask(rev_points)
		radial_peaks = recognizer.radial_peaks(normalized_points)
		corner_count = recognizer.count_corners_from_mask(corners)
		is_closed = recognizer.is_closed_path(normalized_points)
		max_radius = recognizer.max_radius_of(normalized_points)
		total_turn_deg = recognizer._open_turn_deg(normalized_points)
		open_corner_count = recognizer._open_corner_count(normalized_points)
		unit_points = recognizer.unit_square_normalize(normalized_points)
		unit_rev_points = recognizer.reverse_points(unit_points)
		unit_max_radius = recognizer.max_radius_of(unit_points)


func create_target_data(points: PackedVector2Array) -> TargetData:
	return TargetData.new(points, self)


class PlayerData:
	var norm: PackedVector2Array
	var closed: bool
	var gap_ratio: float
	var is_line: bool
	var corner_p: Array[float]
	var peaks: Array[Vector3]
	var peaks_ready: bool
	var unit: PackedVector2Array
	var unit_ready: bool


func build_player_data(points: PackedVector2Array) -> PlayerData:
	var pd := PlayerData.new()
	pd.norm = normalize(points)
	pd.closed = is_closed_path(pd.norm)
	pd.gap_ratio = _endpoint_gap_ratio(pd.norm)
	pd.is_line = is_line_like(pd.norm)
	pd.corner_p = corner_mask(pd.norm)
	if pd.closed:
		pd.peaks = radial_peaks(pd.norm)
		pd.peaks_ready = true
	return pd



func compare(player: PackedVector2Array, target: PackedVector2Array) -> float:
	if player.size() < 2 or target.size() < 2:
		return 0.0
	var target_data := create_target_data(target)
	return compare_to_target_data(player, target_data)


func guess(points: PackedVector2Array) -> String:
	if points.size() < 2:
		return "other"
	var pd := build_player_data(points)
	if pd.is_line:
		return "line"

	var tpls := _templates()
	var names := _template_names
	var best_name := "other"
	var best_score := 0.0
	_suppress_rotation_penalty = true
	for name in names:
		var tpl: TargetData = tpls[name]
		if (
			(pd.closed and not tpl.is_closed)
			or (not pd.closed and tpl.is_closed and pd.gap_ratio >= near_closed_gap)
		):
			continue
		var score := _score_player_data(pd, tpl)
		if score > best_score:
			best_score = score
			best_name = name
			if best_score >= guess_early_exit_score:
				break
	_suppress_rotation_penalty = false
	if best_score >= guess_score_threshold:
		return best_name

	if not pd.closed and pd.gap_ratio < unfinished_gap:
		var stitched_pd := build_player_data(_virtual_close(pd.norm))
		_suppress_rotation_penalty = true
		for name in names:
			var tpl: TargetData = tpls[name]
			if not tpl.is_closed:
				continue
			var score := _score_player_data(stitched_pd, tpl)
			if score > best_score:
				best_score = score
				best_name = name
				if best_score >= guess_early_exit_score:
					break
		_suppress_rotation_penalty = false
	return best_name if best_score >= guess_score_threshold else "other"


func _templates() -> Dictionary:
	if not _templates_ready:
		for name in ["circle", "square", "triangle", "exit"]:
			_template_cache[name] = create_target_data(_template_points(name))
			_template_names.append(name)
		_templates_ready = true
	return _template_cache


func _template_points(kind: String) -> PackedVector2Array:
	match kind:
		"circle":
			var arr := PackedVector2Array()
			for i in range(sample_points):
				var a := TAU * float(i) / float(sample_points)
				arr.append(Vector2(cos(a), sin(a)))
			return arr
		"square":
			return PackedVector2Array(
				[Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]
			)
		"triangle":
			return PackedVector2Array(
				[Vector2(1, 1), Vector2(0, -1), Vector2(-1, 1), Vector2(1, 1)]
			)

		"exit":
			return PackedVector2Array(
				[Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(-1, 1)]
			)
	return PackedVector2Array()


func compare_to_target_data(player: PackedVector2Array, target: TargetData) -> float:
	if player.size() < 2 or target.normalized_points.size() < 2:
		return 0.0
	var pd := build_player_data(player)
	var debug_out := { }
	var score := _score_player_data(pd, target, debug_out)
	if debug_enabled:
		_debug_store_capture(player, pd, target, score, debug_out)
	return score


func clear_debug_captures() -> void:
	debug_captures.clear()
	debug_last = { }


func _debug_config_snapshot() -> Dictionary:
	return {
		"base_tolerance": base_tolerance,
		"base_line_tolerance": base_line_tolerance,
		"base_complex_tolerance": base_complex_tolerance,
		"base_open_tolerance": base_open_tolerance,
		"base_open_unit_tolerance": base_open_unit_tolerance,
		"base_open_tail_trim": base_open_tail_trim,
		"tolerance": tolerance,
		"line_tolerance": line_tolerance,
		"complex_tolerance": complex_tolerance,
		"open_tolerance": open_tolerance,
		"open_unit_tolerance": open_unit_tolerance,
		"open_tail_trim": open_tail_trim,
		"enable_unit_square_open": enable_unit_square_open,
		"open_structural_weight": open_structural_weight,
		"structural_weight": structural_weight,
		"open_turn_tol_deg": open_turn_tol_deg,
		"open_corner_tol": open_corner_tol,
		"rotation_tolerance_deg": rotation_tolerance_deg,
		"line_angle_tol_deg": line_angle_tol_deg,
		"straight_turn_tol_deg": straight_turn_tol_deg,
		"corner_angle": corner_angle,
		"corner_weight": corner_weight,
		"closed_path_threshold": closed_path_threshold,
		"near_closed_gap": near_closed_gap,
		"sample_points": sample_points,
		"bad_threshold": bad_threshold,
		"good_threshold": good_threshold,
		"perfect_threshold": perfect_threshold,
	}


func _debug_points_to_arrays(points: PackedVector2Array) -> Array:
	var out := []
	out.resize(points.size())
	for i in range(points.size()):
		out[i] = [points[i].x, points[i].y]
	return out


func _debug_store_capture(
	player_raw: PackedVector2Array,
	pd: PlayerData,
	target: TargetData,
	score: float,
	breakdown: Dictionary,
) -> void:
	var capture := {
		"time_utc": Time.get_datetime_string_from_system(true),
		"score": score,
		"config": _debug_config_snapshot(),
		"player_raw": _debug_points_to_arrays(player_raw),
		"player_norm": _debug_points_to_arrays(pd.norm),
		"target_raw": _debug_points_to_arrays(target.raw_points),
		"target_norm": _debug_points_to_arrays(target.normalized_points),
		"player_closed": pd.closed,
		"player_gap_ratio": pd.gap_ratio,
		"player_is_line": pd.is_line,
		"target_is_closed": target.is_closed,
		"breakdown": breakdown,
	}
	debug_last = capture
	debug_captures.append(capture)
	while debug_captures.size() > maxi(debug_max_captures, 1):
		debug_captures.pop_front()
	if debug_print_on_compare:
		print(
			(
				"GestureRecognizer compare: score=%.1f player=%d target=%d dist=%s"
				% [
					score,
					player_raw.size(),
					target.raw_points.size(),
					str(breakdown.get("distance", -1.0)),
				]
			)
		)


func save_debug_captures(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(debug_captures, "\t"))
	f.close()
	return OK



func tolerance_scale_for_od(od: float) -> float:
	var c := clampf(od, od_min, od_max)
	return clampf(1.0 + (base_od - c) * od_step_scale, od_min_scale, od_max_scale)


func apply_overall_difficulty(od: float) -> float:
	var s := tolerance_scale_for_od(od)
	tolerance = base_tolerance * s
	line_tolerance = base_line_tolerance * s
	complex_tolerance = base_complex_tolerance * s
	open_tolerance = base_open_tolerance * s
	open_unit_tolerance = base_open_unit_tolerance * s
	open_tail_trim = clampf(base_open_tail_trim * s, 0.0, 0.2)
	return s


static func od_from_chart(chart: ChartData) -> float:
	if chart == null:
		return 5.0
	var raw := 5.0
	if not chart.metadata.is_empty() and chart.metadata.has("overall_difficulty"):
		raw = float(str(chart.metadata["overall_difficulty"]))
	elif chart.has_method("get_od"):
		raw = float(chart.call("get_od")) * 1000.0
	return clampf(raw, 1.0, 10.0)


func apply_chart_od(chart: ChartData) -> float:
	return apply_overall_difficulty(GestureRecognizer.od_from_chart(chart))


func compare_with_od(player: PackedVector2Array, target: PackedVector2Array, od: float) -> float:
	apply_overall_difficulty(od)
	return compare(player, target)


func quality_of(score: float) -> String:
	if score >= perfect_threshold:
		return "perfect"
	if score >= good_threshold:
		return "good"
	if score >= bad_threshold:
		return "sloppy"
	return "bad"


func is_pass(score: float) -> bool:
	return score >= bad_threshold



func _is_straight(points: PackedVector2Array) -> bool:
	if points.size() < 2:
		return false
	if is_closed_path(points):
		return false
	return _open_turn_deg(points) < straight_turn_tol_deg


func _line_angle(points: PackedVector2Array) -> float:
	if points.size() < 2:
		return 0.0
	var d := points[points.size() - 1] - points[0]
	if d.length() < 1.0e-6:
		return 0.0
	return d.angle()


func _line_orientation_factor(
	player_norm: PackedVector2Array,
	target_norm: PackedVector2Array,
) -> float:
	var diff := absf(
		wrapf(_line_angle(player_norm) - _line_angle(target_norm), -PI / 2.0, PI / 2.0)
	)
	return exp(-pow(rad_to_deg(diff) / line_angle_tol_deg, 2.0))


func _score_player_data(pd: PlayerData, target: TargetData, debug_out: Dictionary = { }) -> float:
	if target.normalized_points.size() < 2:
		return 0.0

	var player_closed := pd.closed
	var debug := debug_enabled

	if player_closed != target.is_closed:
		if target.is_closed and pd.gap_ratio < near_closed_gap:
			player_closed = true
		else:
			if debug:
				debug_out["topology_mismatch"] = true
				debug_out["player_closed"] = pd.closed
				debug_out["score"] = 0.0
			return 0.0
	if player_closed and not pd.peaks_ready:
		pd.peaks = radial_peaks(pd.norm)
		pd.peaks_ready = true

	var structural: float
	var effective_tolerance: float
	var distance := 1.0e9
	var unit_search_dist := -1.0
	if not player_closed:
		structural = _open_structural(pd.norm, target)
		if pd.is_line and target.is_line:
			distance = _rotation_search(pd.norm, target, pd.corner_p)[0]
			effective_tolerance = line_tolerance
		else:
			if enable_unit_square_open:
				if not pd.unit_ready:
					pd.unit = unit_square_normalize(pd.norm)
					pd.unit_ready = true
				var unit_search := _unit_rotation_search(
					pd.norm,
					target,
					-1.0,
					pd.corner_p,
					pd.unit,
				)
				distance = unit_search[0]
				unit_search_dist = distance # Store for step 2
				effective_tolerance = open_unit_tolerance
			else:
				distance = _rotation_search(pd.norm, target, pd.corner_p)[0]
				effective_tolerance = open_tolerance
	else:
		structural = structural_score_fast(pd.norm, target, pd.peaks, pd.corner_p)
		distance = _rotation_search(pd.norm, target, pd.corner_p)[0]
		if target.circle_dist > circle_distinct:
			effective_tolerance = complex_tolerance
		else:
			effective_tolerance = tolerance

	var positional := 100.0 * exp(-pow(distance / effective_tolerance, 2.0))

	var weight := open_structural_weight if not player_closed else structural_weight
	var score := lerpf(positional, structural, weight)

	if player_closed and target.is_closed:
		if pd.peaks.is_empty() and target.radial_peaks.size() >= 3:
			score *= 0.5

	if not player_closed and pd.is_line and target.is_line:
		score *= _line_orientation_factor(pd.norm, target.normalized_points)

	if not player_closed and enable_unit_square_open and open_rotation_reject:
		if not (pd.is_line and target.is_line):
			score *= _open_rotation_factor(
				pd.norm,
				target,
				structural,
				pd.corner_p,
				pd.unit,
				unit_search_dist,
			)

	if player_closed:
		if not _suppress_rotation_penalty:
			score *= _rotation_penalty(target, pd.peaks)
	score = clamp(score, 0.0, 100.0)
	if debug:
		debug_out["player_closed"] = player_closed
		debug_out["structural"] = structural
		debug_out["positional"] = positional
		debug_out["distance"] = distance
		debug_out["effective_tolerance"] = effective_tolerance
		debug_out["weight"] = weight
		debug_out["score"] = score
	return score


func _open_structural(player_norm: PackedVector2Array, target: TargetData) -> float:
	var full := _open_structural_core(player_norm, target)
	if open_tail_trim <= 0.0 or player_norm.size() < 16:
		return full
	var keep := int(float(player_norm.size()) * (1.0 - open_tail_trim))
	if keep < 8 or keep >= player_norm.size():
		return full
	var trimmed := PackedVector2Array()
	trimmed.resize(keep)
	for i in range(keep):
		trimmed[i] = player_norm[i]
	var short := _open_structural_core(trimmed, target)
	short *= 1.0 - open_tail_trim * 0.5
	return maxf(full, short)


func _open_structural_core(player_norm: PackedVector2Array, target: TargetData) -> float:
	var turn_diff := _open_turn_deg(player_norm) - target.total_turn_deg
	var turn_match := exp(-pow(turn_diff / open_turn_tol_deg, 2.0))
	var corner_diff := float(_open_corner_count(player_norm)) - float(target.open_corner_count)
	var corner_match := exp(-pow(corner_diff / open_corner_tol, 2.0))
	return 100.0 * turn_match * corner_match


func _rotation_penalty(target: TargetData, player_peaks: Array[Vector3]) -> float:
	if player_peaks.size() < 2 or player_peaks.size() != target.radial_peaks.size():
		return 1.0
	var n := player_peaks.size()
	var best_off := 0
	var best_var := 1.0e9
	for offset in range(n):
		var total := 0.0
		for i in range(n):
			var d := wrapf(player_peaks[i].x - target.radial_peaks[(i + offset) % n].x, -0.5, 0.5)
			total += d * d
		if total < best_var:
			best_var = total
			best_off = offset
	var resid := 0.0
	var devs := []
	for i in range(n):
		var d := wrapf(player_peaks[i].x - target.radial_peaks[(i + best_off) % n].x, -0.5, 0.5)
		resid += d
		devs.append(d)
	resid /= float(n)
	var var_total := 0.0
	for d in devs:
		var_total += (d - resid) * (d - resid)
	var std := sqrt(var_total / float(n))
	if std > 0.014:
		return 1.0
	var rot_deg := absf(resid) * 360.0
	if rot_deg <= rotation_tolerance_deg:
		return 1.0
	return exp(-pow((rot_deg - rotation_tolerance_deg) / 4.0, 2.0))


func _open_rotation_factor(
	player_norm: PackedVector2Array,
	target: TargetData,
	structural: float,
	corner_p: Array[float],
	player_unit: PackedVector2Array,
	near_dist: float,
) -> float:
	var full: Array = _unit_rotation_search(player_norm, target, 180.0, corner_p, player_unit)
	var full_dist: float = full[0]
	if full_dist >= open_rot_moderate_dist:
		return 1.0
	var deg := absf(wrapf(rad_to_deg(full[1]) / 360.0, -0.5, 0.5)) * 360.0
	if deg < open_rot_angle_deg:
		return 1.0
	if near_dist <= full_dist * 1.2:
		return 1.0
	if near_dist < open_rot_exact_dist * 2.0:
		return 1.0
	if full_dist < open_rot_exact_dist:
		return 0.0
	if structural < open_rot_struct_gate:
		return 0.0
	return 1.0



func normalize(points: PackedVector2Array) -> PackedVector2Array:
	var result := resample(points, sample_points)
	result = scale_to_unit(result)
	result = translate_to_origin(result)

	if enable_rotation_alignment:
		result = rotate_to_zero(result)

	return result


func resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	if points.size() < 2:
		return points

	var total_length := 0.0
	for i in range(1, points.size()):
		total_length += points[i - 1].distance_to(points[i])

	if total_length == 0.0:
		return points

	var spacing := total_length / float(n - 1)
	var result := PackedVector2Array()
	result.append(points[0])

	var distance_since_last := 0.0

	for i in range(1, points.size()):
		var previous := points[i - 1]
		var current := points[i]
		var segment_length := previous.distance_to(current)

		while distance_since_last + segment_length >= spacing:
			if segment_length <= 0.00001:
				break

			var remaining := spacing - distance_since_last
			var t := remaining / segment_length
			var new_point := previous.lerp(current, t)

			result.append(new_point)
			previous = new_point
			segment_length = previous.distance_to(current)
			distance_since_last = 0.0

		distance_since_last += segment_length

	while result.size() < n:
		result.append(points[-1])

	if result.size() > n:
		result.resize(n)

	return result


func _virtual_close(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var open := points.duplicate()
	open.append(points[0])
	return resample(open, sample_points)


func scale_to_unit(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points

	var bounds := get_bounding_rect(points)
	var width := bounds.size.x
	var height := bounds.size.y
	var scale_factor := sqrt(width * height)

	if minf(width, height) < line_flatness * maxf(width, height):
		scale_factor = maxf(width, height)

	if scale_factor == 0.0:
		return points

	var result := PackedVector2Array()
	result.resize(points.size())

	for i in range(points.size()):
		result[i] = points[i] / scale_factor

	return result


func translate_to_origin(points: PackedVector2Array) -> PackedVector2Array:
	var c := centroid(points)
	var result := PackedVector2Array()
	result.resize(points.size())

	for i in range(points.size()):
		result[i] = points[i] - c

	return result


func rotate_to_zero(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points
	var c := centroid(points)
	var angle := (points[0] - c).angle()
	var result := PackedVector2Array()
	result.resize(points.size())
	for i in range(points.size()):
		result[i] = (points[i] - c).rotated(-angle) + c
	return result



func get_bounding_rect(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()

	var min_p := points[0]
	var max_p := points[0]

	for p in points:
		min_p.x = minf(min_p.x, p.x)
		max_p.x = maxf(max_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.y = maxf(max_p.y, p.y)

	return Rect2(min_p, max_p - min_p)


func is_line_like(points: PackedVector2Array) -> bool:
	if points.size() < 2:
		return false
	var bounds := get_bounding_rect(points)
	var long_side := maxf(bounds.size.x, bounds.size.y)
	if long_side > 0.0 and minf(bounds.size.x, bounds.size.y) < line_flatness * long_side:
		return true
	return _is_straight(points)


func is_closed_path(points: PackedVector2Array) -> bool:
	if points.size() < 2:
		return false
	var bounds := get_bounding_rect(points)
	var max_dim := maxf(bounds.size.x, bounds.size.y)
	if max_dim == 0.0:
		return false
	return points[0].distance_to(points[-1]) / max_dim < closed_path_threshold


func _endpoint_gap_ratio(points: PackedVector2Array) -> float:
	if points.size() < 2:
		return 0.0
	var bounds := get_bounding_rect(points)
	var max_dim := maxf(bounds.size.x, bounds.size.y)
	if max_dim == 0.0:
		return 0.0
	return points[0].distance_to(points[-1]) / max_dim


func centroid(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in points:
		sum += point
	return sum / float(points.size())


func max_radius_of(points: PackedVector2Array) -> float:
	var max_r := 0.0
	for point in points:
		max_r = maxf(max_r, point.length())
	return max_r



func corner_mask(points: PackedVector2Array, step: int = 3) -> Array[float]:
	var mask: Array[float] = []
	mask.resize(points.size())
	mask.fill(0.0)

	var closed := is_closed_path(points)
	var sz := points.size()
	for i in range(sz):
		var before: Vector2
		var after: Vector2
		if closed:
			before = points[i] - points[wrapi(i - step, 0, sz)]
			after = points[wrapi(i + step, 0, sz)] - points[i]
		else:
			before = points[i] - points[maxi(i - step, 0)]
			after = points[mini(i + step, sz - 1)] - points[i]

		if absf(before.angle_to(after)) > corner_angle:
			mask[i] = 1.0

	return mask


func count_corners_from_mask(mask: Array[float]) -> int:
	var count := 0
	var sz := mask.size()
	for i in range(sz):
		if mask[i] != 0.0 and mask[wrapi(i - 1, 0, sz)] == 0.0:
			count += 1
	return count


func _open_turn_deg(points: PackedVector2Array, n := 8) -> float:
	var subsample := resample(points, n)
	var total := 0.0
	var prev := Vector2.ZERO
	for i in range(1, subsample.size()):
		var delta := subsample[i] - subsample[i - 1]
		if i > 1:
			total += absf(prev.angle_to(delta))
		prev = delta
	return rad_to_deg(total)


func _open_corner_count(points: PackedVector2Array, step := 6) -> int:
	var mask: Array[float] = []
	mask.resize(points.size())
	mask.fill(0.0)
	var sz := points.size()
	for i in range(sz):
		var before := points[i] - points[maxi(i - step, 0)]
		var after := points[mini(i + step, sz - 1)] - points[i]
		if absf(before.angle_to(after)) > corner_angle:
			mask[i] = 1.0
	return count_corners_from_mask(mask)



func path_distance_fast(player_norm: PackedVector2Array, target: TargetData) -> float:
	return _rotation_search(player_norm, target)[0]


func _corner_candidate_offsets(
	corner_a: Array[float],
	corner_b: Array[float],
	count: int,
) -> Array[int]:
	if count <= 0:
		return []
	var idx_a: Array[int] = []
	var idx_b: Array[int] = []
	for i in range(mini(corner_a.size(), count)):
		if corner_a[i] != 0.0:
			idx_a.append(i)
	for i in range(mini(corner_b.size(), count)):
		if corner_b[i] != 0.0:
			idx_b.append(i)
	if idx_a.is_empty() or idx_b.is_empty():
		return []

	var seen := { }
	var offsets: Array[int] = []
	for ca in idx_a:
		for cb in idx_b:
			for d in [-1, 0, 1]:
				var off := wrapi(cb - ca + d, 0, count)
				if not seen.has(off):
					seen[off] = true
					offsets.append(off)
	return offsets


func _rotation_search(
	player_norm: PackedVector2Array,
	target: TargetData,
	corner_p: Array[float] = [],
) -> Array:
	if corner_p.is_empty():
		corner_p = corner_mask(player_norm)

	var limit := deg_to_rad(rotation_tolerance_deg) * 3.0
	var step := deg_to_rad(6.0)
	var best := 1.0e9
	var best_ang := 0.0
	var rotated := player_norm.duplicate()

	var player_radius := max_radius_of(player_norm)
	var refit := 1.0
	if player_radius > 0.0:
		refit = target.max_radius / player_radius

	var closed := target.is_closed

	var count := mini(player_norm.size(), target.normalized_points.size())
	var fwd_offsets: Array[int] = []
	var bwd_offsets: Array[int] = []
	if closed:
		fwd_offsets = _corner_candidate_offsets(corner_p, target.corners, count)
		bwd_offsets = _corner_candidate_offsets(corner_p, target.rev_corners, count)

	var ang := -limit
	while ang <= limit + 0.0001:
		for i in range(player_norm.size()):
			rotated[i] = player_norm[i].rotated(ang) * refit

		var fwd := _min_cyclic_masked(
			rotated,
			target.normalized_points,
			corner_p,
			target.corners,
			closed,
			fwd_offsets,
		)
		var bwd := _min_cyclic_masked(
			rotated,
			target.rev_points,
			corner_p,
			target.rev_corners,
			closed,
			bwd_offsets,
		)
		var d := minf(fwd, bwd)
		if d < best:
			best = d
			best_ang = ang
		ang += step

	return [best, best_ang]


func _min_cyclic_masked(
	a: PackedVector2Array,
	b: PackedVector2Array,
	corner_a: Array[float],
	corner_b: Array[float],
	is_closed := true,
	candidate_offsets: Array[int] = [],
) -> float:
	var count := mini(a.size(), b.size())
	if count == 0:
		return 1.0e9

	var offsets: Array[int] = candidate_offsets
	if offsets.is_empty():
		offsets = []
		if is_closed:
			for i in range(count):
				offsets.append(i)
		else:
			offsets.append(0)

	var best := 1.0e9

	for offset in offsets:
		var total := 0.0
		var weight_sum := 0.0

		for i in range(count):
			var idx_b := (i + offset) % count
			var weight := 1.0 + corner_weight * (corner_a[i] + corner_b[idx_b])
			total += weight * a[i].distance_to(b[idx_b])
			weight_sum += weight

		var dist := total / weight_sum
		if dist < best:
			best = dist

	return best



func structural_score_fast(
	player: PackedVector2Array,
	target: TargetData,
	player_peaks: Array[Vector3],
	corner_p: Array[float] = [],
) -> float:
	var target_peaks := target.radial_peaks

	var player_count := player_peaks.size()
	var target_count := target_peaks.size()

	if target_count == 0:
		if player_count == 0:
			return 100.0
		return 100.0 * exp(-pow(float(player_count) / 3.0, 2.0))

	var player_corners := count_corners_from_mask(
		corner_p if not corner_p.is_empty() else corner_mask(player)
	)
	if target.corner_count >= 3 and player_corners < maxi(2, target.corner_count - 2):
		return 0.0

	if player_count == 0:
		return 0.0

	var count_match := exp(-pow(float(abs(player_count - target_count)), 2.0))

	var best := 1.0e9
	for offset in range(target_count):
		var total := 0.0
		for i in range(player_count):
			total += absf(player_peaks[i].y - target_peaks[(i + offset) % target_count].y)
		best = minf(best, total / float(player_count))

	var depth_match := exp(-pow(best / peak_depth_tolerance, 2.0))
	return 100.0 * count_match * depth_match * _regularity_factor(player_peaks)


func radial_signal(points: PackedVector2Array) -> Array[float]:
	var profile: Array[float] = []
	profile.resize(radial_bins)
	profile.fill(0.0)

	for point in points:
		var angle := wrapf(atan2(point.y, point.x) / TAU, 0.0, 1.0)
		var index := int(round(angle * radial_bins)) % radial_bins
		var radius := point.length()

		if radius > profile[index]:
			profile[index] = radius

	for _pass in range(2):
		for i in range(radial_bins):
			if profile[i] == 0.0:
				var previous := profile[wrapi(i - 1, 0, radial_bins)]
				var following := profile[wrapi(i + 1, 0, radial_bins)]
				profile[i] = 0.5 * (previous + following)

	return profile


func smooth_circular(values: Array[float], passes: int) -> Array[float]:
	var curr: Array[float] = values.duplicate()
	var next: Array[float] = []
	next.resize(radial_bins)

	for _pass in range(passes):
		for i in range(radial_bins):
			var previous := curr[wrapi(i - 1, 0, radial_bins)]
			var following := curr[wrapi(i + 1, 0, radial_bins)]
			next[i] = 0.25 * previous + 0.5 * curr[i] + 0.25 * following

		var temp := curr
		curr = next
		next = temp

	return curr


func radial_peaks(points: PackedVector2Array) -> Array[Vector3]:
	var profile := smooth_circular(radial_signal(points), 2)
	var mean_radius := 0.0

	for value in profile:
		mean_radius += value
	mean_radius /= float(radial_bins)

	var peaks: Array[Vector3] = []

	for i in range(radial_bins):
		var is_peak := true
		for k in range(1, peak_min_separation + 1):
			if (
				profile[i] <= profile[wrapi(i - k, 0, radial_bins)]
				or profile[i] < profile[wrapi(i + k, 0, radial_bins)]
			):
				is_peak = false
				break

		if not is_peak:
			continue

		var lowest := 1.0e9
		for k in range(1, peak_min_separation + 1):
			lowest = minf(lowest, profile[wrapi(i - k, 0, radial_bins)])
			lowest = minf(lowest, profile[wrapi(i + k, 0, radial_bins)])

		if profile[i] - lowest > min_peak_depth * mean_radius:
			peaks.append(Vector3(float(i) / float(radial_bins), profile[i], profile[i] - lowest))

	return peaks


func _coeff_of_variation(values: Array[float]) -> float:
	if values.size() < 2:
		return 0.0
	var mean := 0.0
	for value in values:
		mean += value
	mean /= float(values.size())
	if mean == 0.0:
		return 0.0

	var variance := 0.0
	for value in values:
		variance += (value - mean) * (value - mean)
	variance /= float(values.size())
	return sqrt(variance) / mean


func _regularity_factor(peaks: Array[Vector3]) -> float:
	if peaks.size() < 3:
		return 1.0
	var angles: Array[float] = []
	var depths: Array[float] = []
	for peak in peaks:
		angles.append(peak.x)
		depths.append(peak.z)
	angles.sort()
	var gaps: Array[float] = []
	for i in range(angles.size()):
		var gap := angles[(i + 1) % angles.size()] - angles[i]
		if gap < 0.0:
			gap += 1.0
		if gap > 1.0e-6:
			gaps.append(gap)
	var gap_cv := _coeff_of_variation(gaps)
	var depth_cv := _coeff_of_variation(depths)
	var gap_norm := maxf(gap_cv - 0.1, 0.0) / 0.3
	var depth_norm := maxf(depth_cv - 0.15, 0.0) / 0.45
	return exp(-pow(minf(gap_norm, depth_norm) * 1.4, 2.0))


func circle_distance_to(points: PackedVector2Array) -> float:
	return path_distance_best_alignment_raw(points, _unit_circle())


func path_distance_best_alignment_raw(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var corner_a := corner_mask(a)
	var corner_b := corner_mask(b)
	var b_rev := reverse_points(b)
	var corner_b_rev := corner_mask(b_rev)

	var fwd := _min_cyclic_masked(a, b, corner_a, corner_b)
	var bwd := _min_cyclic_masked(a, b_rev, corner_a, corner_b_rev)
	return minf(fwd, bwd)


func unit_square_normalize(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points
	var bounds := get_bounding_rect(points)
	var width := bounds.size.x
	var height := bounds.size.y
	if width == 0.0 or height == 0.0:
		return points.duplicate()

	var result := PackedVector2Array()
	result.resize(points.size())
	for i in range(points.size()):
		result[i] = Vector2(
			(points[i].x - bounds.position.x) / width,
			(points[i].y - bounds.position.y) / height,
		)
	var c := centroid(result)
	for i in range(result.size()):
		result[i] -= c
	return result


func _unit_rotation_search(
	player_norm: PackedVector2Array,
	target: TargetData,
	limit_deg := -1.0,
	corner_p: Array[float] = [],
	player_unit: PackedVector2Array = PackedVector2Array(),
) -> Array:
	if corner_p.is_empty():
		corner_p = corner_mask(player_norm)
	if player_unit.is_empty():
		player_unit = unit_square_normalize(player_norm)

	var lim := rotation_tolerance_deg * 3.0 if limit_deg <= 0.0 else limit_deg
	var fine_step := deg_to_rad(6.0)

	var player_radius := max_radius_of(player_unit)
	var refit := 1.0
	if player_radius > 0.0:
		refit = target.unit_max_radius / player_radius

	var rotated := player_unit.duplicate()

	var center := 0.0
	var half_range := deg_to_rad(lim)
	if lim > 90.0:
		var coarse_step := fine_step * 4.0
		var coarse_best := 1.0e9
		var coarse_ang := 0.0
		var limit := deg_to_rad(lim)
		var loop_ang := -limit
		while loop_ang <= limit + 0.0001:
			for i in range(player_unit.size()):
				rotated[i] = player_unit[i].rotated(loop_ang) * refit
			var fwd := _min_cyclic_masked(
				rotated,
				target.unit_points,
				corner_p,
				target.corners,
				false,
			)
			var bwd := _min_cyclic_masked(
				rotated,
				target.unit_rev_points,
				corner_p,
				target.rev_corners,
				false,
			)
			var d := minf(fwd, bwd)
			if d < coarse_best:
				coarse_best = d
				coarse_ang = loop_ang
			loop_ang += coarse_step
		center = coarse_ang
		half_range = coarse_step

	var best := 1.0e9
	var best_ang := 0.0
	var lo := center - half_range
	var hi := center + half_range
	var ang := lo
	while ang <= hi + 0.0001:
		for i in range(player_unit.size()):
			rotated[i] = player_unit[i].rotated(ang) * refit

		var fwd := _min_cyclic_masked(rotated, target.unit_points, corner_p, target.corners, false)
		var bwd := _min_cyclic_masked(
			rotated,
			target.unit_rev_points,
			corner_p,
			target.rev_corners,
			false,
		)
		var d := minf(fwd, bwd)
		if d < best:
			best = d
			best_ang = ang
		ang += fine_step

	return [best, best_ang]


func reverse_points(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points.size() - 1, -1, -1):
		result.append(points[i])
	return result


func _unit_circle() -> PackedVector2Array:
	if _unit_circle_cache.is_empty():
		var points := PackedVector2Array()
		for i in range(sample_points):
			var angle := TAU * float(i) / float(sample_points)
			points.append(Vector2(cos(angle), sin(angle)))
		_unit_circle_cache = normalize(points)
	return _unit_circle_cache
