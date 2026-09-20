# hit_result.gd — Single source of truth for rhythm judgement:
# kind enum, timing weights (0..1), label colors, and OD-based windows.
# Replaces the duplicated HitAccuracy enums (judge_spawner, character)
# and the window formulas previously owned by judge_spawner.
class_name HitResult
extends RefCounted

enum Kind { PERFECT, OK, BAD, MISS, BAD_DRAW }

const WEIGHTS := {
	Kind.PERFECT: 1.0,
	Kind.OK: 0.6667,
	Kind.BAD: 0.3334,
	Kind.MISS: 0.0,
}

const LABELS := {
	Kind.PERFECT: "PERFECT",
	Kind.OK: "OK",
	Kind.BAD: "BAD",
	Kind.MISS: "MISS",
	Kind.BAD_DRAW: "BAD DRAWING",
}

const COLORS := {
	Kind.PERFECT: Color(0.0, 0.906, 0.969, 1.0),
	Kind.OK: Color(0.35, 0.95, 0.55),
	Kind.BAD: Color(1.0, 0.60, 0.20),
	Kind.MISS: Color(1.0, 0.30, 0.35),
	Kind.BAD_DRAW: Color(1.0, 0.30, 0.35),
}


static func weight_of(kind: int) -> float:
	return float(WEIGHTS.get(kind, 0.0))


static func excellent_window_ms(od: float) -> float:
	return 50.0 - 3.0 * od


static func good_window_ms(od: float) -> float:
	if od <= 5.0:
		return 120.0 - 8.0 * od
	return 110.0 - 6.0 * od


static func bad_window_ms(od: float) -> float:
	if od <= 5.0:
		return 135.0 - 8.0 * od
	return 120.0 - 5.0 * od


static func classify(error_ms: float, od: float) -> int:
	var timing_error := absf(error_ms) * 1000.0
	if timing_error <= excellent_window_ms(od):
		return Kind.PERFECT
	if timing_error <= good_window_ms(od):
		return Kind.OK
	if timing_error <= bad_window_ms(od):
		return Kind.BAD
	return Kind.MISS
