class_name ChartParser
extends RefCounted


static func load(path: String) -> ChartData:
	var chart := ChartData.new()
	chart.chart_path = path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Could not open chart: " + path)
		return chart
	var section := ""
	var metadata := { }
	var note_points: Array = []
	var parsed_shapes: Array = []
	var current_shape: Dictionary = { }
	for raw_line in f.get_as_text().split("\n"):
		var line := _strip_comment(raw_line).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("[") and line.ends_with("]") and line.length() > 2:
			if line.begins_with("[(") or line.begins_with("[["):
				if not current_shape.is_empty():
					_apply_shape_start(current_shape)
					_close_shape(current_shape)
					parsed_shapes.append(current_shape)
				current_shape = {
					"name": _shape_name(line),
					"closed": not line.begins_with("[["),
					"points": [],
				}
				continue
			section = line.substr(1, line.length() - 2).strip_edges()
			continue
		match section:
			"metadata":
				var kv := line.split("=", true, 1)
				if kv.size() == 2:
					metadata[kv[0].strip_edges()] = kv[1].strip_edges()
			"notes":
				var tokens := line.split(" ", false)
				match tokens[0]:
					"@": # note point: @ <time_ms> [<x> <y>]; solo/unsetup notes may omit coords (default 0.5 0.5)
						if tokens.size() >= 2:
							var px := 0.5
							var py := 0.5
							if tokens.size() >= 4:
								px = float(tokens[2])
								py = float(tokens[3])
							var point := {
								"time": float(tokens[1]),
								"x": px,
								"y": py,
								"id": str(current_shape.get("name", "")),
							}
							note_points.append(point)
							if current_shape.is_empty():
								current_shape = { "name": "", "closed": true, "points": [] }
							current_shape["points"].append(point)
					"!": # geometry point: <x> <y>, no timestamp
						if tokens.size() >= 3 and not current_shape.is_empty():
							current_shape["points"].append(
								{ "x": float(tokens[1]), "y": float(tokens[2]) }
							)
	if not current_shape.is_empty():
		_apply_shape_start(current_shape)
		_close_shape(current_shape)
		parsed_shapes.append(current_shape)
	note_points.sort_custom(
		func(a, b):
			return a.time < b.time,
	)
	parsed_shapes.sort_custom(
		func(a, b):
			return a.start_time < b.start_time,
	)
	for shape in parsed_shapes:
		var pts := PackedVector2Array()
		for p in shape.points:
			pts.append(Vector2(p.x, p.y))
		chart.shapes.append(pts)
		chart.shape_times.append([shape.start_time, shape.hit_time])
		chart.shape_ids.append(str(shape.get("name", "")))
	chart.metadata = metadata
	chart.notes = note_points
	chart.build_shape_colors()
	chart.build_runtime_index()
	return chart


static func parse_metadata(path: String) -> Dictionary:
	var metadata := { }
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Could not open chart: " + path)
		return metadata
	var section := ""
	for raw_line in f.get_as_text().split("\n"):
		var line := _strip_comment(raw_line).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("[") and line.ends_with("]") and line.length() > 2:
			if line.begins_with("[(") or line.begins_with("[["):
				if section.to_lower() == "metadata":
					break
				continue
			if section.to_lower() == "metadata" and not metadata.is_empty():
				break
			section = line.substr(1, line.length() - 2).strip_edges()
			continue
		if section.to_lower() != "metadata":
			continue
		var kv := line.split("=", true, 1)
		if kv.size() == 2:
			metadata[kv[0].strip_edges().to_lower()] = _unquote_value(kv[1].strip_edges())
	return metadata


static func _unquote_value(value: String) -> String:
	var v := value.strip_edges()
	if v.length() >= 2:
		var first := v[0]
		var last := v[v.length() - 1]
		if (first == '"' and last == '"') or (first == "'" and last == "'"):
			return v.substr(1, v.length() - 2)
	return v


static func _shape_name(header: String) -> String:
	return (
		header
		.strip_edges()
		.trim_prefix("[(")
		.trim_prefix("[[")
		.trim_suffix(")]")
		.trim_suffix("]]")
		.strip_edges()
	)


static func _strip_comment(raw: String) -> String:
	if raw.begins_with("#"):
		return ""
	var cut := raw.find(" #")
	if cut == -1:
		cut = raw.find("\t#")
	return raw if cut == -1 else raw.substr(0, cut)


static func _apply_shape_start(shape: Dictionary) -> void:
	var start := 1.0e9
	var hit := -1.0e9
	for p in shape.get("points", []):
		if p.has("time"):
			start = minf(start, float(p.time))
			hit = maxf(hit, float(p.time))
	if start > 1.0e8:
		start = 0.0
	if hit < -1.0e8:
		hit = start
	shape["start_time"] = start
	shape["hit_time"] = hit


static func _close_shape(shape: Dictionary) -> void:
	if not shape.get("closed", false):
		return
	var pts: Array = shape.get("points", [])
	if pts.size() < 2:
		return
	var first: Dictionary = pts[0]
	var last: Dictionary = pts[pts.size() - 1]
	if Vector2(first.x, first.y).is_equal_approx(Vector2(last.x, last.y)):
		return
	pts.append(first.duplicate())


static func is_solo_id(shape_id: String) -> bool:
	return shape_id.strip_edges().to_lower().begins_with("solo")


static func has_unsetup_notes(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var section := ""
	var in_shape := false
	for raw_line in f.get_as_text().split("\n"):
		var line := _strip_comment(raw_line).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("[") and line.ends_with("]") and line.length() > 2:
			if line.begins_with("[[") or line.begins_with("[("):
				if section == "notes":
					if is_solo_id(_shape_name(line)):
						return true
					in_shape = true
				continue
			section = line.substr(1, line.length() - 2).strip_edges().to_lower()
			in_shape = false
			continue
		if section == "notes" and (line == "@" or line.begins_with("@ ")):
			if not in_shape:
				return true
	return false
