extends Control

const EDITOR_BEAT_POINT := preload("res://scenes/editor/editor_beat_point.tscn")
const EDITOR_SHAPE_POINT := preload("res://scenes/editor/editor_shape_point.tscn")
const SHAPE_NAMES := ShapeLibrary.NAMES
const CUSTOM_SHAPE_NAME := ShapeLibrary.CUSTOM
const DELETE_WINDOW_SEC := 0.15
const MIN_PX_PER_SEC := 5.0
const MAX_PX_PER_SEC := 600.0
const ZOOM_FACTOR := 1.15
const HISTORY_LIMIT := 100
const _WAVE_DRAG_THRESHOLD_PX := 4.0
const SHAPE_BASE_MODULATE := Color(1, 1, 1, 0.16078432)
const SHAPE_SELECTED_MODULATE := Color(1.0, 0.85, 0.2, 0.5)
const SHAPE_CENTER_OFFSET_Y := 0.0
const SHAPE_NOTES_SIZE := Vector2(126.0, 126.0)

var beat_times_ms: Array[int] = []
var waveform: TextureRect = null
var difficulties: Dictionary = { }

var _view_pps := 100.0
var _selected: Array[int] = []
var _drag_beat := -1
var _drag_moved := false
var _drag_history_recorded := false
var _suppress_click := false
var _wave_scrubbing := false
var _wave_moved := false
var _wave_press_pos := Vector2.ZERO
var _wave_start_time := 0.0
var _wave_was_playing := false
var _selected_shape := -1
var _shapes: Array[Dictionary] = []
var _shape_nodes: Array = []
var _custom_points: PackedVector2Array = PackedVector2Array()
var _custom_closed: bool = false
var _custom_pending_times: Array[int] = []
var _custom_drag_idx: int = -1
var _beat_shape_map: Dictionary = { }
var _scrubbing := false
var _markers_root: Node2D = null
var _shapes_root: Node2D = null
var _beat_bg_tiles: Array[TextureRect] = []
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _custom_undo_stack: Array[Dictionary] = []
var _custom_redo_stack: Array[Dictionary] = []
var _custom_drag_recorded := false
var _layout_refresh_queued := false
var _marker_nodes: Dictionary = { }
var _hitsound_fired: Dictionary = { }
var _current_difficulty: String = ""

@onready var mapping_player: AudioStreamPlayer = %MappingPreviewPlayer
@onready var timeline: HSlider = %MappingPreviewCurrentPos
@onready var metadata_group: Control = %METADATA
@onready var hitsound: AudioStreamPlayer = %HitSound
@onready var _line_generator: ColorRect = %LineGenerator
@onready var _beat_y_position: Control = $Border/VBoxContainer/beat_column/BeatYPosition
@onready var _shape_y_position: Control = $Border/VBoxContainer/shape_column/ShapeYPosition
@onready var _beat_bg: TextureRect = %BeatBG
@onready var _btn_start: Button = $HBoxContainer/go_to_start
@onready var _btn_play: Button = $HBoxContainer/start
@onready var _btn_end: Button = $HBoxContainer/go_to_end
@onready var _btn_add_shape: Button = %"Add Shape"
@onready var _shape_option: OptionButton = %ShapeOption
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _add_difficulty_popup: Control = %AddDifficultyPopup
@onready var _custom_panel: ColorRect = %CustomShapeEditor
@onready var _custom_canvas: Control = %CustomCanvas
@onready var _custom_line: Line2D = %CustomLine
@onready var _custom_grid: Control = %CustomGrid
@onready var _custom_info_label: Label = %CustomInfo
@onready var _custom_confirm_btn: Button = %CustomConfirm
@onready var _custom_closed_check: CheckBox = %CustomClosedCheck
@onready var _add_diff_name_edit: LineEdit = %DifficultyName
@onready var _add_diff_spin: SpinBox = %DiffSpin
@onready var _add_diff_label: Label = %DiffLabel
@onready var _edit_diff_name_edit: LineEdit = $EditDifficulty/DifficultyNameEdit


func _ready() -> void:
	_add_difficulty_popup.visible = false
	_markers_root = Node2D.new()
	_markers_root.name = "BeatMarkers"
	add_child(_markers_root)
	_shapes_root = Node2D.new()
	_shapes_root.name = "EditorShapes"
	add_child(_shapes_root)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_scroll()
	_sync_beat_bg.call_deferred()
	timeline.min_value = 0.0
	timeline.step = 0.01
	timeline.value_changed.connect(_on_timeline_changed)
	timeline.drag_started.connect(
		func() -> void:
			_scrubbing = true,
	)
	timeline.drag_ended.connect(
		func(_v: bool) -> void:
			_scrubbing = false,
	)
	_safe_connect(_btn_start, _on_go_to_start)
	_safe_connect(_btn_end, _on_go_to_end)
	_safe_connect(_btn_play, _on_start_pressed)
	_safe_connect(_btn_add_shape, _on_add_shape_pressed)
	for c in [_btn_start, _btn_play, _btn_end, _btn_add_shape, timeline, _shape_option]:
		if c != null and c is Control:
			(c as Control).focus_mode = Control.FOCUS_NONE
	if waveform != null:
		waveform.mouse_filter = Control.MOUSE_FILTER_PASS
		if not waveform.gui_input.is_connected(_on_waveform_gui_input):
			waveform.gui_input.connect(_on_waveform_gui_input)
	_size_waveform_strip()
	_sync_timeline_range()
	_update_scroll()
	_refresh_shape_option()
	_setup_custom_editor()


func _process(_delta: float) -> void:
	if mapping_player.stream == null:
		return
	if mapping_player.playing:
		var pos := mapping_player.get_playback_position()
		timeline.set_value_no_signal(pos)
		_update_scroll()
		_check_beats_passed_line_generator(pos)
		if pos >= mapping_player.stream.get_length() - 0.05:
			mapping_player.stop()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if key_event.ctrl_pressed:
		if _handle_ctrl_shortcut(key_event):
			get_viewport().set_input_as_handled()
		return
	match key_event.physical_keycode:
		KEY_M:
			_run_with_difficulty(add_beat_at_current)
		KEY_N:
			_run_with_difficulty(remove_beat_at_current)
		KEY_SPACE:
			_on_start_pressed()
			get_viewport().set_input_as_handled()
		KEY_DELETE, KEY_BACKSPACE:
			if _selected_shape >= 0:
				_delete_selected_shape()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if get_viewport().gui_get_focus_owner() is LineEdit:
				return # let the focused field / global handler deal with it
			if _custom_panel != null and _custom_panel.visible:
				_hide_custom_editor()
			else:
				_set_selected([])
				_select_shape(-1)
			get_viewport().set_input_as_handled()


func _handle_ctrl_shortcut(event: InputEventKey) -> bool:
	match event.physical_keycode:
		KEY_Z:
			_undo_edit()
			return true
		KEY_R:
			_redo_edit()
			return true
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_zoom_waveform(1)
			return true
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_waveform(-1)
			return true
	# Some layouts only report '+' / '-' in the printable keycode.
	match event.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_zoom_waveform(1)
			return true
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_waveform(-1)
			return true
	return false


func _capture_state() -> Dictionary:
	return {
		"beats": beat_times_ms.duplicate(),
		"shapes": _shapes.duplicate(true),
		"selected": _selected.duplicate(),
		"selected_shape": _selected_shape,
	}


func _record_history() -> void:
	_undo_stack.append(_capture_state())
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _reset_history() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_custom_undo_stack.clear()
	_custom_redo_stack.clear()


func _undo_edit() -> void:
	if _custom_panel != null and _custom_panel.visible:
		_custom_undo_action()
		return
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_capture_state())
	_apply_state(_undo_stack.pop_back())


func _redo_edit() -> void:
	if _custom_panel != null and _custom_panel.visible:
		_custom_redo_action()
		return
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_capture_state())
	_apply_state(_redo_stack.pop_back())


func _apply_state(state: Dictionary) -> void:
	_end_beat_drag()
	beat_times_ms.assign(state.get("beats", []))
	_shapes.clear()
	for shape in state.get("shapes", []):
		_shapes.append((shape as Dictionary).duplicate(true))
	_selected.clear()
	for t in state.get("selected", []):
		_selected.append(int(t))
	_selected_shape = int(state.get("selected_shape", -1))
	_rebuild_markers()
	_rebuild_shape_nodes()
	_refresh_shape_highlight()
	_refresh_shape_option()
	_update_scroll()


func _run_with_difficulty(action: Callable) -> void:
	if _difficulty_option.selected == -1:
		Notification.show_toast(
			"Difficulty Missing",
			"Must add difficulty first.",
			NotificationToast.Kind.WARN,
			2.6,
		)
		return
	action.call()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if waveform == null or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not waveform.get_global_rect().has_point(mb.position):
		return
	if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_waveform(1) # marker Buttons ignore wheel, so it falls through here
		get_viewport().set_input_as_handled()
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_waveform(-1)
		get_viewport().set_input_as_handled()
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if _drag_beat < 0 and not _wave_scrubbing:
			_wave_scrubbing = true
			_wave_moved = false
			_wave_press_pos = mb.position
			_wave_start_time = current_time()
			_wave_was_playing = mapping_player.playing and not mapping_player.stream_paused
	elif not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_set_selected([])


func _on_marker_clicked(beat_ms: int) -> void:
	if _suppress_click:
		_suppress_click = false
		return # release at the end of a drag, not a real click
	if Input.is_key_pressed(KEY_SHIFT):
		var sel := _selected.duplicate()
		if sel.has(beat_ms):
			sel.erase(beat_ms)
		else:
			sel.append(beat_ms)
		_set_selected(sel)
	elif _selected == [beat_ms]:
		_set_selected([]) # clicking the selected beat unselects it
	else:
		_set_selected([beat_ms])


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _wave_scrubbing:
			_handle_wave_scrub(event as InputEventMouseMotion)
		elif _drag_beat >= 0:
			_handle_beat_drag(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)


func _handle_wave_scrub(motion: InputEventMouseMotion) -> void:
	if (not _wave_moved and _wave_press_pos.distance_to(motion.position) < _WAVE_DRAG_THRESHOLD_PX):
		return
	if not _wave_moved:
		_wave_moved = true
		Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
	var delta_px := motion.position.x - _wave_press_pos.x
	var pps := _px_per_sec()
	var new_time := _wave_start_time - delta_px / pps if pps > 0.0 else _wave_start_time
	seek(new_time)


func _handle_beat_drag(motion: InputEventMouseMotion) -> void:
	var target := _mouse_to_beat_ms(motion.position)
	if target == _drag_beat:
		return
	if (
		not _drag_history_recorded and beat_times_ms.has(_drag_beat)
		and not beat_times_ms.has(target)
	):
		_record_history()
		_drag_history_recorded = true
	if not _move_beat(_drag_beat, target):
		return
	_drag_beat = target
	if not _drag_moved:
		_drag_moved = true
		Input.set_default_cursor_shape(Input.CURSOR_HSIZE)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	if _wave_scrubbing:
		_end_wave_scrub()
	_end_beat_drag()


func _end_wave_scrub() -> void:
	var was_scrub := _wave_moved
	var was_playing := _wave_was_playing
	_wave_scrubbing = false
	_wave_moved = false
	_wave_was_playing = false
	_wave_start_time = 0.0
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if not was_scrub:
		return
	get_viewport().set_input_as_handled() # keep selection
	if was_playing and mapping_player.playing and not mapping_player.stream_paused:
		mapping_player.stream_paused = true


func _on_marker_drag_started(beat_ms: int) -> void:
	if not _selected.has(beat_ms):
		return # not selected: ignore the drag, release falls back to select
	_drag_beat = beat_ms
	_drag_moved = false
	_drag_history_recorded = false


func _end_beat_drag() -> void:
	if _drag_moved:
		_suppress_click = true # don't toggle selection on the drag release
		_refresh_shape_option() # selection may have changed count mid-drag
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_drag_beat = -1
	_drag_moved = false
	_drag_history_recorded = false


func _mouse_to_beat_ms(mouse_pos: Vector2) -> int:
	return int(round(_mouse_to_time_sec(mouse_pos) * 1000.0))


func _mouse_to_time_sec(mouse_pos: Vector2) -> float:
	if _markers_root == null:
		return 0.0
	var to_local: Transform2D = _markers_root.get_global_transform_with_canvas().affine_inverse()
	var t := (to_local * mouse_pos).x / _px_per_sec()
	t = maxf(0.0, t)
	if mapping_player.stream != null:
		t = minf(t, mapping_player.stream.get_length())
	return t


func _move_beat(old_ms: int, new_ms: int) -> bool:
	if new_ms == old_ms:
		return true
	if not beat_times_ms.has(old_ms) or beat_times_ms.has(new_ms):
		return false
	_replace_beat_time(old_ms, new_ms)
	_retarget_marker(old_ms, new_ms)
	_retarget_selected_beat(old_ms, new_ms)
	if _retarget_shapes(old_ms, new_ms):
		_rebuild_beat_shape_map()
		_refresh_shapes()
	return true


func _replace_beat_time(old_ms: int, new_ms: int) -> void:
	beat_times_ms.erase(old_ms)
	beat_times_ms.append(new_ms)
	beat_times_ms.sort()


func _retarget_marker(old_ms: int, new_ms: int) -> void:
	var node = _marker_nodes.get(old_ms)
	if node == null:
		return
	_marker_nodes.erase(old_ms)
	_marker_nodes[new_ms] = node
	node.beat_ms = new_ms
	node.position = Vector2(float(new_ms) / 1000.0 * _px_per_sec(), _beat_y())


func _retarget_selected_beat(old_ms: int, new_ms: int) -> void:
	if not _selected.has(old_ms):
		return
	var sel := _selected.duplicate()
	sel.erase(old_ms)
	sel.append(new_ms)
	sel.sort()
	_selected = sel
	_refresh_marker_selection()


func _retarget_shapes(old_ms: int, new_ms: int) -> bool:
	var touched := false
	for shape in _shapes:
		var times: Array = shape["times_ms"]
		if times.has(old_ms):
			times.erase(old_ms)
			times.append(new_ms)
			times.sort()
			touched = true
	return touched


func _set_selected(times: Array) -> void:
	var clean: Array[int] = []
	for t in times:
		var ti := int(t)
		if beat_times_ms.has(ti) and not clean.has(ti):
			clean.append(ti)
	clean.sort()
	_selected = clean
	if not clean.is_empty() and _selected_shape >= 0:
		_selected_shape = -1
		_refresh_shape_highlight()
	_refresh_marker_selection()
	_refresh_shape_option()


func _refresh_marker_selection() -> void:
	for t in _marker_nodes:
		var marker = _marker_nodes[t]
		marker.set_selected(_selected.has(t))


func _select_shape(idx: int) -> void:
	if idx < -1 or idx >= _shapes.size():
		idx = -1
	_selected_shape = idx
	if idx >= 0 and not _selected.is_empty():
		_selected = []
		_refresh_marker_selection()
		_refresh_shape_option()
	_refresh_shape_highlight()


func _refresh_shape_highlight() -> void:
	for i in range(_shape_nodes.size()):
		var node = _shape_nodes[i]
		if is_instance_valid(node) and node is CanvasItem:
			node.self_modulate = (
				SHAPE_SELECTED_MODULATE if i == _selected_shape else SHAPE_BASE_MODULATE
			)


func _on_shape_gui_input(event: InputEvent, node: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			var idx := _shape_nodes.find(node)
			if idx < 0:
				return
			_select_shape(-1 if idx == _selected_shape else idx)
			node.accept_event()


func _delete_selected_shape() -> void:
	if _selected_shape < 0 or _selected_shape >= _shapes.size():
		return
	_record_history()
	var idx := _selected_shape
	_selected_shape = -1
	if idx < _shape_nodes.size():
		var node = _shape_nodes[idx]
		if is_instance_valid(node):
			node.queue_free()
		_shape_nodes.remove_at(idx)
	_shapes.remove_at(idx)
	_rebuild_beat_shape_map()
	_refresh_shape_highlight()


func _delete_all_shapes() -> void:
	for node in _shape_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_shape_nodes.clear()
	_shapes.clear()
	_beat_shape_map.clear()
	_selected_shape = -1


func _rebuild_beat_shape_map() -> void:
	_beat_shape_map.clear()
	for i in range(_shapes.size()):
		for t in _shapes[i]["times_ms"]:
			_beat_shape_map[int(t)] = i


func _strip_beat_from_shapes(ms: int) -> void:
	var changed := false
	for i in range(_shapes.size() - 1, -1, -1):
		var times: Array = _shapes[i]["times_ms"]
		if not times.has(ms):
			continue
		times.erase(ms)
		changed = true
		if times.is_empty():
			if i < _shape_nodes.size():
				var node = _shape_nodes[i]
				if is_instance_valid(node):
					node.queue_free()
				_shape_nodes.remove_at(i)
			_shapes.remove_at(i)
			if _selected_shape == i:
				_selected_shape = -1
			elif _selected_shape > i:
				_selected_shape -= 1
	if changed:
		_rebuild_beat_shape_map()
		_refresh_shapes()
		_refresh_shape_highlight()


func _on_start_pressed() -> void:
	if mapping_player.stream == null:
		return
	if mapping_player.playing:
		mapping_player.stream_paused = not mapping_player.stream_paused
		return
	mapping_player.stream_paused = false
	mapping_player.play(timeline.value)


func _on_go_to_start() -> void:
	seek(0.0)


func _on_go_to_end() -> void:
	if mapping_player.stream == null:
		return
	seek(mapping_player.stream.get_length())


func seek(time_sec: float) -> void:
	var clamped := maxf(0.0, time_sec)
	if mapping_player.stream != null:
		clamped = clampf(clamped, 0.0, mapping_player.stream.get_length())
	timeline.set_value_no_signal(clamped)
	if mapping_player.playing:
		var was_paused := mapping_player.stream_paused
		mapping_player.play(clamped)
		mapping_player.stream_paused = was_paused
	_update_scroll()


func current_time() -> float:
	if mapping_player.playing and not mapping_player.stream_paused:
		return mapping_player.get_playback_position()
	return float(timeline.value)


func _on_timeline_changed(v: float) -> void:
	if _scrubbing or not mapping_player.playing or mapping_player.stream_paused:
		seek(v)
		return
	_update_scroll()


func _on_waveform_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_waveform(1)
				waveform.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_waveform(-1)
				waveform.accept_event()


func _zoom_waveform(steps: int) -> void:
	if steps == 0:
		return
	var target := clampf(_view_pps * pow(ZOOM_FACTOR, steps), MIN_PX_PER_SEC, MAX_PX_PER_SEC)
	if is_equal_approx(target, _view_pps):
		return
	_view_pps = target
	_size_waveform_strip()
	_rebuild_markers()
	_refresh_shapes()
	_update_scroll()


func add_beat_at_current() -> void:
	if mapping_player.stream == null:
		return
	var ms := int(round(current_time() * 1000.0))
	if beat_times_ms.has(ms):
		return
	_record_history()
	beat_times_ms.append(ms)
	beat_times_ms.sort()
	_rebuild_markers()


func remove_beat_at_current() -> void:
	if _selected_shape >= 0:
		_delete_selected_shape()
		return
	if beat_times_ms.is_empty():
		return
	if not _selected.is_empty():
		_record_history()
		_remove_selected_beats()
		return
	var best := _nearest_beat_ms(int(round(current_time() * 1000.0)))
	if best < 0:
		return
	_record_history()
	_remove_beat(best)


func _remove_selected_beats() -> void:
	for t in _selected.duplicate():
		if beat_times_ms.has(t):
			beat_times_ms.erase(t)
			_strip_beat_from_shapes(t)
	_rebuild_markers()
	_set_selected([])


func _remove_beat(beat_ms: int) -> void:
	beat_times_ms.erase(beat_ms)
	_strip_beat_from_shapes(beat_ms)
	_rebuild_markers()
	var sel := _selected.duplicate()
	sel.erase(beat_ms)
	_set_selected(sel)


func _nearest_beat_ms(now_ms: int) -> int:
	var best := -1
	var best_err := int(DELETE_WINDOW_SEC * 1000.0)
	for t in beat_times_ms:
		var err := absi(t - now_ms)
		if err <= best_err:
			best_err = err
			best = t
	return best


func get_beat_times_ms() -> Array[int]:
	return beat_times_ms.duplicate()


func get_selected_beats_ms() -> Array[int]:
	return _selected.duplicate()


func get_shapes() -> Array[Dictionary]:
	return _shapes.duplicate()


func get_solo_beats_ms() -> Array[int]:
	var out: Array[int] = []
	for t in beat_times_ms:
		if not _beat_shape_map.has(t):
			out.append(t)
	return out


func clear_beats() -> void:
	_reset_history()
	beat_times_ms.clear()
	_delete_all_shapes()
	_rebuild_markers()
	_set_selected([])


func _on_add_shape_pressed() -> void:
	if not _can_add_shape():
		return
	var times := _selected.duplicate()
	times.sort()
	var shape_name := _current_shape_name()
	if shape_name == CUSTOM_SHAPE_NAME:
		if _beats_available_for_shape(times):
			_show_custom_editor(times)
		return
	if not _shape_beat_count_matches(shape_name, times):
		return
	if not _beats_available_for_shape(times):
		return
	_record_history()
	_create_shape_entry(
		shape_name,
		times,
		_shape_points(shape_name),
		ShapeLibrary.is_closed_by_default(shape_name),
	)
	_select_shape(_shapes.size() - 1)


func _can_add_shape() -> bool:
	if _selected.is_empty():
		push_warning(
			"mapping: select at least one beat first (click a marker, Shift+click for multi)."
		)
		return false
	if _shapes_root == null:
		push_error("mapping: shapes container missing.")
		return false
	return true


func _current_shape_name() -> String:
	if _shape_option != null and _shape_option.selected >= 0:
		return _shape_option.get_item_text(_shape_option.selected)
	return "Square"


func _shape_beat_count_matches(shape_name: String, times: Array) -> bool:
	var needed := _shape_required_beats(shape_name)
	if times.size() == needed:
		return true
	push_warning(
		"mapping: %s needs %d selected beats, got %d." % [shape_name, needed, times.size()]
	)
	return false


func _beats_available_for_shape(times: Array) -> bool:
	for t in times:
		if not _beat_shape_map.has(t):
			continue
		push_warning(
			(
				"mapping: beat %d is already used in shape %d, remove that shape first."
				% [t, int(_beat_shape_map[t])]
			)
		)
		return false
	return true


func _create_shape_entry(
	shape_name: String,
	times: Array,
	points: PackedVector2Array = PackedVector2Array(),
	closed: bool = false,
) -> void:
	if _shapes_root == null:
		push_error("mapping: shapes container missing.")
		return
	var clean := _clean_shape_times(times)
	var pts := points
	if pts.is_empty():
		pts = _shape_points(shape_name)
		closed = ShapeLibrary.is_closed_by_default(shape_name)
	if shape_name == CUSTOM_SHAPE_NAME:
		pts = _clamp_shape_points(pts)
	var data := { "shape": shape_name, "times_ms": clean, "points": pts, "closed": closed }
	_shapes.append(data)
	_spawn_shape_from_data(data)
	_rebuild_beat_shape_map()


func _spawn_shape_from_data(data: Dictionary) -> void:
	var shape_name := str(data.get("shape", "Square"))
	var times: Array = data.get("times_ms", [])
	var pts = data.get("points", PackedVector2Array())
	if not (pts is PackedVector2Array):
		pts = PackedVector2Array()
	var shape_node := _spawn_shape_node(shape_name, times)
	shape_node.init(pts)
	_shape_nodes.append(shape_node)


func _rebuild_shape_nodes() -> void:
	for node in _shape_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_shape_nodes.clear()
	for data in _shapes:
		_spawn_shape_from_data(data)
	_rebuild_beat_shape_map()


func _clean_shape_times(times: Array) -> Array[int]:
	var clean: Array[int] = []
	for t in times:
		clean.append(int(t))
	clean.sort()
	return clean


func _clamp_shape_points(points: PackedVector2Array) -> PackedVector2Array:
	var clamped := PackedVector2Array()
	for p in points:
		clamped.append(Vector2(clampf(p.x, 0.0, 1.0), clampf(p.y, 0.0, 1.0)))
	return clamped


func _spawn_shape_node(shape_name: String, times: Array) -> Control:
	var shape_node = EDITOR_SHAPE_POINT.instantiate()
	_position_shape_node(shape_node, times)
	shape_node.add_child(_make_shape_tag(shape_name, times.size()))
	shape_node.gui_input.connect(_on_shape_gui_input.bind(shape_node))
	_shapes_root.add_child(shape_node)
	return shape_node


func _make_shape_tag(shape_name: String, beat_count: int) -> Label:
	var tag := Label.new()
	tag.text = "%s (%d)" % [shape_name, beat_count]
	tag.theme = load("res://resources/themes/Theme.tres")
	tag.add_theme_font_size_override("font_size", 32)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tag


func _position_shape_node(shape_node: Control, times: Array) -> void:
	if times.is_empty():
		return
	var pps := _px_per_sec()
	var x0 := float(times[0]) / 1000.0 * pps
	var x1 := float(times[times.size() - 1]) / 1000.0 * pps
	shape_node.position = Vector2(x0, _shape_y() - SHAPE_CENTER_OFFSET_Y)
	var w := maxf(SHAPE_NOTES_SIZE.x, x1 - x0 + SHAPE_NOTES_SIZE.x)
	shape_node.custom_minimum_size = Vector2(w, SHAPE_NOTES_SIZE.x)
	shape_node.size = Vector2(w, SHAPE_NOTES_SIZE.x)


func _refresh_shapes() -> void:
	if _shapes_root == null:
		return
	for i in range(_shapes.size()):
		if i >= _shape_nodes.size():
			continue
		var node = _shape_nodes[i]
		if not is_instance_valid(node):
			continue
		_position_shape_node(node, _shapes[i]["times_ms"])


func _shape_required_beats(shape_name: String) -> int:
	return ShapeLibrary.required_beats(shape_name, _selected.size())


func _custom_total_point_count() -> int:
	return maxi(2, _custom_pending_times.size() + 1)


func _custom_expected_point_count() -> int:
	return _custom_total_point_count()


func _custom_user_needed() -> int:
	var total := _custom_total_point_count()
	if _custom_closed:
		return maxi(1, total - 1)
	return total


func _refresh_shape_option() -> void:
	if _shape_option == null:
		return
	var previous := _selected_shape_option_text()
	_shape_option.clear()
	_fill_shape_options()
	_select_shape_option_by_text(previous)
	var valid := not _selected.is_empty() and _shape_option.item_count > 0
	_shape_option.disabled = not valid and not _selected.is_empty()
	if _btn_add_shape != null:
		_btn_add_shape.disabled = not valid


func _selected_shape_option_text() -> String:
	if _shape_option.selected < 0 or _shape_option.item_count == 0:
		return ""
	return _shape_option.get_item_text(_shape_option.selected)


func _fill_shape_options() -> void:
	if _selected.is_empty():
		for shape_name in SHAPE_NAMES:
			_shape_option.add_item(shape_name)
		return
	for shape_name in SHAPE_NAMES:
		if _shape_required_beats(shape_name) == _selected.size():
			_shape_option.add_item(shape_name)
	_shape_option.add_item(CUSTOM_SHAPE_NAME)


func _select_shape_option_by_text(text: String) -> void:
	if _shape_option.item_count == 0:
		return
	var pick := 0
	for i in range(_shape_option.item_count):
		if _shape_option.get_item_text(i) == text:
			pick = i
			break
	_shape_option.select(pick)


func _shape_points(shape_name: String) -> PackedVector2Array:
	return ShapeLibrary.points(shape_name)


func _setup_custom_editor() -> void:
	if _custom_panel != null:
		_custom_panel.visible = false
	if _custom_grid != null and not _custom_grid.draw.is_connected(_on_custom_grid_draw):
		_custom_grid.draw.connect(_on_custom_grid_draw)
	if (
		_custom_canvas != null
		and not _custom_canvas.gui_input.is_connected(_on_custom_canvas_input)
	):
		_custom_canvas.gui_input.connect(_on_custom_canvas_input)


func _ensure_custom_editor() -> void:
	_setup_custom_editor()


func _show_custom_editor(times: Array) -> void:
	_ensure_custom_editor()
	_custom_pending_times = []
	for t in times:
		_custom_pending_times.append(int(t))
	_custom_points = PackedVector2Array()
	_custom_closed = false
	if _custom_closed_check != null:
		_custom_closed_check.set_pressed_no_signal(false)
	_custom_drag_idx = -1
	_custom_drag_recorded = false
	_custom_undo_stack.clear()
	_custom_redo_stack.clear()
	_update_custom_editor()
	_custom_panel.visible = true


func _hide_custom_editor() -> void:
	if _custom_panel != null:
		_custom_panel.visible = false
	_custom_drag_idx = -1


func _update_custom_editor() -> void:
	if _custom_info_label == null or _custom_confirm_btn == null:
		return
	var total := _custom_total_point_count()
	_update_custom_closed_availability(total)
	_update_custom_info_text(total)
	_custom_confirm_btn.disabled = _custom_points.size() != total
	_redraw_custom_views()


func _update_custom_closed_availability(total: int) -> void:
	if _custom_closed_check == null:
		return
	_custom_closed_check.disabled = total < 4
	if total < 4 and _custom_closed:
		_custom_closed = false
		_custom_closed_check.set_pressed_no_signal(false)


func _update_custom_info_text(total: int) -> void:
	if _custom_closed:
		_custom_info_label.text = (
			"Beats: %d  • Need %d (+1 auto) = %d pts (0..1)  • Placed: %d"
			% [_custom_pending_times.size(), _custom_user_needed(), total, _custom_points.size()]
		)
		return
	_custom_info_label.text = (
		"Beats: %d  • Need %d points (0..1)  • Placed: %d"
		% [_custom_pending_times.size(), _custom_expected_point_count(), _custom_points.size()]
	)


func _redraw_custom_views() -> void:
	if _custom_line != null:
		_update_custom_line()
	if _custom_canvas != null:
		_custom_canvas.queue_redraw()
	if _custom_grid != null:
		_custom_grid.queue_redraw()


func _update_custom_line() -> void:
	if _custom_line == null or _custom_canvas == null:
		return
	var csize := _custom_canvas.size
	if csize.x < 1 or csize.y < 1:
		csize = Vector2(240, 240)
	var pts := PackedVector2Array()
	for p in _custom_points:
		pts.append(Vector2(p.x * csize.x, p.y * csize.y))
	_custom_line.points = pts
	_custom_line.closed = _custom_closed and pts.size() >= 3


func _sync_closed_duplicate() -> void:
	if not _custom_closed:
		return
	if _custom_points.size() < 2:
		return
	var total := _custom_total_point_count()
	if _custom_points.size() == total - 1:
		_custom_points.append(_custom_points[0])
	elif _custom_points.size() == total:
		_custom_points[_custom_points.size() - 1] = _custom_points[0]


func _on_custom_grid_draw() -> void:
	if _custom_grid == null or _custom_canvas == null:
		return
	var s := _custom_canvas.size
	if s.x < 1:
		return
	var pts := _custom_points
	for i in range(pts.size()):
		var pos := Vector2(pts[i].x * s.x, pts[i].y * s.y)
		var col := Color(0.2, 0.8, 1.0, 1.0) if i == pts.size() - 1 else Color(1.0, 0.85, 0.2, 1.0)
		_custom_grid.draw_circle(pos, 5.0, col)
		_custom_grid.draw_string(
			ThemeDB.fallback_font,
			pos + Vector2(6, 6),
			str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			Color.WHITE,
		)


func _on_custom_canvas_input(event: InputEvent) -> void:
	if _custom_canvas == null:
		return
	if event is InputEventMouseButton:
		_handle_custom_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_custom_mouse_motion(event as InputEventMouseMotion)


func _handle_custom_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_handle_custom_press(mb.position)
	elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_custom_drag_idx = -1
		_custom_drag_recorded = false
		_update_custom_editor()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_on_custom_undo()
		_custom_canvas.accept_event()


func _handle_custom_press(_pos: Vector2) -> void:
	var total := _custom_total_point_count()
	var canvas_size := _custom_canvas.size
	var idx := _hit_custom_point(_pos, canvas_size)
	if idx >= 0:
		if (_custom_closed and idx == _custom_points.size() - 1 and _custom_points.size() == total):
			idx = 0
		_custom_drag_idx = idx
		_custom_drag_recorded = false
		_custom_canvas.accept_event()
		return
	if _custom_points.size() >= total:
		return
	if _custom_closed and _custom_points.size() == total - 1:
		return
	_custom_record()
	_add_custom_point(_normalized_point(_pos, canvas_size))
	_update_custom_editor()
	_custom_canvas.accept_event()


func _add_custom_point(normalized: Vector2) -> void:
	var total := _custom_total_point_count()
	_custom_points.append(normalized)
	if _custom_closed and _custom_points.size() == total - 1:
		_custom_points.append(_custom_points[0])


func _handle_custom_mouse_motion(motion: InputEventMouseMotion) -> void:
	if _custom_drag_idx < 0 or _custom_drag_idx >= _custom_points.size():
		return
	if not _custom_drag_recorded:
		_custom_record()
		_custom_drag_recorded = true
	var total := _custom_total_point_count()
	var canvas_size := _custom_canvas.size
	_custom_points[_custom_drag_idx] = _normalized_point(motion.position, canvas_size)
	_sync_dragged_closed_point(total)
	_update_custom_editor()


func _sync_dragged_closed_point(total: int) -> void:
	if not _custom_closed or _custom_points.size() != total:
		return
	if _custom_drag_idx == 0:
		_custom_points[_custom_points.size() - 1] = _custom_points[0]
	elif _custom_drag_idx == _custom_points.size() - 1:
		_custom_points[0] = _custom_points[_custom_drag_idx]


func _normalized_point(local: Vector2, canvas_size: Vector2) -> Vector2:
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		return Vector2.ZERO
	return Vector2(
		clampf(local.x / canvas_size.x, 0.0, 1.0),
		clampf(local.y / canvas_size.y, 0.0, 1.0),
	)


func _hit_custom_point(pos: Vector2, canvas_size: Vector2) -> int:
	for i in range(_custom_points.size()):
		var pp := Vector2(_custom_points[i].x * canvas_size.x, _custom_points[i].y * canvas_size.y)
		if pos.distance_to(pp) < 10.0:
			return i
	return -1


func _on_custom_closed_toggled(v: bool) -> void:
	var total := _custom_total_point_count()
	if total < 4 and v:
		if _custom_closed_check != null:
			_custom_closed_check.set_pressed_no_signal(false)
		return
	_custom_record()
	_custom_closed = v
	if _custom_closed:
		if _custom_points.size() == total - 1:
			_custom_points.append(_custom_points[0])
		elif _custom_points.size() == total:
			_custom_points[total - 1] = _custom_points[0]
	else:
		if (
			_custom_points.size() == total and _custom_points.size() >= 2
			and _custom_points[0].is_equal_approx(_custom_points[_custom_points.size() - 1])
		):
			_custom_points.remove_at(_custom_points.size() - 1)
	_update_custom_editor()


func _custom_snapshot() -> Dictionary:
	return { "points": _custom_points.duplicate(), "closed": _custom_closed }


func _custom_record() -> void:
	_custom_undo_stack.append(_custom_snapshot())
	if _custom_undo_stack.size() > HISTORY_LIMIT:
		_custom_undo_stack.pop_front()
	_custom_redo_stack.clear()


func _custom_restore(snapshot: Dictionary) -> void:
	var points = snapshot.get("points", PackedVector2Array())
	_custom_points = (points as PackedVector2Array).duplicate()
	_custom_closed = bool(snapshot.get("closed", false))
	if _custom_closed_check != null:
		_custom_closed_check.set_pressed_no_signal(_custom_closed)
	_custom_drag_idx = -1
	_custom_drag_recorded = false
	_update_custom_editor()


func _custom_undo_action() -> void:
	if _custom_undo_stack.is_empty():
		return
	_custom_redo_stack.append(_custom_snapshot())
	_custom_restore(_custom_undo_stack.pop_back())


func _custom_redo_action() -> void:
	if _custom_redo_stack.is_empty():
		return
	_custom_undo_stack.append(_custom_snapshot())
	_custom_restore(_custom_redo_stack.pop_back())


func _on_custom_undo() -> void:
	_custom_undo_action()


func _on_custom_clear() -> void:
	if _custom_points.is_empty():
		return
	_custom_record()
	_custom_points = PackedVector2Array()
	_update_custom_editor()


func _on_custom_cancel() -> void:
	_hide_custom_editor()


func _on_custom_confirm() -> void:
	var need := _custom_expected_point_count()
	if _custom_points.size() != need:
		push_warning("custom: need %d points, got %d." % [need, _custom_points.size()])
		return
	var pts := _custom_points.duplicate()
	if _custom_closed and pts.size() >= 2:
		pts[pts.size() - 1] = pts[0]
	_hide_custom_editor()
	var times := _custom_pending_times.duplicate()
	_custom_pending_times.clear()
	_record_history()
	_create_shape_entry(CUSTOM_SHAPE_NAME, times, pts, _custom_closed)
	_select_shape(_shapes.size() - 1)


func get_difficulties_data() -> Dictionary:
	_save_current_difficulty_state()
	return difficulties.duplicate(true)


func import_difficulty(diff_name: String, chart: ChartData) -> void:
	if chart == null or chart.metadata.is_empty():
		return
	_save_current_difficulty_state()
	var clean_name := _clean_difficulty_name(diff_name)
	_register_difficulty(clean_name, chart)
	_ensure_chart_song(chart)
	_import_beats_and_shapes(chart) # populates beat_times_ms / _shapes from the chart
	_set_current_difficulty(clean_name)
	_select_difficulty_in_dropdown(clean_name)


func _clean_difficulty_name(raw: String) -> String:
	var clean_name := raw.strip_edges()
	return "untitled" if clean_name.is_empty() else clean_name


func _register_difficulty(diff_name: String, chart: ChartData) -> void:
	var is_new := not difficulties.has(diff_name)
	var overall := int(chart.metadata.get("overall_difficulty", 0))
	difficulties[diff_name] = { "beats": [], "shapes": [], "overall_difficulty": overall }
	if is_new:
		_difficulty_option.add_item(diff_name)


func _ensure_chart_song(chart: ChartData) -> void:
	if mapping_player.stream != null:
		return
	var song := chart.song_path()
	if not song.is_empty():
		_load_song(song)


func _set_current_difficulty(diff_name: String) -> void:
	_current_difficulty = diff_name
	_save_current_difficulty_state()
	_edit_diff_name_edit.text = diff_name


func _select_difficulty_in_dropdown(diff_name: String) -> void:
	for i in range(_difficulty_option.item_count):
		if _difficulty_option.get_item_text(i) == diff_name:
			_difficulty_option.select(i)
			return


func _import_beats_and_shapes(chart: ChartData) -> void:
	clear_beats()
	if chart.notes.is_empty():
		return
	var collected := _collect_note_times(chart.notes)
	var times_by_id: Dictionary = collected["times_by_id"]
	for sid in _shape_ids_in_time_order(times_by_id, collected["order"]):
		var times := _sorted_times(times_by_id[sid])
		if ChartParser.is_solo_id(sid) or sid.strip_edges().is_empty():
			continue # unsetup/solo notes stay as plain beats, not shapes
		_import_chart_shape(sid, times, chart.shape_points_by_id(sid))
	_finish_import()


func _collect_note_times(notes: Array) -> Dictionary:
	var times_by_id: Dictionary = { }
	var order: Array = []
	for note in notes:
		var n := note as Dictionary
		var sid := str(n.get("id", ""))
		var ms := int(round(float(n.get("start_time", n.get("time", 0.0)))))
		if not times_by_id.has(sid):
			times_by_id[sid] = []
			order.append(sid)
		(times_by_id[sid] as Array).append(ms)
		if not beat_times_ms.has(ms):
			beat_times_ms.append(ms)
	beat_times_ms.sort()
	return { "times_by_id": times_by_id, "order": order }


func _shape_ids_in_time_order(times_by_id: Dictionary, order: Array) -> Array:
	var sorted_ids := order.duplicate()
	sorted_ids.sort_custom(
		func(a: String, b: String) -> bool:
			return int((times_by_id[a] as Array)[0]) < int((times_by_id[b] as Array)[0]),
	)
	return sorted_ids


func _sorted_times(times: Array) -> Array:
	var sorted := times.duplicate()
	sorted.sort()
	return sorted


func _import_chart_shape(_sid: String, times: Array, pts: PackedVector2Array) -> void:
	var editor_shape := ShapeLibrary.infer_name(times.size(), pts)
	if (editor_shape.is_empty() or times.size() != _shape_required_beats(editor_shape)):
		_import_custom_shape_if_possible(times, pts)
		return
	_create_shape_entry(
		editor_shape,
		times,
		_shape_points(editor_shape),
		ShapeLibrary.is_closed_by_default(editor_shape),
	)


func _import_custom_shape_if_possible(times: Array, pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	_create_shape_entry(CUSTOM_SHAPE_NAME, times, pts, _points_are_closed(pts))


func _points_are_closed(pts: PackedVector2Array) -> bool:
	return pts.size() >= 3 and pts[0].is_equal_approx(pts[pts.size() - 1])


func _finish_import() -> void:
	_rebuild_markers()
	_refresh_shapes()
	_set_selected([])
	_select_shape(-1)
	seek(0.0)
	_request_layout_refresh()


func _load_song(path: String) -> void:
	var p := path.strip_edges()
	if p.is_empty():
		return
	var stream: AudioStream = Global.load_safely(p)
	mapping_player.stop()
	mapping_player.stream_paused = false
	mapping_player.stream = stream
	_size_waveform_strip()
	_sync_timeline_range()
	seek(0.0)


func _px_per_sec() -> float:
	return _view_pps


func _to_mapping(point_global: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * point_global


func _line_x() -> float:
	if _line_generator == null:
		return 0.0
	var center_global := _line_generator.global_position + _line_generator.size * 0.5
	return _to_mapping(center_global).x


func _beat_y() -> float:
	if _beat_y_position == null:
		return 0.0
	var center_global := _beat_y_position.global_position + _beat_y_position.size * 0.5
	return _to_mapping(center_global).y


func _shape_y() -> float:
	if _shape_y_position == null:
		return 0.0
	var center_global := _shape_y_position.global_position + _shape_y_position.size * 0.5
	return _to_mapping(center_global).y


func _on_visibility_changed() -> void:
	if not visible:
		return
	# Containers only sort visible children, so wait for the layout pass before
	# reading BeatYPosition / ShapeYPosition.
	await get_tree().process_frame
	_refresh_marker_positions()
	_refresh_shape_positions()
	_update_scroll()


func _on_viewport_size_changed() -> void:
	if not visible:
		return
	# Resizing re-sorts the Border containers, so let the layout settle before
	# reading the moved BeatYPosition / ShapeYPosition anchors.
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_marker_positions()
	_refresh_shape_positions()
	_update_scroll()


func _refresh_marker_positions() -> void:
	var y := _beat_y()
	for t in _marker_nodes:
		var marker = _marker_nodes[t]
		if is_instance_valid(marker):
			marker.position.y = y


func _refresh_shape_positions() -> void:
	var count: int = mini(_shapes.size(), _shape_nodes.size())
	for i in range(count):
		var node = _shape_nodes[i]
		if is_instance_valid(node):
			_position_shape_node(node, _shapes[i]["times_ms"])


func _request_layout_refresh() -> void:
	# Imported shapes can spawn before the Border containers have sorted
	# ShapeYPosition, which leaves them at the beat column's Y until a resize.
	if _layout_refresh_queued:
		return
	_layout_refresh_queued = true
	await get_tree().process_frame
	await get_tree().process_frame
	_layout_refresh_queued = false
	if not is_inside_tree():
		return
	_refresh_marker_positions()
	_refresh_shape_positions()
	_update_scroll()


func _sync_timeline_range() -> void:
	if mapping_player.stream == null:
		timeline.max_value = 0.0
		return
	timeline.max_value = maxf(0.0, mapping_player.stream.get_length())
	timeline.set_value_no_signal(0.0)


func _update_scroll() -> void:
	if _markers_root == null:
		return
	var scroll_x := _line_x() - current_time() * _px_per_sec()
	_markers_root.position = Vector2(scroll_x, 0.0)
	if _shapes_root != null:
		_shapes_root.position = Vector2(scroll_x, 0.0)
	_sync_beat_bg()


func _sync_beat_bg() -> void:
	if _beat_bg == null or _markers_root == null:
		return
	var period := _beat_bg.size.x
	if period <= 0.0:
		return
	var view_left := global_position.x
	var needed := int(ceil(size.x / period)) + 2
	_ensure_beat_bg_tiles(needed)
	var start_x := view_left + fposmod(_markers_root.global_position.x - view_left, period) - period
	for i in range(_beat_bg_tiles.size()):
		var tile := _beat_bg_tiles[i]
		if not is_instance_valid(tile):
			continue
		tile.global_position = Vector2(start_x + float(i) * period, _beat_bg.global_position.y)


func _ensure_beat_bg_tiles(count: int) -> void:
	if _beat_bg == null:
		return
	var parent := _beat_bg.get_parent()
	if parent == null:
		return
	while _beat_bg_tiles.size() < count:
		if _beat_bg_tiles.is_empty():
			_beat_bg_tiles.append(_beat_bg)
			continue
		var tile := _beat_bg.duplicate() as TextureRect
		tile.visible = true
		tile.name = "BeatBGLoop%d" % _beat_bg_tiles.size()
		tile.unique_name_in_owner = false
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(tile)
		_beat_bg_tiles.append(tile)


func _check_beats_passed_line_generator(_pos: float) -> void:
	if _line_generator == null or _markers_root == null:
		return
	var line_x := _line_x()
	var col_x := _markers_root.position.x
	for t in beat_times_ms:
		var marker = _marker_nodes.get(t)
		if marker == null or not is_instance_valid(marker):
			continue
		var marker_x_in_mapping: float = col_x + marker.position.x
		var passed := marker_x_in_mapping <= line_x + 0.1 # tiny epsilon for float/1px mismatch
		var was_fired: bool = _hitsound_fired.has(t)
		if passed and not was_fired:
			if hitsound != null:
				hitsound.play()
			_hitsound_fired[t] = true
		elif not passed and was_fired:
			_hitsound_fired.erase(t)


func _size_waveform_strip() -> void:
	if waveform == null:
		return
	var length := 0.0
	if mapping_player.stream != null:
		length = maxf(0.0, mapping_player.stream.get_length())
	var w := maxf(1.0, length * _view_pps)
	waveform.position.x = 0.0
	waveform.size.x = w
	waveform.custom_minimum_size.x = w


func _rebuild_markers() -> void:
	if _markers_root == null:
		return
	_end_beat_drag() # nodes are freed below; a drag can't survive a rebuild
	for child in _markers_root.get_children():
		child.queue_free()
	_marker_nodes.clear()
	for k in _hitsound_fired.keys():
		if not beat_times_ms.has(k):
			_hitsound_fired.erase(k)
	for t in beat_times_ms:
		var marker = EDITOR_BEAT_POINT.instantiate()
		marker.position = Vector2(float(t) / 1000.0 * _px_per_sec(), _beat_y())
		marker.beat_ms = t
		_markers_root.add_child(marker)
		marker.clicked.connect(_on_marker_clicked)
		marker.drag_started.connect(_on_marker_drag_started)
		_marker_nodes[t] = marker
	_refresh_marker_selection()


func _safe_connect(btn: Button, method: Callable) -> void:
	if btn == null:
		return
	if not btn.pressed.is_connected(method):
		btn.pressed.connect(method)


func _on_load_song_file_selected(path: String) -> void:
	_load_song(path)


func _on_add_difficuly_pressed() -> void:
	_add_diff_name_edit.text = ""
	_add_diff_spin.value = 0
	_add_difficulty_popup.visible = true
	_add_diff_name_edit.grab_focus()
	pass # Replace with function body.


func _save_current_difficulty_state() -> void:
	if _current_difficulty.is_empty() or not difficulties.has(_current_difficulty):
		return
	var entry: Dictionary = difficulties[_current_difficulty]
	entry["beats"] = beat_times_ms.duplicate()
	entry["shapes"] = _shapes.duplicate(true)


func _on_add_difficulty_confirmation_pressed() -> void:
	var raw_name := _add_diff_name_edit.text.strip_edges()
	var error := _difficulty_name_error(raw_name)
	if not error.is_empty():
		_warn_invalid_difficulty(error)
		return
	_add_difficulty(raw_name, int(_add_diff_spin.value))
	_add_diff_name_edit.text = ""
	_add_difficulty_popup.visible = false


func _add_difficulty(diff_name: String, overall_difficulty: int) -> void:
	_save_current_difficulty_state()
	difficulties[diff_name] = {
		"beats": [],
		"shapes": [],
		"overall_difficulty": overall_difficulty,
	}
	_difficulty_option.add_item(diff_name)
	_difficulty_option.select(_difficulty_option.item_count - 1)
	_current_difficulty = diff_name
	clear_beats() # fresh empty buffer for the new difficulty
	_edit_diff_name_edit.text = diff_name


func _difficulty_name_error(raw_name: String, excluded: String = "") -> String:
	var clean_name := raw_name.strip_edges()
	if clean_name.is_empty():
		return "Difficulty name can't be empty."
	for existing in difficulties.keys():
		if str(existing) == excluded:
			continue
		if str(existing).to_lower() == clean_name.to_lower():
			return 'A difficulty named "%s" already exists.' % existing
	return ""


func _warn_invalid_difficulty(message: String) -> void:
	Notification.show_toast("Invalid Difficulty", message, NotificationToast.Kind.WARN, 2.6)


func _on_save_changes_on_current_diff_pressed() -> void:
	if _current_difficulty.is_empty():
		Notification.show_toast(
			"Difficulty Missing",
			"No difficulty selected.",
			NotificationToast.Kind.WARN,
			2.6,
		)
		return
	_save_current_difficulty_state()
	Notification.show_toast(
		"Difficulty Saved",
		'Saved "%s".' % _current_difficulty,
		NotificationToast.Kind.SUCCESS,
	)


func _on_edit_difficulty_name_button_pressed() -> void:
	if _current_difficulty.is_empty():
		Notification.show_toast(
			"Difficulty Missing",
			"Select a difficulty first.",
			NotificationToast.Kind.WARN,
			2.6,
		)
		return
	var new_name := _edit_diff_name_edit.text.strip_edges()
	var error := _difficulty_name_error(new_name, _current_difficulty)
	if not error.is_empty():
		_warn_invalid_difficulty(error)
		return
	if new_name == _current_difficulty:
		return
	_rename_current_difficulty(new_name)
	Notification.show_toast(
		"Difficulty Renamed",
		'Renamed to "%s".' % new_name,
		NotificationToast.Kind.SUCCESS,
	)


func _rename_current_difficulty(new_name: String) -> void:
	difficulties[new_name] = difficulties[_current_difficulty]
	difficulties.erase(_current_difficulty)
	_replace_difficulty_option_text(_current_difficulty, new_name)
	_current_difficulty = new_name
	_edit_diff_name_edit.text = new_name


func _replace_difficulty_option_text(old_name: String, new_name: String) -> void:
	for i in range(_difficulty_option.item_count):
		if _difficulty_option.get_item_text(i) == old_name:
			_difficulty_option.set_item_text(i, new_name)
			return


func _on_cancel_difficulty_creation_pressed() -> void:
	_add_difficulty_popup.visible = false


func _load_difficulty_state(name_diff: String) -> void:
	if not difficulties.has(name_diff):
		return
	var entry: Dictionary = difficulties[name_diff]
	clear_beats()
	_load_entry_beats(entry)
	_load_entry_shapes(entry)
	_current_difficulty = name_diff
	_edit_diff_name_edit.text = name_diff
	_rebuild_markers()
	_refresh_shapes()
	_set_selected([])
	_select_shape(-1)
	seek(0.0)


func _load_entry_beats(entry: Dictionary) -> void:
	var loaded_beats: Array[int] = []
	for b in entry.get("beats", []):
		loaded_beats.append(int(b))
	loaded_beats.sort()
	beat_times_ms = loaded_beats


func _load_entry_shapes(entry: Dictionary) -> void:
	for shape in entry.get("shapes", []):
		var sd := shape as Dictionary
		_create_shape_entry(
			str(sd.get("shape", "Square")),
			sd.get("times_ms", []),
			sd.get("points", PackedVector2Array()),
			bool(sd.get("closed", false)),
		)


func _on_difficulty_option_item_selected(index: int) -> void:
	if index < 0 or index >= _difficulty_option.item_count:
		return
	var new_name := _difficulty_option.get_item_text(index)
	if new_name == _current_difficulty:
		return
	_save_current_difficulty_state()
	_load_difficulty_state(new_name)
	pass # Replace with function body.


func _on_diff_spin_value_changed(value: float) -> void:
	var i := int(value)
	if i <= 3:
		_add_diff_label.text = "EASY"
	elif i <= 6:
		_add_diff_label.text = "MEDIUM"
	else:
		_add_diff_label.text = "HARD"
	pass # Replace with function body.


func _on_add_beat_button_pressed() -> void:
	_run_with_difficulty(add_beat_at_current)


func _on_remove_beat_button_pressed() -> void:
	_run_with_difficulty(remove_beat_at_current)


func _on_undo_pressed() -> void:
	_undo_edit()


func _on_redo_pressed() -> void:
	_redo_edit()
