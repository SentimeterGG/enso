extends Control

signal item_hovered(chart_path: String)

const LEVEL_ITEM_SCENE: PackedScene = preload("res://scenes/menus/level_item.tscn")
const BUILTIN_LEVELS_DIR := "res://levels"
const USER_LEVELS_DIR := "user://levels"

var MAX_WIDTH := 750.0
var SELECTED_MAX_WIDTH := 864.0
var MIN_WIDTH := 690.0
const DURATION := 0.25
const COVER_FADE_PX := 660.0
const DRAG_THRESHOLD := 24.0
const ROW_HEIGHT := 120.0
const VARIANT_ROW_HEIGHT := 96.0
const ROW_GAP := 6.0
const ROW_ANIM_DURATION := 0.22
const ROW_SPAWN_STAGGER := 0.04

var selected_index: int = 0
var levels: Array[Dictionary] = []
var skipped_incomplete: int = 0
var skipped_incomplete_paths: Array[String] = []

var _dragging: bool = false
var _press_y: float = 0.0
var _press_scroll_y: float = 0.0
var _drag_dist: float = 0.0
var _center_row: int = 0
var _collapsing: bool = false
var _active_tween: Tween = null
var _highlight_tweens: Array[Tween] = []
var _layout_tweens: Array[Tween] = []

@onready var scroll: Control = $Scroll


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	call_deferred("grab_focus")
	await get_tree().process_frame
	await get_tree().process_frame
	_update_level_size_width()
	_play_intro()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_global_rect().has_point(event.position):
				_begin_drag(event.position.y)
		else:
			if _dragging:
				var was_drag := _drag_dist > DRAG_THRESHOLD
				_end_drag()
				if not was_drag:
					var idx := _item_index_at(event.position)
					if idx >= 0:
						select(idx)
				grab_focus()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to(event.position.y)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		wheel_scroll(-1)
		accept_event()
	elif event.is_action_pressed("ui_down"):
		wheel_scroll(1)
		accept_event()
	elif event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_W:
				wheel_scroll(-1)
				accept_event()
			KEY_S:
				wheel_scroll(1)
				accept_event()


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton and event.pressed
		and event.button_index == MOUSE_BUTTON_WHEEL_UP
	):
		wheel_scroll(-1)
		accept_event()
	elif (
		event is InputEventMouseButton and event.pressed
		and event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	):
		wheel_scroll(1)
		accept_event()


func get_selected_level_index() -> int:
	if levels.is_empty():
		return 0
	if scroll.get_child_count() > 0:
		var item := scroll.get_child(clampi(selected_index, 0, scroll.get_child_count() - 1))
		var id := int(item.get("data_id"))
		if id >= 0 and id < levels.size():
			return id
	return clampi(selected_index, 0, levels.size() - 1)


func get_selected_level() -> Dictionary:
	if levels.is_empty():
		return { }
	return levels[get_selected_level_index()]


func get_selected_chart_path() -> String:
	if scroll.get_child_count() > 0:
		var item := scroll.get_child(clampi(selected_index, 0, scroll.get_child_count() - 1))
		return str(item.get("chart_path"))
	var level := get_selected_level()
	var chart_paths: Array = level.get("chart_paths", [])
	return str(chart_paths[0]) if not chart_paths.is_empty() else ""


func pulse_selected() -> void:
	if scroll.get_child_count() == 0:
		return
	var item := scroll.get_child(clampi(selected_index, 0, scroll.get_child_count() - 1))
	if item.has_method("play_pulse"):
		item.call("play_pulse")


func get_skipped_incomplete_count() -> int:
	return skipped_incomplete


func reload_levels() -> void:
	_clear_items()
	levels = _discover_levels()
	for i in range(levels.size()):
		_populate_level_list(i)
	_layout_rows()
	if levels.is_empty():
		selected_index = 0
	else:
		if Global.current_chart != null and not Global.current_chart.chart_path.is_empty():
			var found := _find_level_index_by_chart(Global.current_chart.chart_path)
			if found != -1:
				selected_index = found
		else:
			selected_index = 0
	select(selected_index)
	if levels.is_empty():
		_update_highlight(true)
		_center_on(0, true)


func _find_level_index_by_chart(chart_path: String) -> int:
	for i in levels.size():
		var chart_paths: Array = (levels[i] as Dictionary).get("chart_paths", [])
		if chart_paths.has(chart_path):
			return i
	return -1


func _populate_level_list(i: int):
	var item: Panel = LEVEL_ITEM_SCENE.instantiate()
	scroll.add_child(item)
	if item.has_method("setup"):
		(
			item.call(
				"setup",
				i,
				levels[i]["title"],
				levels[i]["subtitle"],
				levels[i]["chart_paths"][0],
				levels[i].get("background", ""),
			)
		)
	if item.has_signal("hovered"):
		item.connect("hovered", _on_item_hovered)


func is_dragged() -> bool:
	return _drag_dist > DRAG_THRESHOLD


func select(index: int) -> void:
	if index < 0 or index >= scroll.get_child_count():
		return
	var selected_node = scroll.get_child(index)
	if _collapsing:
		_finish_collapse(selected_index)
		index = selected_node.get_index()
		if index < 0 or index >= scroll.get_child_count():
			return
	if selected_node.get("variant") == true:
		selected_index = index
		_update_highlight(false, DURATION, index)
		_center_on(index)
		return

	if index == selected_index and _has_variant_rows():
		_collapse_variants(index)
		return

	_kill_highlight_tweens()
	_remove_variant_rows()
	var current_index := selected_node.get_index()
	var selected_chart_paths: Array[String] = levels[int(selected_node.get("data_id"))].get(
		"chart_paths"
	)
	for i in range(selected_chart_paths.size()):
		var filename = selected_chart_paths[i].get_file()
		var raw_name = filename.get_basename()
		var finalized_name = raw_name.capitalize()
		var item: Panel = LEVEL_ITEM_SCENE.instantiate()
		scroll.add_child(item)
		if item.has_method("setup"):
			item.call(
				"setup",
				selected_node.get("data_id"),
				finalized_name,
				selected_node.get("level_subtitle"),
				selected_chart_paths[i],
				"",
				true,
			)
		if item.has_signal("hovered"):
			item.connect("hovered", _on_item_hovered)
		scroll.move_child(item, current_index + i + 1)
		item.z_index = 0
		item.set_meta("layout_from_y", _row_y(current_index))
		item.set_meta("layout_delay", float(i) * ROW_SPAWN_STAGGER)
		item.modulate.a = 1.0

	index = current_index
	_layout_rows(true)
	selected_index = current_index + 1 if (current_index + 1) < scroll.get_child_count() else current_index
	_update_highlight()
	_center_on(selected_index)


func _item_index_at(global_pos: Vector2) -> int:
	var best := -1
	var best_dist := INF
	for i in scroll.get_child_count():
		var r := (scroll.get_child(i) as Control).get_global_rect()
		if global_pos.y >= r.position.y and global_pos.y <= r.end.y:
			return i
		var d := absf((r.position.y + r.size.y * 0.5) - global_pos.y)
		if d < best_dist:
			best_dist = d
			best = i
	return best


func _has_variant_rows() -> bool:
	for child in scroll.get_children():
		if child.get("variant") == true:
			return true
	return false


func _remove_variant_rows() -> void:
	for child in scroll.get_children():
		if child.get("variant") == true:
			scroll.remove_child(child)
			child.queue_free()


func _collapse_variants(main_index: int) -> void:
	_collapsing = true
	_kill_highlight_tweens()
	_kill_layout_tweens()
	var variant_count := 0
	for child in scroll.get_children():
		if child.get("variant") == true:
			variant_count += 1
	if variant_count == 0:
		_collapsing = false
		_update_highlight()
		_center_on(main_index)
		return

	var duration := ROW_ANIM_DURATION * 0.8
	var slide_to := _row_y(main_index)
	var tween := create_tween()
	_layout_tweens.append(tween)
	tween.set_parallel(true)
	for child in scroll.get_children():
		var item := child as Control
		if item == null:
			continue
		if item.get("variant") == true:
			(
				tween
				.tween_property(item, "offset_top", slide_to, duration)
				.set_trans(Tween.TRANS_CUBIC)
				.set_ease(Tween.EASE_OUT)
			)
			(
				tween
				.tween_property(item, "offset_bottom", slide_to + _row_height_for(item), duration)
				.set_trans(Tween.TRANS_CUBIC)
				.set_ease(Tween.EASE_OUT)
			)
			var from_width := item.custom_minimum_size.x
			if not is_equal_approx(from_width, MIN_WIDTH):
				(
					tween
					.tween_method(
						func(w: float) -> void:
							_apply_row_width(item, w),
						from_width,
						MIN_WIDTH,
						duration,
					)
					.set_trans(Tween.TRANS_CUBIC)
					.set_ease(Tween.EASE_OUT)
				)
		else:
			var i := item.get_index()
			var target_index := i if i <= main_index else i - variant_count
			var target_y := _row_y_without_variants(target_index)
			if not is_equal_approx(item.offset_top, target_y):
				(
					tween
					.tween_property(item, "offset_top", target_y, duration)
					.set_trans(Tween.TRANS_CUBIC)
					.set_ease(Tween.EASE_OUT)
				)
				(
					tween
					.tween_property(item, "offset_bottom", target_y + ROW_HEIGHT, duration)
					.set_trans(Tween.TRANS_CUBIC)
					.set_ease(Tween.EASE_OUT)
				)
			var target_width := _target_width_for(target_index, main_index)
			var from_width := item.custom_minimum_size.x
			if not is_equal_approx(from_width, target_width):
				(
					tween
					.tween_method(
						func(w: float) -> void:
							_apply_row_width(item, w),
						from_width,
						target_width,
						duration,
					)
					.set_trans(Tween.TRANS_CUBIC)
					.set_ease(Tween.EASE_OUT)
				)
	tween.finished.connect(_finish_collapse.bind(main_index))


func _finish_collapse(main_index: int) -> void:
	_collapsing = false
	_kill_layout_tweens()
	_remove_variant_rows()
	_layout_rows(false)
	if scroll.get_child_count() == 0:
		return
	selected_index = clampi(main_index, 0, scroll.get_child_count() - 1)
	_update_highlight(true)
	_center_on(selected_index)


func select_level(level_index: int) -> void:
	if level_index < 0 or level_index >= levels.size():
		return
	for i in scroll.get_child_count():
		var item := scroll.get_child(i)
		if item.get("variant") == false and int(item.get("data_id")) == level_index:
			select(i)
			return


func wheel_scroll(direction: int) -> void:
	var next := clampi(_center_row + direction, 0, scroll.get_child_count() - 1)
	if next == _center_row:
		return
	_update_highlight(false, DURATION, next)
	_center_on(next)


func _on_item_hovered(chart_path: String) -> void:
	emit_signal("item_hovered", chart_path)


func _clear_items() -> void:
	_collapsing = false
	_kill_highlight_tweens()
	_kill_layout_tweens()
	for child in scroll.get_children():
		scroll.remove_child(child)
		child.queue_free()


func _discover_levels() -> Array[Dictionary]:
	var by_folder: Dictionary = { }
	skipped_incomplete = 0
	skipped_incomplete_paths.clear()
	for base_dir: String in [BUILTIN_LEVELS_DIR, USER_LEVELS_DIR]:
		var chart_paths = _find_charts_in(base_dir)
		var group: Array[String] = []
		for i in range(chart_paths.size()):
			if ChartParser.has_unsetup_notes(chart_paths[i]):
				skipped_incomplete += 1
				skipped_incomplete_paths.append(chart_paths[i])
				continue

			if group.is_empty():
				group.append(chart_paths[i])
			elif chart_paths[i].get_base_dir() == group[0].get_base_dir():
				group.append(chart_paths[i])
			else:
				var key := _dedupe_key(group[0])
				by_folder[key] = _make_entry(group)
				group = [chart_paths[i]] # Reset group with the new path

		if not group.is_empty():
			var key := _dedupe_key(group[0])
			by_folder[key] = _make_entry(group)
	var out: Array[Dictionary] = []
	for key in by_folder:
		out.append(by_folder[key])
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["title"]).to_lower() < str(b["title"]).to_lower(),
	)
	return out


func _dedupe_key(chart_path: String) -> String:
	return chart_path.get_base_dir().get_file()


func _find_charts_in(base_dir: String) -> Array[String]:
	var out: Array[String] = []
	if base_dir == USER_LEVELS_DIR:
		_ensure_dir(base_dir)
	if not DirAccess.dir_exists_absolute(base_dir):
		return out
	for sub in DirAccess.get_directories_at(base_dir):
		var folder := base_dir.path_join(sub)
		for f in DirAccess.get_files_at(folder):
			if f.get_extension().to_lower() == "enso":
				out.append(folder.path_join(f))
		if out.is_empty():
			continue
	out.sort()
	return out


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	DirAccess.make_dir_recursive_absolute(path)


func _make_entry(chart_paths: Array[String]) -> Dictionary:
	var meta := _read_chart_metadata(chart_paths[0])
	var title := (
		str(meta.get("name", "")).strip_edges() + " by " + str(meta.get("source", "")).strip_edges()
	)
	var subtitle := "MAPPED BY " + str(meta.get("mapper", "")).strip_edges()
	var background := str(meta.get("bg", "")).strip_edges()
	if (
		not background.is_empty() and not background.begins_with("res://")
		and not background.begins_with("user://")
	):
		background = chart_paths[0].get_base_dir().path_join(background).simplify_path()
	return {
		"title": title,
		"subtitle": subtitle,
		"chart_paths": chart_paths,
		"background": background,
	}


func _read_chart_metadata(chart_path: String) -> Dictionary:
	var meta: Dictionary = ChartParser.parse_metadata(chart_path)
	return meta


func _play_intro() -> void:
	if scroll.get_child_count() == 0:
		return
	var target: float = _target_y_for(selected_index)
	scroll.position.y = target + size.y * 0.6
	_kill_scroll_tween()
	_active_tween = create_tween()
	(
		_active_tween
		.tween_property(scroll, "position:y", target, 1)
		.set_trans(Tween.TRANS_CUBIC)
		.set_ease(Tween.EASE_OUT)
	)


func _center_on(index: int, instant: bool = false) -> void:
	if scroll.get_child_count() == 0:
		return
	_center_row = clampi(index, 0, scroll.get_child_count() - 1)
	var target: float = _target_y_for(index)
	_kill_scroll_tween()
	_active_tween = create_tween()
	if instant:
		_active_tween.tween_property(scroll, "position:y", target, 0.0)
	else:
		(
			_active_tween
			.tween_property(scroll, "position:y", target, DURATION)
			.set_trans(Tween.TRANS_CUBIC)
			.set_ease(Tween.EASE_OUT)
		)


func _begin_drag(y: float) -> void:
	_dragging = true
	_press_y = y
	_press_scroll_y = scroll.position.y
	_drag_dist = 0.0
	_kill_scroll_tween()
	_kill_highlight_tweens()


func _drag_to(y: float) -> void:
	var delta: float = y - _press_y
	_drag_dist = maxf(_drag_dist, absf(delta))
	if _drag_dist <= DRAG_THRESHOLD:
		return # still a click: don't move the list or touch selection
	scroll.position.y = _clamp_y(_press_scroll_y + delta)
	_update_coverflow_live()


func _end_drag() -> void:
	_dragging = false
	if _drag_dist > DRAG_THRESHOLD:
		var nearest: int = _nearest_index_to_center()
		_update_highlight(false, DURATION, nearest)
		_center_on(nearest)


func _kill_scroll_tween() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null


func _row_y(index: int) -> float:
	var y := 0.0
	var count := mini(index, scroll.get_child_count())
	for i in count:
		y += _row_height_for(scroll.get_child(i) as Control) + ROW_GAP
	return y


func _row_y_without_variants(index: int) -> float:
	var y := 0.0
	var seen := 0
	for i in scroll.get_child_count():
		if seen >= index:
			break
		var item := scroll.get_child(i) as Control
		if item == null or item.get("variant") == true:
			continue
		y += _row_height_for(item) + ROW_GAP
		seen += 1
	return y


func _item_center(index: int) -> float:
	if index < 0 or index >= scroll.get_child_count():
		return 0.0
	var item := scroll.get_child(index) as Control
	return _row_y(index) + _row_height_for(item) * 0.5


func _center_y() -> float:
	return size.y * 0.5


func _target_y_for(index: int) -> float:
	return _clamp_y(_center_y() - _item_center(index))


func _min_y() -> float:
	if scroll.get_child_count() == 0:
		return 0.0
	return _center_y() - _item_center(scroll.get_child_count() - 1)


func _max_y() -> float:
	if scroll.get_child_count() == 0:
		return 0.0
	return _center_y() - _item_center(0)


func _clamp_y(y: float) -> float:
	return clampf(y, minf(_min_y(), _max_y()), maxf(_min_y(), _max_y()))


func _nearest_index_to_center() -> int:
	if scroll.get_child_count() == 0:
		return 0
	var center_local: float = _center_y() - scroll.position.y
	var best: int = selected_index
	var best_dist: float = INF
	for i in scroll.get_child_count():
		var d: float = absf(_item_center(i) - center_local)
		if d < best_dist:
			best_dist = d
			best = i
	return best


func _kill_highlight_tweens() -> void:
	for t in _highlight_tweens:
		if t and t.is_valid():
			t.kill()
	_highlight_tweens.clear()


func _layout_rows(animate: bool = false) -> void:
	_kill_layout_tweens()
	for i in scroll.get_child_count():
		var item := scroll.get_child(i) as Control
		if item == null:
			continue
		_set_row_width(item, item.custom_minimum_size.x)
		if animate:
			_animate_row_into_slot(item, i)
		else:
			_set_row_y(item, _row_y(i))


func _animate_row_into_slot(item: Control, index: int) -> void:
	var target_y := _row_y(index)
	if item.has_meta("layout_from_y"):
		_set_row_y(item, float(item.get_meta("layout_from_y")))
		item.remove_meta("layout_from_y")
	var delay := 0.0
	if item.has_meta("layout_delay"):
		delay = float(item.get_meta("layout_delay"))
		item.remove_meta("layout_delay")
	var current_y := item.offset_top
	if is_equal_approx(current_y, target_y):
		_set_row_y(item, target_y)
		return
	var tween := create_tween()
	_layout_tweens.append(tween)
	tween.set_parallel(true)
	(
		tween
		.tween_property(item, "offset_top", target_y, ROW_ANIM_DURATION)
		.set_delay(delay)
		.set_trans(Tween.TRANS_CUBIC)
		.set_ease(Tween.EASE_OUT)
	)
	(
		tween
		.tween_property(item, "offset_bottom", target_y + _row_height_for(item), ROW_ANIM_DURATION)
		.set_delay(delay)
		.set_trans(Tween.TRANS_CUBIC)
		.set_ease(Tween.EASE_OUT)
	)


func _apply_row_width(item: Control, width: float) -> void:
	if not is_instance_valid(item):
		return
	_set_row_width(item, width)


func _set_row_width(item: Control, width: float) -> void:
	var max_width := SELECTED_MAX_WIDTH
	if scroll.size.x > 0.0:
		max_width = minf(max_width, scroll.size.x)
	var w := clampf(width, minf(MIN_WIDTH, max_width), max_width)
	var h := _row_height_for(item)
	item.custom_minimum_size = Vector2(w, h)
	item.custom_maximum_size = Vector2(w, h)
	item.anchor_left = 1.0
	item.anchor_right = 1.0
	item.anchor_top = 0.0
	item.anchor_bottom = 0.0
	item.offset_left = -w
	item.offset_right = 0.0


func _row_height_for(item: Control) -> float:
	if item != null and item.get("variant") == true:
		return VARIANT_ROW_HEIGHT
	return ROW_HEIGHT


func _set_row_y(item: Control, y: float) -> void:
	item.offset_top = y
	item.offset_bottom = y + _row_height_for(item)


func _kill_layout_tweens() -> void:
	for t in _layout_tweens:
		if t and t.is_valid():
			t.kill()
	_layout_tweens.clear()


func _full_width_rows() -> Array[int]:
	var rows: Array[int] = []
	if scroll.get_child_count() == 0:
		return rows
	rows.append(clampi(selected_index, 0, scroll.get_child_count() - 1))
	var parent := _selected_parent_row()
	if parent >= 0:
		rows.append(parent)
	return rows


func _selected_parent_row() -> int:
	if scroll.get_child_count() == 0:
		return -1
	var selected := clampi(selected_index, 0, scroll.get_child_count() - 1)
	var item := scroll.get_child(selected)
	if item == null or item.get("variant") != true:
		return -1
	for i in range(selected - 1, -1, -1):
		var parent := scroll.get_child(i)
		if parent != null and parent.get("variant") != true:
			return i
	return -1


func _update_level_size_width():
	SELECTED_MAX_WIDTH = size.x
	MAX_WIDTH = size.x * 0.8681
	MIN_WIDTH = size.x * 0.7986


func _on_resized() -> void:
	_update_level_size_width()
	if scroll.get_child_count() > 0:
		_update_highlight(true)


func _update_coverflow_live() -> void:
	if scroll.get_child_count() == 0:
		return
	_kill_highlight_tweens()
	var full_width := _full_width_rows()
	var parent_row := _selected_parent_row()
	var center_local: float = _center_y() - scroll.position.y
	for i in scroll.get_child_count():
		var item := scroll.get_child(i) as Control
		if item == null:
			continue
		var dist_px: float = absf(_item_center(i) - center_local)
		var t: float = clampf(dist_px / COVER_FADE_PX, 0.0, 1.0)
		var width: float = lerpf(MAX_WIDTH, MIN_WIDTH, t)
		if i in full_width:
			width = SELECTED_MAX_WIDTH
		_apply_row_width(item, width)
		if item.has_method("set_selected"):
			item.set_selected(i == selected_index)
		if item.has_method("set_parent_focused"):
			item.set_parent_focused(i == parent_row)


func _target_width_for(index: int, center_row: int) -> float:
	var dist := absi(index - center_row)
	return maxf(MIN_WIDTH, MAX_WIDTH - float(dist) * ((MAX_WIDTH - MIN_WIDTH) / 5.0))


func _update_highlight(
	instant: bool = false,
	duration: float = DURATION,
	center_row: int = -1,
) -> void:
	if center_row < 0:
		center_row = selected_index
	_kill_highlight_tweens()
	var full_width := _full_width_rows()
	var parent_row := _selected_parent_row()
	for i in scroll.get_child_count():
		var item := scroll.get_child(i) as Control
		if item == null:
			continue
		var width := _target_width_for(i, center_row)
		if i in full_width:
			width = SELECTED_MAX_WIDTH
		if instant:
			_apply_row_width(item, width)
		else:
			var from: float = item.custom_minimum_size.x
			var tween := create_tween()
			_highlight_tweens.append(tween)
			(
				tween
				.tween_method(
					func(w: float) -> void:
						_apply_row_width(item, w),
					from,
					width,
					duration,
				)
				.set_trans(Tween.TRANS_CUBIC)
				.set_ease(Tween.EASE_OUT)
			)
		if item.has_method("set_selected"):
			item.set_selected(i == selected_index)
		if item.has_method("set_parent_focused"):
			item.set_parent_focused(i == parent_row)
