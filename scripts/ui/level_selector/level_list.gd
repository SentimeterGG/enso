# level_list.gd — Scrollable coverflow level list: discovers charts dynamically
# from res://levels and user://levels (each subfolder / *.enso is one level),
# builds level_item rows from their [metadata], and manages selection,
# centering and coverflow-width highlight with tweens, plus mouse drag, wheel
# and keyboard (up/down/W/S) navigation, with drag-vs-click disambiguation
# and an intro slide-in animation.
# RETURN: centered, highlighted selection of the current row
extends Control

const LEVEL_ITEM_SCENE: PackedScene = preload("res://scenes/level_item.tscn")
const BUILTIN_LEVELS_DIR := "res://levels"
const USER_LEVELS_DIR := "user://levels"
const SUBTITLE_KEYS: Array[String] = [
	"artist", "author", "charter", "creator", "mapper", "by", "chart_by"
]

const MAX_WIDTH := 260.0
const MIN_WIDTH := 140.0
const DURATION := 0.25
const COVER_FADE_PX := 220.0
const DRAG_THRESHOLD := 8.0

var selected_index: int = 0
## One entry per discovered level: {title, subtitle, chart_path, is_user}.
var levels: Array[Dictionary] = []
## Charts skipped by _discover_levels() for holding solo/unsetup notes.
var skipped_incomplete: int = 0
## Paths skipped for the same reason (for notifications/debugging).
var skipped_incomplete_paths: Array[String] = []
var _dragging: bool = false
var _press_y: float = 0.0
var _press_scroll_y: float = 0.0
var _drag_dist: float = 0.0
var _active_tween: Tween = null
var _highlight_tweens: Array[Tween] = []
@onready var scroll: VBoxContainer = $Scroll
signal item_hovered(chart_path: String)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	reload_levels(false)
	call_deferred("grab_focus")
	await get_tree().process_frame
	await get_tree().process_frame
	_play_intro()


func get_selected_level() -> Dictionary:
	if levels.is_empty():
		return {}
	return levels[clampi(selected_index, 0, levels.size() - 1)]


func get_selected_chart_path() -> String:
	var level := get_selected_level()
	return str(level.get("chart_path", ""))


## Incomplete charts hidden by the last reload (solo/unsetup notes).
func get_skipped_incomplete_count() -> int:
	return skipped_incomplete


func reload_levels(keep_selection: bool = true) -> void:
	var previous_path := get_selected_chart_path() if keep_selection else ""
	_clear_items()
	levels = _discover_levels()
	for entry in levels:
		var item := LEVEL_ITEM_SCENE.instantiate()
		scroll.add_child(item)
		if item.has_method("setup"):
			item.call("setup", entry["title"], entry["subtitle"], entry["chart_path"])
		if item.has_signal("hovered"):
			item.connect("hovered", _on_item_hovered)
	selected_index = 0
	if keep_selection and not previous_path.is_empty():
		for i in levels.size():
			if str(levels[i].get("chart_path", "")) == previous_path:
				selected_index = i
				break
	if levels.is_empty():
		selected_index = 0
	else:
		selected_index = clampi(selected_index, 0, levels.size() - 1)
	_update_highlight(true)
	_center_on(selected_index, true)


func _on_item_hovered(chart_path: String) -> void:
	emit_signal("item_hovered", chart_path)


func _clear_items() -> void:
	# remove_child must stay: queue_free() is deferred to end of frame, so
	# without the synchronous detach the stale placeholder rows would still
	# occupy indices 0..n while reload_levels() highlights/centers the fresh
	# rows below in the same call.
	for child in scroll.get_children():
		scroll.remove_child(child)
		child.queue_free()


## Scans res://levels and user://levels. Each subfolder containing a *.enso
## file (preferring chart.enso) counts as one level; loose *.enso files
## directly inside the folder also count. Entries with the same folder name in
## both locations collapse with the user:// copy winning. Sorted by title.
## Charts holding solo/unsetup notes ([[solo_N]] / header-less @) are
## incomplete and skipped (counted in skipped_incomplete).
func _discover_levels() -> Array[Dictionary]:
	var by_folder: Dictionary = {}
	skipped_incomplete = 0
	skipped_incomplete_paths.clear()
	for base_dir: String in [BUILTIN_LEVELS_DIR, USER_LEVELS_DIR]:
		for chart_path in _find_charts_in(base_dir):
			if ChartParser.has_unsetup_notes(chart_path):
				skipped_incomplete += 1
				skipped_incomplete_paths.append(chart_path)
				continue
			var key := _dedupe_key(chart_path, base_dir)
			by_folder[key] = _make_entry(chart_path)
	var out: Array[Dictionary] = []
	for key in by_folder:
		out.append(by_folder[key])
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["title"]).to_lower() < str(b["title"]).to_lower()
	)
	return out


func _dedupe_key(chart_path: String, base_dir: String) -> String:
	# Subfolder levels collapse on folder name (user:// wins); loose *.enso
	# files directly in the levels dir collapse on file name instead so they
	# never collide with the folder entries.
	if chart_path.get_base_dir() == base_dir:
		return "::file::" + chart_path.get_file()
	return chart_path.get_base_dir().get_file()


func _find_charts_in(base_dir: String) -> Array[String]:
	var out: Array[String] = []
	if base_dir == USER_LEVELS_DIR:
		_ensure_dir(base_dir)
	if not DirAccess.dir_exists_absolute(base_dir):
		return out
	for sub in DirAccess.get_directories_at(base_dir):
		var folder := base_dir.path_join(sub)
		var candidates: Array[String] = []
		for f in DirAccess.get_files_at(folder):
			if f.get_extension().to_lower() == "enso":
				candidates.append(f)
		if candidates.is_empty():
			continue
		candidates.sort()
		var picked := "chart.enso"
		if not candidates.has(picked):
			picked = candidates[0]
		out.append(folder.path_join(picked))
	for f in DirAccess.get_files_at(base_dir):
		if f.get_extension().to_lower() == "enso":
			out.append(base_dir.path_join(f))
	out.sort()
	return out


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	DirAccess.make_dir_recursive_absolute(path)


func _make_entry(chart_path: String) -> Dictionary:
	var meta := _read_chart_metadata(chart_path)
	var title := (
		str(meta.get("name", "")).strip_edges() + " by " + str(meta.get("source", "")).strip_edges()
	)
	var subtitle := "MAPPED BY " + str(meta.get("mapper", "")).strip_edges()
	return {"title": title, "subtitle": subtitle, "chart_path": chart_path}


## Lightweight [metadata]-only parse (no note loading) so the list stays fast.
## Mirrors ChartParser comment handling: "#" starts a comment only at line
## start or after whitespace, so hex colors like "#EEB8C4" survive.
func _read_chart_metadata(chart_path: String) -> Dictionary:
	var meta: Dictionary = ChartParser.parse_metadata(chart_path)
	return meta


func is_dragged() -> bool:
	return _drag_dist > DRAG_THRESHOLD


func _play_intro() -> void:
	if scroll.get_child_count() == 0:
		return
	var target: float = _target_y_for(selected_index)
	scroll.position.y = target + size.y * 0.6
	_kill_scroll_tween()
	_active_tween = create_tween()
	(
		_active_tween
		. tween_property(scroll, "position:y", target, 1)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)


func select(index: int) -> void:
	if index < 0 or index >= scroll.get_child_count():
		return
	if index == selected_index:
		return
	selected_index = index
	_update_highlight()
	_center_on(index)


func _center_on(index: int, instant: bool = false) -> void:
	if scroll.get_child_count() == 0:
		return
	var target: float = _target_y_for(index)
	_kill_scroll_tween()
	_active_tween = create_tween()
	if instant:
		_active_tween.tween_property(scroll, "position:y", target, 0.0)
	else:
		(
			_active_tween
			. tween_property(scroll, "position:y", target, DURATION)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)


func wheel_scroll(direction: int) -> void:
	select(clampi(selected_index + direction, 0, scroll.get_child_count() - 1))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		wheel_scroll(-1)
		accept_event()
	elif event.is_action_pressed("ui_down"):
		wheel_scroll(1)
		accept_event()
	elif event is InputEventKey and event.pressed:
		# Arrows are already covered by ui_up/ui_down above; only WASD adds anything.
		match event.physical_keycode:
			KEY_W:
				wheel_scroll(-1)
				accept_event()
			KEY_S:
				wheel_scroll(1)
				accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_global_rect().has_point(event.position):
				_begin_drag(event.position.y)
		else:
			if _dragging:
				_end_drag()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to(event.position.y)


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_WHEEL_UP
	):
		wheel_scroll(-1)
		accept_event()
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	):
		wheel_scroll(1)
		accept_event()


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
	scroll.position.y = _clamp_y(_press_scroll_y + delta)
	_refresh_selection_to_center()
	_update_coverflow_live()


func _end_drag() -> void:
	_dragging = false
	if _drag_dist > DRAG_THRESHOLD:
		_snap_to_center()
	# Keep _drag_dist so item release (which arrives after _input)
	# can still tell this was a drag, not a click.


func _kill_scroll_tween() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null


func _item_center(index: int) -> float:
	var item := scroll.get_child(index)
	return item.position.y + item.size.y * 0.5


func _target_y_for(index: int) -> float:
	return _clamp_y(size.y * 0.5 - _item_center(index))


func _min_y() -> float:
	if scroll.get_child_count() == 0:
		return 0.0
	return size.y * 0.5 - _item_center(scroll.get_child_count() - 1)


func _max_y() -> float:
	if scroll.get_child_count() == 0:
		return 0.0
	return size.y * 0.5 - _item_center(0)


func _clamp_y(y: float) -> float:
	return clampf(y, minf(_min_y(), _max_y()), maxf(_min_y(), _max_y()))


func _nearest_index_to_center() -> int:
	if scroll.get_child_count() == 0:
		return 0
	var center_local: float = size.y * 0.5 - scroll.position.y
	var best: int = selected_index
	var best_dist: float = INF
	for i in scroll.get_child_count():
		var d: float = absf(_item_center(i) - center_local)
		if d < best_dist:
			best_dist = d
			best = i
	return best


func _refresh_selection_to_center() -> void:
	# Called every motion event while dragging so selected_index tracks
	# whatever item is under the vertical center. Visuals are handled by
	# _update_coverflow_live() right after (pixel-perfect, no tween lag);
	# the tweened settle happens in _snap_to_center() on release.
	var nearest: int = _nearest_index_to_center()
	if nearest == selected_index:
		return
	selected_index = nearest


func _snap_to_center() -> void:
	# Force a snap even if _refresh_selection_to_center() already
	# set selected_index (select() would early-return and skip centering).
	var nearest: int = _nearest_index_to_center()
	selected_index = nearest
	_update_highlight()
	_center_on(nearest)


func _kill_highlight_tweens() -> void:
	for t in _highlight_tweens:
		if t and t.is_valid():
			t.kill()
	_highlight_tweens.clear()


func _update_coverflow_live() -> void:
	# Pixel-perfect coverflow while the finger is down: widths follow the
	# true distance to the vertical center, so items grow/shrink smoothly
	# as they pass through the middle (no discrete popping).
	if scroll.get_child_count() == 0:
		return
	_kill_highlight_tweens()
	var center_local: float = size.y * 0.5 - scroll.position.y
	for i in scroll.get_child_count():
		var item := scroll.get_child(i)
		var dist_px: float = absf(_item_center(i) - center_local)
		var t: float = clampf(dist_px / COVER_FADE_PX, 0.0, 1.0)
		var width: float = lerpf(MAX_WIDTH, MIN_WIDTH, t)
		item.custom_minimum_size = Vector2(width, item.custom_minimum_size.y)
		if item.has_method("set_selected"):
			item.set_selected(i == selected_index)


func _update_highlight(instant: bool = false, duration: float = DURATION) -> void:
	_kill_highlight_tweens()
	for i in scroll.get_child_count():
		var item := scroll.get_child(i)
		var dist := absi(i - selected_index)
		var width: float = MAX_WIDTH - float(dist) * ((MAX_WIDTH - MIN_WIDTH) / 5.0)
		width = maxf(MIN_WIDTH, width)
		if instant:
			item.custom_minimum_size = Vector2(width, item.custom_minimum_size.y)
		else:
			var tween := create_tween()
			_highlight_tweens.append(tween)
			(
				tween
				. tween_property(item, "custom_minimum_size:x", width, duration)
				. set_trans(Tween.TRANS_CUBIC)
				. set_ease(Tween.EASE_OUT)
			)
		if item.has_method("set_selected"):
			item.set_selected(i == selected_index)
