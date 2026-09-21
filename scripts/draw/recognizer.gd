# recognizer.gd — Gesture recognition engine (class_name GestureRecognizer): scores
# player strokes vs. target shapes via resampling, rotation search, corner masks
# and radial-peak structure. compare() returns 0-100 accuracy, guess() classifies
# strokes (circle/square/triangle/line/other) from ideal templates.
# Sloppy-but-correct strokes score above 60 (BAD_DRAW threshold); clearly
# different shapes score below 60. Difficulty (overall_difficulty 1-10, base 5)
# scales tolerances via apply_overall_difficulty()/compare_with_od().
# RETURN: accuracy score (0-100) for compare, shape name for guess
class_name GestureRecognizer
extends Resource

# --- Configurable Parameters (Godot Inspector) ---

@export_group("Base Tolerance")
## Base tolerance for general shapes. Lower = stricter, Higher = more forgiving.
## Source of truth: apply_overall_difficulty() rescales the runtime tolerances
## from these every time (never compounded).
@export_range(0.01, 0.5, 0.01) var base_tolerance: float = 0.3

## Base tolerance for straight or near-flat lines.
@export_range(0.01, 0.5, 0.01) var base_line_tolerance: float = 0.35

## Base tolerance for complex/spiky shapes far from a circle (e.g., star).
@export_range(0.01, 0.5, 0.01) var base_complex_tolerance: float = 0.46

## Base tolerance for open (non-closed) shapes like L, U, Z, arcs.
@export_range(0.01, 0.5, 0.01) var base_open_tolerance: float = 0.38

## Base tolerance for open-shape matching after unit-square normalization.
## Unit-square normalization removes aspect-ratio sensitivity, so hand-drawn
## L/U/Z/C strokes match their targets even when bar proportions differ.
@export_range(0.1, 1.0, 0.01) var base_open_unit_tolerance: float = 0.7

## Base fraction of points trimmed from the end of open strokes before
## structural (turn/corner) scoring. Forgives very short extra segments or
## hooks at the end of L/V/U strokes by scoring structure as if the tiny
## tail were absent. 0.08 removes roughly the last 8% of resampled points.
@export_range(0.0, 0.2, 0.01) var base_open_tail_trim: float = 0.08

# Runtime tolerances, rescaled from the base values above by
# apply_overall_difficulty(). Do not edit directly; tune the base values.
var tolerance: float = 0.3
var line_tolerance: float = 0.35
var complex_tolerance: float = 0.46
var open_tolerance: float = 0.38
var open_unit_tolerance: float = 0.7
var open_tail_trim: float = 0.08

@export_group("Matching Behavior")
## When true, open shapes are matched with unit-square normalization, which
## is robust to the aspect-ratio and proportion variance of hand-drawn strokes.
@export var enable_unit_square_open: bool = true

## Weight of the structural (turn/corner) score for open shapes. Open shapes
## are drawn noisily, so their structure matters more than for closed shapes.
@export_range(0.0, 1.0, 0.05) var open_structural_weight: float = 0.65

## Rejects open shapes that match their target near-perfectly only after a
## large rotation (e.g. an L drawn rotated 180 deg, a U drawn sideways).
@export var open_rotation_reject: bool = true

@export_group("Open Rotation Rejection")
## Distance below which an open shape is treated as an exact rotated copy.
@export_range(0.01, 0.3, 0.01) var open_rot_exact_dist: float = 0.06
## Below this distance a rotated open shape with poor structure is rejected.
@export_range(0.05, 0.5, 0.01) var open_rot_moderate_dist: float = 0.18
## Below this structural score, a moderately-fitted rotated open shape rejects.
@export_range(0.0, 100.0, 5.0) var open_rot_struct_gate: float = 60.0
## Rotation angle (deg) beyond which open shapes are considered rotated copies.
@export_range(15.0, 90.0, 5.0) var open_rot_angle_deg: float = 45.0

## Turn-difference tolerance (degrees) for matching open shapes.
@export_range(5.0, 60.0, 1.0) var open_turn_tol_deg: float = 45.0

## Corner-count tolerance for matching open shapes.
@export_range(0.5, 3.0, 0.1) var open_corner_tol: float = 2.5

## Maximum rotation (degrees) forgiven during matching. Small offsets are
## corrected; larger rotations (90 deg, flips) are NOT aligned and still fail.
@export_range(0.0, 45.0, 1.0) var rotation_tolerance_deg: float = 15.0

## Ratio of positional score vs structural (radial) score. Kept at 0.5 so
## similar polygons stay separable: sloppy strokes keep matching peaks
## (structural ~100, unaffected) while triangle-vs-square drops to ~51-55
## (clearly BAD) instead of sitting on the 60 boundary.
@export_range(0.0, 1.0, 0.05) var structural_weight: float = 0.5

@export_group("Difficulty (overall_difficulty 1-10)")
## Chart OD that these base tolerances are tuned for. OD 5 = base (scale 1.0),
## OD 1 = most forgiving (scale od_max_scale), OD 10 = strictest (scale 0.5).
@export_range(1.0, 10.0, 1.0) var base_od: float = 5.0
## Tolerance scale applied per OD step away from base_od.
@export_range(0.02, 0.2, 0.01) var od_step_scale: float = 0.1
## Clamp range for OD input.
@export_range(1.0, 10.0, 1.0) var od_min: float = 1.0
@export_range(1.0, 10.0, 1.0) var od_max: float = 10.0
## Widest (most forgiving, OD 1) and narrowest (strictest, OD 10) scales.
## Keep the forgiving cap low: similar polygons (triangle vs square) already
## score ~58 at base, so anything past ~1.1 pushes wrong shapes above the
## BAD threshold of 60.
@export_range(1.0, 2.0, 0.05) var od_max_scale: float = 1.1
@export_range(0.3, 1.0, 0.05) var od_min_scale: float = 0.5

@export_group("Draw Quality Bands (0-100)")
## Below this the stroke counts as BAD DRAWING (must stay in sync with
## ScoreManager.DRAW_BAD_THRESHOLD = 60).
@export_range(0.0, 100.0, 1.0) var bad_threshold: float = 60.0
## At/above this the stroke counts as GOOD. 75 is the midpoint between BAD
## (60) and PERFECT (~90): the middle ground between the most forgiving
## wrong-shape ceiling (~50) and the strictest sloppy-stroke floor (~70-90).
@export_range(0.0, 100.0, 1.0) var good_threshold: float = 75.0
## At/above this the stroke counts as PERFECT.
@export_range(0.0, 100.0, 1.0) var perfect_threshold: float = 90.0

@export_group("Line Orientation")
## Angle (deg) tolerance for line-vs-line direction. A perpendicular line
## (90 deg off) must score ~0; a sloppy line (a few deg off) keeps ~full score.
@export_range(10.0, 45.0, 1.0) var line_angle_tol_deg: float = 25.0
## Total turning (deg) below which an open stroke counts as straight
## (catches 2-point diagonals, which are straight lines despite a square bbox).
@export_range(5.0, 30.0, 1.0) var straight_turn_tol_deg: float = 12.0

@export_group("Resampling & Preprocessing")
## Number of resampled points along the path.
@export var sample_points: int = 64

## Aspect ratio threshold below which a shape is treated as a straight line.
@export_range(0.05, 0.5, 0.01) var line_flatness: float = 0.3

## Ratio of start-to-end distance vs bbox max dimension to consider a path closed.
@export_range(0.05, 0.5, 0.01) var closed_path_threshold: float = 0.25

## Endpoint gap (fraction of bbox max dimension) below which an unclosed stroke
## is still treated as a closed shape when the target is closed. Below the
## strict `closed_path_threshold` a stroke is closed outright; between that and
## this value it is only tolerated against closed targets.
@export_range(0.25, 1.0, 0.05) var near_closed_gap: float = 0.5

## Minimum match score (0..100) for guess() to accept a template as the answer.
## Below this the stroke is reported as "other". Raise it to be stricter.
@export_range(10.0, 90.0, 1.0) var guess_score_threshold: float = 50.0

## Score at/above which guess() stops scanning remaining templates and accepts
## the current best match immediately. Purely a performance short-circuit —
## keep this comfortably above guess_score_threshold so it never changes which
## shape wins, only how many templates get scored to find out.
@export_range(50.0, 100.0, 1.0) var guess_early_exit_score: float = 92.0

## Largest start/end gap (fraction of bbox max dimension) that is still treated
## as an unfinished closed shape. Beyond compare()'s `near_closed_gap` a stroke
## normally reads as open; above this threshold it is reported as an open stroke
## instead of being virtually stitched into a closed shape.
@export_range(0.5, 1.0, 0.05) var unfinished_gap: float = 0.75

## Enables rotation alignment (normalizes initial stroke direction).
@export var enable_rotation_alignment: bool = false

@export_group("Feature & Corner Detection")
## Angle (radians) that defines a sharp turn/corner (~55 deg = 0.96 rad).
@export_range(0.1, 2.0, 0.01) var corner_angle: float = 0.9599

## Extra weight given to corner points during cyclic distance matching.
@export_range(0.0, 5.0, 0.1) var corner_weight: float = 1.0

@export_group("Radial Signature")
## Number of angular bins for radial signatures.
@export var radial_bins: int = 72

## Minimum separation window (in bins) required to register a peak.
@export var peak_min_separation: int = 6

## Minimum depth (fraction of mean radius) for a peak to avoid wobble.
@export_range(0.01, 0.5, 0.01) var min_peak_depth: float = 0.08

## Depth tolerance when comparing radial peak profiles.
@export_range(0.01, 0.5, 0.01) var peak_depth_tolerance: float = 0.15

## Normalized distance threshold to consider a shape distinct from a circle.
@export_range(0.1, 1.0, 0.05) var circle_distinct: float = 0.3

@export_group("Debug Capture")
## When true, every compare() call stores its configuration, the raw target
## points and the raw drawn (player) points plus the score breakdown into
## `debug_captures` (see `debug_last` for the most recent one). Zero cost
## when false. Toggle it in the Inspector or via `debug_enabled = true`.
@export var debug_enabled: bool = false
## When true (and `debug_enabled` is true), each compare() also prints a
## one-line summary (score, point counts, distance) to the console.
@export var debug_print_on_compare: bool = false
## Maximum number of captures kept in `debug_captures` (oldest dropped first).
@export_range(1, 200, 1) var debug_max_captures: int = 20

# Last compare() debug capture (empty Dictionary when nothing captured yet).
var debug_last: Dictionary = {}
# Ring buffer of recent compare() debug captures, oldest first.
var debug_captures: Array[Dictionary] = []

# Lazy-loaded unit circle
var _unit_circle_cache: PackedVector2Array = PackedVector2Array()

# Lazy template library used by guess()
var _template_cache: Dictionary = {}
# Template names in a fixed, deterministic order (parallel to _template_cache).
var _template_names: Array[String] = []
var _templates_ready := false
var _suppress_rotation_penalty := false


# --- Target Data Cache Struct (Saves massive frame time) ---
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


## Cache target shapes using this method so structural data isn't recomputed on every swipe!
func create_target_data(points: PackedVector2Array) -> TargetData:
	return TargetData.new(points, self)


# --- Player Stroke Data (Built Once, Reused Across Targets) ---
## Everything the matcher needs to know about the player's stroke. Building
## it once per guess()/compare() and reusing it for every target removes the
## redundant resampling, radial-peak, corner-mask and unit-square work that
## used to happen inside each compare_to_target_data() call.
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
	# radial peaks are only needed once the stroke is (idiomatically) closed,
	# and unit-square normalization only for genuinely open strokes.
	if pd.closed:
		pd.peaks = radial_peaks(pd.norm)
		pd.peaks_ready = true
	return pd


# --- Public Entry Points ---


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

	# Classify by matching the stroke against a small library of ideal templates
	# using the same tuned pipeline as the accuracy scoring in compare(). This
	# is far more robust than hand-counting corners:
	#   - a hand-drawn circle with a gap or an overshoot (treated as near-closed
	#     by compare()) still wins the circle match instead of falling into the
	#     corner-count cracks,
	#   - a sloppy square outscores a triangle because both the positional and
	#     the structural (radial-peak) terms agree,
	#   - genuinely open strokes (L, V, [, U) are matched by the open-stroke
	#     matcher instead of being dismissed as "not a closed path".
	# The player stroke is normalized / feature-extracted exactly once and the
	# result reused for every template; targets that cannot possibly match are
	# skipped outright instead of being fed through the zero-returning
	# topology check.
	var tpls := _templates()
	var names := _template_names
	var best_name := "other"
	var best_score := 0.0
	# Classifying against ideal templates must accept any starting corner/phase
	# (a square can start at any corner, a diamond is a 45-degree square). The
	# rotation-phase penalty below exists to grade a stroke against a fixed
	# reference in compare(); it must not zero a shape in guess() just because
	# the player began the loop at a different point.
	_suppress_rotation_penalty = true
	for name in names:
		var tpl: TargetData = tpls[name]
		# Mirror the topology mismatch in _score_player_data: a closed stroke
		# can never match an open template, and an open stroke only matches a
		# closed template when its endpoint gap is under `near_closed_gap`.
		if (
			(pd.closed and not tpl.is_closed)
			or (not pd.closed and tpl.is_closed and pd.gap_ratio >= near_closed_gap)
		):
			continue
		var score := _score_player_data(pd, tpl)
		if score > best_score:
			best_score = score
			best_name = name
			# Performance short-circuit only: once a template scores this
			# high nothing later in `names` could realistically beat it, so
			# stop paying for more _rotation_search calls. Keep
			# guess_early_exit_score comfortably above guess_score_threshold
			# so this never changes *which* shape wins, only how many
			# templates get scored to find out.
			if best_score >= guess_early_exit_score:
				break
	_suppress_rotation_penalty = false
	if best_score >= guess_score_threshold:
		return best_name

	# Second chance: an unfinished closed shape whose opening is larger than
	# compare()'s `near_closed_gap` reads as an open stroke and matched nothing
	# above. Virtually stitch its ends together and retry against the closed
	# templates only, so a circle/square/etc. left a quarter open still gets
	# classified instead of falling into "other".
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


## Lazily-built ideal stroke templates, cached as TargetData so their
## structural data is computed once per recognizer instead of per swipe.
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
				[
					Vector2(-1, -1),
					Vector2(-1, 1),
					Vector2(1, 1),
					Vector2(1, -1),
					Vector2(-1, -1),
				]
			)
		"triangle":
			return PackedVector2Array(
				[
					Vector2(1, 1),
					Vector2(0, -1),
					Vector2(-1, 1),
					Vector2(1, 1),
				]
			)

		"exit":
			return PackedVector2Array(
				[
					Vector2(-1, 1),
					Vector2(1, -1),
					Vector2(1, 1),
					Vector2(-1, -1),
					Vector2(-1, 1),
				]
			)
	return PackedVector2Array()


func compare_to_target_data(player: PackedVector2Array, target: TargetData) -> float:
	if player.size() < 2 or target.normalized_points.size() < 2:
		return 0.0
	var pd := build_player_data(player)
	var debug_out := {}
	var score := _score_player_data(pd, target, debug_out)
	if debug_enabled:
		_debug_store_capture(player, pd, target, score, debug_out)
	return score


## Drops all stored debug captures and resets `debug_last`.
func clear_debug_captures() -> void:
	debug_captures.clear()
	debug_last = {}


## Snapshot of every tuning value that influences scoring. Stored with each
## debug capture so a saved capture fully reproduces the configuration.
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


## Converts points to plain [[x, y], ...] arrays so captures are JSON-safe.
func _debug_points_to_arrays(points: PackedVector2Array) -> Array:
	var out := []
	out.resize(points.size())
	for i in range(points.size()):
		out[i] = [points[i].x, points[i].y]
	return out


## Records one compare() call: config + raw/normalized target and player
## points + score breakdown. Keeps at most `debug_max_captures` entries.
func _debug_store_capture(
	player_raw: PackedVector2Array,
	pd: PlayerData,
	target: TargetData,
	score: float,
	breakdown: Dictionary
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


## Writes all stored captures as JSON to `path` (e.g. "user://draw_debug.json").
## Returns OK on success, else a FileAccess error code. Points are stored as
## [[x, y], ...] arrays; use `clear_debug_captures()` to reset afterwards.
func save_debug_captures(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(debug_captures, "\t"))
	f.close()
	return OK


# --- Difficulty (overall_difficulty 1-10) & Quality Bands ---


## Scale factor for an OD value: OD 5 (base) -> 1.0, OD 1 -> od_max_scale
## (most forgiving), OD 10 -> od_min_scale (strictest). Linear in between.
func tolerance_scale_for_od(od: float) -> float:
	var c := clampf(od, od_min, od_max)
	return clampf(1.0 + (base_od - c) * od_step_scale, od_min_scale, od_max_scale)


## Applies an OD value to this recognizer by rescaling every runtime tolerance
## from the Base Tolerance exports (never compounded: calling twice recomputes
## from base). Returns the applied scale. Sloppy strokes stay above
## `bad_threshold` (60) while clearly different shapes stay below it across
## the full OD 1-10 range.
func apply_overall_difficulty(od: float) -> float:
	var s := tolerance_scale_for_od(od)
	tolerance = base_tolerance * s
	line_tolerance = base_line_tolerance * s
	complex_tolerance = base_complex_tolerance * s
	open_tolerance = base_open_tolerance * s
	open_unit_tolerance = base_open_unit_tolerance * s
	open_tail_trim = clampf(base_open_tail_trim * s, 0.0, 0.2)
	return s


## Reads a chart's overall_difficulty (1-10, 5 = base). Handles both the raw
## metadata string ("6") and the legacy ChartData.get_od() (/1000) scaling.
static func od_from_chart(chart: ChartData) -> float:
	if chart == null:
		return 5.0
	var raw := 5.0
	if not chart.metadata.is_empty() and chart.metadata.has("overall_difficulty"):
		raw = float(str(chart.metadata["overall_difficulty"]))
	elif chart.has_method("get_od"):
		raw = float(chart.call("get_od")) * 1000.0
	return clampf(raw, 1.0, 10.0)


## Applies the OD of a ChartData (usually Global.current_chart). No-op for null.
func apply_chart_od(chart: ChartData) -> float:
	return apply_overall_difficulty(GestureRecognizer.od_from_chart(chart))


## Scores with a one-shot OD applied first (does not permanently change tuning
## any more than apply_overall_difficulty does — both recompute from base).
func compare_with_od(player: PackedVector2Array, target: PackedVector2Array, od: float) -> float:
	apply_overall_difficulty(od)
	return compare(player, target)


## Quality band for a 0-100 score: perfect / good / sloppy (pass) / bad.
## GOOD (75) is the midpoint between BAD (60) and PERFECT (90).
func quality_of(score: float) -> String:
	if score >= perfect_threshold:
		return "perfect"
	if score >= good_threshold:
		return "good"
	if score >= bad_threshold:
		return "sloppy"
	return "bad"


## True when the score counts as a successful drawing (sloppy or better).
func is_pass(score: float) -> bool:
	return score >= bad_threshold


# --- Straight-stroke & Line-orientation helpers ---


## True for open strokes with almost no total turning (2-point diagonals,
## hlines/vlines). Catches straight lines whose bbox is square, which the
## flatness-only check misses.
func _is_straight(points: PackedVector2Array) -> bool:
	if points.size() < 2:
		return false
	if is_closed_path(points):
		return false
	return _open_turn_deg(points) < straight_turn_tol_deg


## Principal direction of a stroke (endpoints of the normalized path).
## Directionless: drawing backwards gives the same angle.
func _line_angle(points: PackedVector2Array) -> float:
	if points.size() < 2:
		return 0.0
	var d := points[points.size() - 1] - points[0]
	if d.length() < 1.0e-6:
		return 0.0
	return d.angle()


## 0-1 orientation factor for line-vs-line pairs. 0 deg -> 1.0, 45 deg -> ~0.04,
## 90 deg -> ~0.0 (with the default 25-deg tolerance), so perpendicular lines
## always fail while sloppy lines (a few deg off) keep their score.
func _line_orientation_factor(
	player_norm: PackedVector2Array, target_norm: PackedVector2Array
) -> float:
	var diff := absf(
		wrapf(_line_angle(player_norm) - _line_angle(target_norm), -PI / 2.0, PI / 2.0)
	)
	return exp(-pow(rad_to_deg(diff) / line_angle_tol_deg, 2.0))


## Scores a ready-made player stroke against one target. All player-side cost
## (normalization, radial peaks, corner mask, unit-square refit) already lives
## in `pd` and is shared across every target in a guess()/compare() run.
## When `debug_out` is provided (compare path) it is filled with the score
## breakdown (structural/positional/distance/weight); guess() leaves it empty.
func _score_player_data(pd: PlayerData, target: TargetData, debug_out: Dictionary = {}) -> float:
	if target.normalized_points.size() < 2:
		return 0.0

	var player_closed := pd.closed
	var debug := debug_enabled

	# Topology mismatch: Open stroke (like a line) vs Closed shape (like a star).
	# Hand-drawn closed shapes rarely seal their endpoints, so a stroke that only
	# misses closing by a small gap is still treated as a closed shape; the
	# positional distance then penalizes the small seam naturally.
	if player_closed != target.is_closed:
		if target.is_closed and pd.gap_ratio < near_closed_gap:
			player_closed = true
		else:
			if debug:
				debug_out["topology_mismatch"] = true
				debug_out["player_closed"] = pd.closed
				debug_out["score"] = 0.0
			return 0.0
	# A near-closed stroke treated as closed needs its radial peaks measured on
	# the (assumed) closed boundary; compute them once here, lazily.
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
					pd.norm, target, -1.0, pd.corner_p, pd.unit
				)
				distance = unit_search[0]
				unit_search_dist = distance  # Store for step 2
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

	# Gaussian falloff
	var positional := 100.0 * exp(-pow(distance / effective_tolerance, 2.0))

	var weight := open_structural_weight if not player_closed else structural_weight
	var score := lerpf(positional, structural, weight)

	# A stroke with no radial peaks (a plain circle/ellipse) must not match a
	# polygon target even when the positional fit is deceptively close.
	if player_closed and target.is_closed:
		if pd.peaks.is_empty() and target.radial_peaks.size() >= 3:
			score *= 0.5

	# Line-vs-line orientation: a perpendicular line is clearly a different
	# shape and must fail, while a sloppy line (a few degrees off) keeps its
	# score. Straight diagonals count as lines (see is_line_like), so diag vs
	# hline (45 deg) and hline vs vline (90 deg) both fail here.
	if not player_closed and pd.is_line and target.is_line:
		score *= _line_orientation_factor(pd.norm, target.normalized_points)

	# Open shapes that only match their target after a large rotation (rotated
	# copies, sideways strokes) are rejected while sloppy-but-aligned strokes
	# and rotationally symmetric shapes are left alone. Line strokes are exempt
	# (their orientation is handled by _line_orientation_factor above).
	if not player_closed and enable_unit_square_open and open_rotation_reject:
		if not (pd.is_line and target.is_line):
			score *= _open_rotation_factor(
				pd.norm, target, structural, pd.corner_p, pd.unit, unit_search_dist
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
	# Small discount for the ignored tail so clean strokes still outscore
	# hooked ones, while tiny extras are forgiven instead of harshly dropped.
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


## Near-perfect open shapes that only fit their target after a large rotation
## are rotated copies (L drawn at 180 deg, U drawn sideways, arcs facing the
## wrong way) and must be rejected. Strokes that also fit reasonably when
## aligned (rotationally symmetric shapes like a Z or an upside-down U) and
## sloppy-but-aligned strokes are left alone.
func _open_rotation_factor(
	player_norm: PackedVector2Array,
	target: TargetData,
	structural: float,
	corner_p: Array[float],
	player_unit: PackedVector2Array,
	near_dist: float
) -> float:
	# REMOVE: Calling _unit_rotation_search 2x Performance issue
	# var near_dist: float = _unit_rotation_search(
	# 	player_norm, target, rotation_tolerance_deg, corner_p, player_unit
	# )[0]
	var full: Array = _unit_rotation_search(player_norm, target, 180.0, corner_p, player_unit)
	var full_dist: float = full[0]
	if full_dist >= open_rot_moderate_dist:
		return 1.0
	var deg := absf(wrapf(rad_to_deg(full[1]) / 360.0, -0.5, 0.5)) * 360.0
	if deg < open_rot_angle_deg:
		return 1.0
	if near_dist <= full_dist * 1.2:
		return 1.0
	# Symmetric strokes (straight diagonals, Z-like shapes) also fit well when
	# aligned: a tiny aligned distance means this is the same shape, not a
	# rotated copy. Without this, diag-vs-diag self-matches score 0.
	if near_dist < open_rot_exact_dist * 2.0:
		return 1.0
	if full_dist < open_rot_exact_dist:
		return 0.0
	if structural < open_rot_struct_gate:
		return 0.0
	return 1.0


# --- Preprocessing Pipeline ---


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
			# FIX: Divide-by-zero protection when consecutive points overlap
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


## Stitches the two ends of an under-closed stroke together and re-samples the
## seam so structural features (corners, radial peaks) can be measured as if the
## loop had been completed. Used by guess()'s second-chance pass for unfinished
## closed shapes whose opening is wider than `near_closed_gap`.
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


# --- Helpers & Bounding Box ---


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
	# Straight strokes with a square bbox (2-point diagonals) are lines too.
	return _is_straight(points)


func is_closed_path(points: PackedVector2Array) -> bool:
	if points.size() < 2:
		return false
	var bounds := get_bounding_rect(points)
	var max_dim := maxf(bounds.size.x, bounds.size.y)
	if max_dim == 0.0:
		return false
	return points[0].distance_to(points[-1]) / max_dim < closed_path_threshold


## Start-to-end gap as a fraction of the bbox max dimension. Scale-invariant,
## so it can be compared against the normalized points.
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


# --- Corner Masking ---


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


## Total absolute turning (degrees) along a path, measured on a short
## subsample for noise robustness. Input must already be normalized.
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


## Corner count for open shapes, using a larger step so smooth curves
## (arcs) don't register spurious corners. Input must be normalized.
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


# --- Fast Cyclic Distance (Zero Heap Allocations) ---


func path_distance_fast(player_norm: PackedVector2Array, target: TargetData) -> float:
	return _rotation_search(player_norm, target)[0]


## Builds a small set of candidate cyclic offsets for `_min_cyclic_masked`,
## instead of trying all `count` offsets. The true best alignment for a
## polygon-like shape virtually always lines a player corner up with a target
## corner, so this tries only offsets that do that (plus a +/-1 index window
## to absorb resampling phase noise), deduplicated. Falls back to an empty
## array — which callers treat as "search everything" — whenever either side
## has no detected corners (circles/ellipses/near-circular strokes), so those
## keep their original exhaustive, fully-accurate search.
func _corner_candidate_offsets(
	corner_a: Array[float], corner_b: Array[float], count: int
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

	var seen := {}
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
	player_norm: PackedVector2Array, target: TargetData, corner_p: Array[float] = []
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

	# Corner masks don't move relative to point index when we rotate the
	# points below (rotated[i] is still the same logical point as
	# player_norm[i], just spun around the origin), so the candidate offsets
	# they imply are valid for every angle in the sweep. Compute them once
	# instead of re-deriving them per angle step.
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
			rotated, target.normalized_points, corner_p, target.corners, closed, fwd_offsets
		)
		var bwd := _min_cyclic_masked(
			rotated, target.rev_points, corner_p, target.rev_corners, closed, bwd_offsets
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
	candidate_offsets: Array[int] = []
) -> float:
	var count := mini(a.size(), b.size())
	if count == 0:
		return 1.0e9

	# Open paths have a fixed start and end: only the natural alignment
	# (offset 0) is valid, plus the reversed path covers drawing backwards.
	# Closed loops must try every cyclic shift because the user may start
	# anywhere around the loop — unless the caller supplied a shortlist of
	# corner-aligned candidates, in which case that shortlist already covers
	# every alignment worth trying.
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


# --- Structural Profile & Radial Peaks ---


func structural_score_fast(
	player: PackedVector2Array,
	target: TargetData,
	player_peaks: Array[Vector3],
	corner_p: Array[float] = []
) -> float:
	var target_peaks := target.radial_peaks

	var player_count := player_peaks.size()
	var target_count := target_peaks.size()

	# Target is a plain circle/ellipse (no radial peaks). A hand-drawn circle
	# has shallow wobble peaks, so grade them down gently by count instead of
	# zeroing the structural score; deep/many peaks (polygons, stars) still
	# score near zero.
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

		# Swap reference buffers instead of re-allocating
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


## Graded (0..1) regularity factor for the structural score. Never zeroes a
## hand-drawn stroke outright; it only scales the structural contribution down
## when BOTH the angular spacing and the peak depths are strongly irregular.
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


## Independently scales each axis so the bounding box becomes a unit square,
## then centers on the origin. This removes aspect-ratio and proportion
## sensitivity that point-to-point matching inherits from real strokes.
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
			(points[i].x - bounds.position.x) / width, (points[i].y - bounds.position.y) / height
		)
	var c := centroid(result)
	for i in range(result.size()):
		result[i] -= c
	return result


## Rotation search performed on unit-square-normalized points. Reuses the
## corner masks from the aspect-preserving normalized path (corner detection
## is invariant to rotation and small affine changes). `limit_deg` overrides
## the search half-range (e.g. 180.0 for full-circle rotated-copy detection).
## `corner_p` / `player_unit` are precomputed by the caller to avoid redundant
## work when this is invoked several times per comparison.
##
## For wide sweeps (used by `_open_rotation_factor`'s 180-deg rotated-copy
## check) this runs a coarse pass first to find the approximate best angle,
## then a fine pass over just the window around it — the same result as a
## uniform fine sweep across the full range, for a fraction of the angle
## steps. Narrow sweeps (the normal +/-45 deg case) go straight to the fine
## step since a coarse pass wouldn't save enough steps to be worth the extra
## bookkeeping.
func _unit_rotation_search(
	player_norm: PackedVector2Array,
	target: TargetData,
	limit_deg := -1.0,
	corner_p: Array[float] = [],
	player_unit: PackedVector2Array = PackedVector2Array()
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
		# Coarse pass: sample every ~4th of the fine step across the full
		# range to find roughly where the best angle lives.
		var coarse_step := fine_step * 4.0
		var coarse_best := 1.0e9
		var coarse_ang := 0.0
		var limit := deg_to_rad(lim)
		var loop_ang := -limit
		while loop_ang <= limit + 0.0001:
			for i in range(player_unit.size()):
				rotated[i] = player_unit[i].rotated(loop_ang) * refit
			var fwd := _min_cyclic_masked(
				rotated, target.unit_points, corner_p, target.corners, false
			)
			var bwd := _min_cyclic_masked(
				rotated, target.unit_rev_points, corner_p, target.rev_corners, false
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
			rotated, target.unit_rev_points, corner_p, target.rev_corners, false
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
