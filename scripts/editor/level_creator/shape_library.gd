class_name ShapeLibrary
extends RefCounted

## Shape definitions shared by the editor canvas and the exporter.
## All point coordinates are normalized to the 0..1 range.

const CUSTOM := "Custom"

const NAMES := [
	"L",
	"L90",
	"L180",
	"L270",
	"LFlip",
	"U",
	"UInv",
	"Square",
	"Triangle",
	"HLine",
	"VLine",
	"Diag",
	"DiagInv",
	"ZigZag",
]

const POINTS := {
	"L": [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)],
	"L90": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	"L180": [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	"L270": [Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)],
	"LFlip": [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)],
	"U": [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)],
	"UInv": [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	"Square": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)],
	"Triangle": [Vector2(0.5, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0.5, 0)],
	"HLine": [Vector2(0, 0.5), Vector2(1, 0.5)],
	"VLine": [Vector2(0.5, 0), Vector2(0.5, 1)],
	"Diag": [Vector2(0, 0), Vector2(1, 1)],
	"DiagInv": [Vector2(1, 0), Vector2(0, 1)],
	"ZigZag": [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)],
}


static func points(shape_name: String) -> PackedVector2Array:
	return PackedVector2Array(POINTS.get(shape_name, POINTS["Square"]))


static func is_closed_by_default(shape_name: String) -> bool:
	return shape_name == "Square" or shape_name == "Triangle"


static func required_beats(shape_name: String, selected_count: int) -> int:
	if shape_name == CUSTOM:
		return maxi(1, selected_count)
	return maxi(1, points(shape_name).size() - 1)


static func matches(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


static func infer_name(count: int, pts: PackedVector2Array) -> String:
	match count:
		4:
			return "Square"
		3:
			for candidate in ["Triangle", "ZigZag", "UInv", "U"]:
				if matches(pts, points(candidate)):
					return candidate
			return "U"
		2:
			for candidate in ["L", "L90", "L180", "L270", "LFlip"]:
				if matches(pts, points(candidate)):
					return candidate
			return "L"
		1:
			return _infer_single_point_shape(pts)
	return ""


static func _infer_single_point_shape(pts: PackedVector2Array) -> String:
	if matches(pts, points("Diag")):
		return "Diag"
	if matches(pts, points("DiagInv")):
		return "DiagInv"
	if pts.size() < 2:
		return "HLine"
	var dx := 0.0
	var dy := 0.0
	for i in range(1, pts.size()):
		dx = maxf(dx, absf(pts[i].x - pts[i - 1].x))
		dy = maxf(dy, absf(pts[i].y - pts[i - 1].y))
	if matches(pts, points("VLine")) or dy > dx:
		return "VLine"
	if matches(pts, points("HLine")):
		return "HLine"
	return "HLine"
