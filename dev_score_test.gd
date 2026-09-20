extends SceneTree

func _init() -> void:
	process_frame.connect(_run)


func _run() -> void:
	process_frame.disconnect(_run)
	var g := root.get_node_or_null("Global")
	if g == null:
		print("TEST FAIL no Global autoload")
		quit()
		return
	var chart := ChartData.new()
	chart.metadata = {"name": "T", "overall_difficulty": "7"}
	chart.notes = [
		{"time": 1000.0, "x": 0.0, "y": 0.0, "id": "sq"},
		{"time": 1200.0, "x": 1.0, "y": 0.0, "id": "sq"},
		{"time": 1400.0, "x": 1.0, "y": 1.0, "id": "sq"},
		{"time": 1600.0, "x": 0.0, "y": 1.0, "id": "sq"},
		{"time": 2000.0, "x": 0.5, "y": 0.5, "id": "solo_1"},
	]
	chart.shapes = [
		PackedVector2Array([Vector2(0, 0), Vector2(1, 1)]),
		PackedVector2Array([Vector2(0.5, 0.5)]),
	]
	chart.shape_times = [[1000.0, 1600.0], [2000.0, 2000.0]]
	chart.shape_ids = ["sq", "solo_1"]
	chart.build_shape_colors()
	chart.build_runtime_index()
	g.set("current_chart", chart)

	var sm := ScoreManager.new()
	var lbl := Label.new()
	lbl.name = "avg_accuracy"
	sm.add_child(lbl)
	root.add_child(sm)
	print("TEST start combined=", sm.combined_acc(), " n=", sm.combined_n)
	sm.register_hit(HitResult.Kind.MISS, "sq")
	sm.register_hit(HitResult.Kind.MISS, "sq")
	sm.register_hit(HitResult.Kind.MISS, "sq")
	print("TEST 3of4 miss combined=", sm.combined_acc(), " n=", sm.combined_n)
	sm.register_hit(HitResult.Kind.MISS, "sq")
	print("TEST 4of4 miss combined=", sm.combined_acc(), " n=", sm.combined_n, " miss=", sm.counts[HitResult.Kind.MISS])
	sm.register_hit(HitResult.Kind.MISS, "solo_1")
	print("TEST solo miss combined=", sm.combined_acc(), " n=", sm.combined_n)
	sm.begin_shape("sq2")
	sm.register_hit(HitResult.Kind.PERFECT, "sq2")
	print("TEST drawn pending=", sm._pending.has("sq2"), " combined_n=", sm.combined_n)
	sm.finish_shape("sq2", 0.8)
	print("TEST drawn finished combined=", sm.combined_acc(), " n=", sm.combined_n)
	quit()
