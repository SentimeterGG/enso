extends Node

# Temporary harness: feeds synthetic strokes through draw.gd's real
# _track_direction in wall-clock time and counts draw_direction_changes.

const DrawScript := preload("res://scripts/draw/draw.gd")

var _node: Node = null
var _cases: Array = []
var _idx := 0
var _results: Array = []


func _make_case(label: String, legs: Array, want: int) -> void:
	_cases.append({"label": label, "legs": legs, "want": want, "pos": legs[0][0], "leg": 0})


func _ready() -> void:
	_node = DrawScript.new()
	add_child(_node)
	_node.connect("draw_direction_changes", _on_turn)

	var line := [[Vector2(0, 0), Vector2(600, 0), 700.0]]
	var lshape := [
		[Vector2(0, 0), Vector2(400, 0), 700.0],
		[Vector2(400, 0), Vector2(400, 400), 700.0],
	]
	var square := [
		[Vector2(0, 0), Vector2(400, 0), 700.0],
		[Vector2(400, 0), Vector2(400, 400), 700.0],
		[Vector2(400, 400), Vector2(0, 400), 700.0],
		[Vector2(0, 400), Vector2(0, 0), 700.0],
	]
	var fast_sq := [
		[Vector2(0, 0), Vector2(400, 0), 1500.0],
		[Vector2(400, 0), Vector2(400, 400), 1500.0],
		[Vector2(400, 400), Vector2(0, 400), 1500.0],
		[Vector2(0, 400), Vector2(0, 0), 1500.0],
	]
	var slow_sq := [
		[Vector2(0, 0), Vector2(400, 0), 300.0],
		[Vector2(400, 0), Vector2(400, 400), 300.0],
		[Vector2(400, 400), Vector2(0, 400), 300.0],
		[Vector2(0, 400), Vector2(0, 0), 300.0],
	]
	var repos: Array = []
	for i in 4:
		repos.append([Vector2(0, i * 400), Vector2(400, i * 400), 700.0])
		if i < 3:
			repos.append([Vector2(400, i * 400), Vector2(0, (i + 1) * 400), 6000.0])
	var circle: Array = []
	for i in 41:
		var a := i * TAU / 40.0
		circle.append([Vector2(200, 200) + Vector2(cos(a), sin(a)) * 200.0, Vector2.ZERO, 900.0])

	_make_case("straight line", line, 0)
	_make_case("L", lshape, 1)
	_make_case("L with rounded corner", _rounded(lshape, 30.0, 700.0), 1)
	_make_case("L rounded corner slow", _rounded(lshape, 30.0, 450.0), 1)
	_make_case("square", square, 3)
	_make_case("square rounded corners", _rounded(square, 25.0, 700.0), 3)
	_make_case("square fast", fast_sq, 3)
	_make_case("square slow", slow_sq, 3)
	_make_case("4 lines + fast repositions", repos, 0)
	_make_case("4 lines + medium repositions", _repos(3500.0), 0)
	_make_case("shaky straight line", _jitter(line, 8.0, 700.0), 0)
	_make_case("circle", circle, 0)


func _rounded(legs: Array, radius: float, speed: float) -> Array:
	# Replace each interior corner of the polyline with a quarter-round arc.
	var pts: Array = []
	for i in legs.size():
		pts.append(legs[i][0])
	pts.append(legs[-1][1])
	var out: Array = []
	var cur: Vector2 = pts[0]
	for i in range(1, pts.size() - 1):
		var prev_p: Vector2 = pts[i - 1]
		var corner: Vector2 = pts[i]
		var next_p: Vector2 = pts[i + 1]
		var r: float = minf(
			radius, minf(prev_p.distance_to(corner), next_p.distance_to(corner)) * 0.4
		)
		var enter: Vector2 = corner + (prev_p - corner).normalized() * r
		var exit_p: Vector2 = corner + (next_p - corner).normalized() * r
		out.append([cur, enter, speed])
		var steps := 14
		var arc: float = enter.distance_to(exit_p) * 1.4
		for k in range(1, steps):
			var f: float = float(k) / float(steps)
			var p := enter.lerp(corner, f).lerp(exit_p, f)
			out.append([out[out.size() - 1][1], p, speed])
		cur = exit_p
	out.append([cur, pts[pts.size() - 1], speed])
	return out


func _repos(repo_speed: float) -> Array:
	var legs: Array = []
	for i in 4:
		legs.append([Vector2(0, i * 400), Vector2(400, i * 400), 700.0])
		if i < 3:
			legs.append([Vector2(400, i * 400), Vector2(0, (i + 1) * 400), repo_speed])
	return legs


func _jitter(legs: Array, amount: float, speed: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var out: Array = []
	for leg in legs:
		var a: Vector2 = leg[0]
		var b: Vector2 = leg[1]
		var steps := 40
		var prev := a
		for k in range(1, steps + 1):
			var p := a.lerp(b, float(k) / float(steps))
			if k < steps:
				p += Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))
			out.append([prev, p, speed])
			prev = p
	return out


func _on_turn() -> void:
	var c: Dictionary = _cases[_idx]
	c["got"] = c.get("got", 0) + 1


func _process(delta: float) -> void:
	if _idx >= _cases.size():
		return
	var c: Dictionary = _cases[_idx]
	var legs: Array = c["legs"]
	var leg: int = c["leg"]
	var a: Vector2 = legs[leg][0]
	var b: Vector2 = legs[leg][1]
	var speed: float = legs[leg][2]
	var seg: float = maxf(a.distance_to(b), 0.001)
	var t: float = float(c.get("t", 0.0))
	t += speed * delta / seg
	while t >= 1.0 and leg < legs.size() - 1:
		t -= 1.0
		leg += 1
		a = legs[leg][0]
		b = legs[leg][1]
		speed = legs[leg][2]
		seg = maxf(a.distance_to(b), 0.001)
	c["leg"] = leg
	c["t"] = t
	var pos: Vector2 = a.lerp(b, t)
	c["pos"] = pos
	c["maxrot"] = maxf(
		float(c.get("maxrot", 0.0)),
		absf(rad_to_deg(float(_node.get("_turn_total")) - float(_node.get("_window")[0].y)))
	)
	_node._track_direction(pos)

	if t >= 1.0 and leg == legs.size() - 1:
		var got: int = c.get("got", 0)
		var want: int = c["want"]
		_results.append(
			(
				"%s %-30s %d (want %d) maxrot=%.0f"
				% [
					"ok " if got == want else "BAD",
					c["label"],
					got,
					want,
					float(c.get("maxrot", 0.0))
				]
			)
		)
		print(_results[-1])
		_idx += 1
		if _idx < _cases.size():
			_node.begin(_cases[_idx]["legs"][0][0])
		else:
			for r in _results:
				pass
			get_tree().quit()
