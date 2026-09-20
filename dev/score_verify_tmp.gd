# tmp verification harness (deleted after run): exercises HitResult + ScoreManager math headless.
extends SceneTree

func _init() -> void:
	var failures := 0
	# 1. classification at OD 5.0: windows 35/80/95
	var od := 5.0
	_check(HitResult.classify(0.02, od) == HitResult.Kind.PERFECT, "perfect", failures)
	failures = _check(HitResult.classify(0.05, od) == HitResult.Kind.OK, "ok", failures)
	failures = _check(HitResult.classify(0.09, od) == HitResult.Kind.BAD, "bad", failures)
	failures = _check(HitResult.classify(0.2, od) == HitResult.Kind.MISS, "miss", failures)
	failures = _check(HitResult.classify(INF, od) == HitResult.Kind.MISS, "inf-miss", failures)

	# 2. multiply model: perfect+ok timing (1.0, 0.6667) x draw 0.8
	var sc := ScoreManager.new()
	sc.reset()
	sc.register_hit(HitResult.Kind.PERFECT, "shape1")
	sc.register_hit(HitResult.Kind.OK, "shape1")
	var s := sc.finish_shape("shape1", 0.8)
	var expected := (1.0 + 0.6667) / 2.0 * 0.8
	failures = _check(absf(s - expected) < 0.001, "multiply shape_score=%f expected=%f" % [s, expected], failures)
	failures = _check(sc.combined_n == 1, "combined_n", failures)
	failures = _check(sc.combo == 2, "combo", failures)

	# 3. bad draw scales down, never negative
	sc.register_hit(HitResult.Kind.PERFECT, "shape2")
	var s2 := sc.finish_shape("shape2", 0.1)
	failures = _check(absf(s2 - 0.1) < 0.0001, "bad-draw scales", failures)
	failures = _check(sc.combined_acc() >= 0.0, "non-negative", failures)

	# 4. aborted draw scores leftover pending as 0
	sc.register_hit(HitResult.Kind.PERFECT, "shape3")
	sc._on_draw_ended()
	failures = _check(sc.combined_n == 3, "abort counted", failures)

	# 5. miss resets combo
	sc.register_hit(HitResult.Kind.MISS, "shape4")
	failures = _check(sc.combo == 0, "miss resets combo", failures)
	sc.finish_shape("shape4", 1.0)

	# 6. draw with no hits nearby -> timing 0, combined 0, no crash
	var sc2 := ScoreManager.new()
	sc2.reset()
	var s3 := sc2.finish_shape("", 0.9)
	failures = _check(absf(s3) < 0.0001, "no-hit draw is 0", failures)

	if failures == 0:
		print("SCORE_VERIFY: ALL PASS")
	else:
		printerr("SCORE_VERIFY: %d FAILURES" % failures)
	sc.free()
	sc2.free()
	quit(failures)


func _check(cond: bool, label: String, failures: int) -> int:
	if cond:
		print("  ok: ", label)
		return failures
	printerr("  FAIL: ", label)
	return failures + 1
