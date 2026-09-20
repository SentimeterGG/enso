extends Control

const EDITOR_BEAT_POINT := preload("res://scenes/editor_beat_point.tscn")
const EDITOR_SHAPE_POINT := preload("res://scenes/editor_shape_point.tscn")

@onready var mapping_player: AudioStreamPlayer = %MappingPreviewPlayer
@onready var timeline: HSlider = %MappingPreviewCurrentPos
@onready var beat_column: Node2D = $beat_collumn
@onready var waveform: TextureRect = $beat_collumn/AudioStreamPreview
@onready var metadata_group: Control = %METADATA
@onready var hitsound: AudioStreamPlayer = %HitSound
# Unique access to level_creator.tscn's vertical receptor line (LineGenerator at x=144).
# Verified in scenes/level_creator.tscn: [node name="LineGenerator" ... unique_name_in_owner = true]
@onready var _line_generator: Line2D = %LineGenerator

@onready var _btn_start: Button = $HBoxContainer/go_to_start
@onready var _btn_play: Button = $HBoxContainer/start
@onready var _btn_end: Button = $HBoxContainer/go_to_end
@onready var _btn_add_shape: Button = $"Add Shape"
@onready var _shape_option: OptionButton = $ShapeOption
# Declarative editor from level_creator.tscn (root overlay, avoids MAPPING clip)
@onready var _custom_panel: Panel = %CustomShapeEditor
@onready var _custom_canvas: Control = %CustomCanvas
@onready var _custom_line: Line2D = %CustomLine
@onready var _custom_grid: Control = %CustomGrid
@onready var _custom_info_label: Label = %CustomInfo
@onready var _custom_confirm_btn: Button = %CustomConfirm
@onready var _custom_closed_check: CheckBox = %CustomClosedCheck

## All shape names in ShapeOption (scenes/level_creator.tscn order).
const SHAPE_NAMES := ["L", "L90", "L180", "L270", "LFlip", "U", "UInv", "Square", "Triangle", "HLine", "VLine", "Diag", "DiagInv", "ZigZag"]
const CUSTOM_SHAPE_NAME := "Custom"
## Receptor x in MAPPING-local coords (matches the Line2D at x=144).
const RECEPTOR_X := 144.0
## Base position of beat_collumn when song time == 0 (from the .tscn).
const COLUMN_BASE := Vector2(145, 86)
## N deletes the marker nearest to "now" within this window.
const DELETE_WINDOW_SEC := 0.15
## Y of beat markers in beat_collumn-local coords (waveform spans ~-4..60).
const MARKER_Y := 28.0
## Y of created shapes in beat_collumn-local coords (below the waveform).
const SHAPE_Y := 70.0
## Waveform zoom limits (px per second) for scroll-wheel zoom.
const MIN_PX_PER_SEC := 5.0
const MAX_PX_PER_SEC := 600.0
## Multiplicative zoom per wheel tick: up = zoom in, down = zoom out.
const ZOOM_FACTOR := 1.15

var beat_times_ms: Array[int] = []
## Display zoom (px/sec). The tiling strip is sized to song_length * this,
## so markers (x = time * pps) always line up with it.
var _view_pps := 100.0
## Currently selected beat times (subset of beat_times_ms).
var _selected: Array[int] = []
## Beat being dragged (original ms, -1 = none). Only x changes while dragging.
var _drag_beat := -1
## True once the current press actually moved (distinguishes drag from click).
var _drag_moved := false
## Consumed by _on_marker_clicked to skip select-toggle after a drag release.
var _suppress_click := false
## Waveform scrub: press-drag on empty waveform seeks like the timeline slider.
var _wave_scrubbing := false
var _wave_moved := false
var _wave_press_pos := Vector2.ZERO
var _wave_start_time := 0.0
var _wave_was_playing := false
const _WAVE_DRAG_THRESHOLD_PX := 4.0
## Selected shape index into _shapes (-1 = none). Mutually exclusive with beats.
var _selected_shape := -1
## Base tint of shape nodes (matches editor_shape_point.tscn).
const SHAPE_BASE_MODULATE := Color(1, 1, 1, 0.16078432)
const SHAPE_SELECTED_MODULATE := Color(1.0, 0.85, 0.2, 0.5)
## Created shapes: {shape: String, times_ms: Array[int], points: PackedVector2Array, closed: bool}.
## Presets store points via _shape_points(); Custom stores user 0..1 points.
var _shapes: Array[Dictionary] = []
## Shape scene nodes parallel to _shapes (for zoom repositioning).
var _shape_nodes: Array = []
# Custom editor state (nodes are @onready % from tscn)
var _custom_points: PackedVector2Array = PackedVector2Array()
var _custom_closed: bool = false
var _custom_pending_times: Array[int] = []
var _custom_drag_idx: int = -1
## beat time ms -> index into _shapes. A beat can only belong to one shape.
var _beat_shape_map: Dictionary = {}
var _scrubbing := false
var _markers_root: Node2D = null
var _shapes_root: Node2D = null
## beat time ms -> editor_beat_point instance.
var _marker_nodes: Dictionary = {}
## Tracks which beats already triggered hitsound/vibrate when passing LineGenerator.
## Key = beat_ms (int), value = true. Cleared when the beat moves back ahead of the line (seek/rewind).
var _hitsound_fired: Dictionary = {}


func _ready() -> void:
	_markers_root = Node2D.new()
	_markers_root.name = "BeatMarkers"
	beat_column.add_child(_markers_root)
	_shapes_root = Node2D.new()
	_shapes_root.name = "EditorShapes"
	beat_column.add_child(_shapes_root)
	beat_column.position = COLUMN_BASE
	timeline.min_value = 0.0
	timeline.step = 0.01
	timeline.value_changed.connect(_on_timeline_changed)
	timeline.drag_started.connect(func() -> void: _scrubbing = true)
	timeline.drag_ended.connect(func(_v: bool) -> void: _scrubbing = false)
	# `start` is already connected in the .tscn; the rest are wired here.
	_safe_connect(_btn_start, _on_go_to_start)
	_safe_connect(_btn_end, _on_go_to_end)
	# _btn_play (`start`) may already be connected via the scene; guard doubles.
	_safe_connect(_btn_play, _on_start_pressed)
	_safe_connect(_btn_add_shape, _on_add_shape_pressed)
	# Space is our global play/pause toggle (see _unhandled_key_input). Keep it
	# away from the widgets: a focused Button would eat Space as its own press
	# (e.g. Space re-triggering "Add Shape"), so none of them take focus.
	for c in [_btn_start, _btn_play, _btn_end, _btn_add_shape, timeline, _shape_option]:
		if c != null and c is Control:
			(c as Control).focus_mode = Control.FOCUS_NONE
	# Scroll-wheel zoom on the waveform (gui_input only fires while hovering it).
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
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M:
				add_beat_at_current()
				get_viewport().set_input_as_handled()
			KEY_N:
				remove_beat_at_current()
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				_on_start_pressed()
				get_viewport().set_input_as_handled()
			KEY_DELETE, KEY_BACKSPACE:
				if _selected_shape >= 0:
					_delete_selected_shape()
					get_viewport().set_input_as_handled()


## Selection works through each marker's Button (see editor_beat_point.gd):
## click = select (click again = unselect), Shift+click = toggle multi-select,
## click on empty waveform = clear. Hold + move drags a beat in time (x only,
## clamped to the song, blocked onto occupied times). Press-drag on empty
## waveform scrubs the playhead like the timeline slider. Marker Buttons
## consume their own presses, so only empty-area presses reach _unhandled_input.
func _unhandled_input(event: InputEvent) -> void:
	if waveform == null or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not waveform.get_global_rect().has_point(mb.position):
		return
	if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_waveform(1)  # marker Buttons ignore wheel, so it falls through here
		get_viewport().set_input_as_handled()
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_waveform(-1)
		get_viewport().set_input_as_handled()
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		# Arm beat_column grab: hold and pull left/right like grabbing paper.
		# Actual seek happens on motion past threshold in _input (relative).
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
		return  # release at the end of a drag, not a real click
	if Input.is_key_pressed(KEY_SHIFT):
		var sel := _selected.duplicate()
		if sel.has(beat_ms):
			sel.erase(beat_ms)
		else:
			sel.append(beat_ms)
		_set_selected(sel)
	elif _selected == [beat_ms]:
		_set_selected([])  # clicking the selected beat unselects it
	else:
		_set_selected([beat_ms])


## Beat dragging (x only) + waveform grab share _input: only _input sees
## motion everywhere, so both trackings live here. _input runs before
## _unhandled_input, so a grab release can swallow the click-clear below.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _wave_scrubbing:
			# Threshold so a plain click (no drag) just clears selection.
			if not _wave_moved and _wave_press_pos.distance_to((event as InputEventMouseMotion).position) < _WAVE_DRAG_THRESHOLD_PX:
				return
			if not _wave_moved:
				_wave_moved = true
				Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
			# Grab semantics: delta in viewport px -> delta in seconds.
			# Pulling right ( +dx ) moves to earlier time, pulling left to later.
			var cur := (event as InputEventMouseMotion).position
			var delta_px := cur.x - _wave_press_pos.x
			var pps := _px_per_sec()
			var new_time := _wave_start_time - delta_px / pps if pps > 0.0 else _wave_start_time
			seek(new_time)
			return
		if _drag_beat < 0:
			return
		var target := _mouse_to_beat_ms((event as InputEventMouseMotion).position)
		if target != _drag_beat and _move_beat(_drag_beat, target):
			_drag_beat = target
			if not _drag_moved:
				_drag_moved = true
				Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _wave_scrubbing:
				var was_scrub := _wave_moved
				var was_playing := _wave_was_playing
				_wave_scrubbing = false
				_wave_moved = false
				_wave_was_playing = false
				_wave_start_time = 0.0
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				if was_scrub:
					get_viewport().set_input_as_handled()  # keep selection
					# Stop playback on drop as requested.
					if was_playing and mapping_player.playing and not mapping_player.stream_paused:
						mapping_player.stream_paused = true
				else:
					# Plain click without drag: clear moved flag, let _unhandled_input clear selection.
					pass
			_end_beat_drag()


func _on_marker_drag_started(beat_ms: int) -> void:
	if not _selected.has(beat_ms):
		return  # not selected: ignore the drag, release falls back to select
	_drag_beat = beat_ms
	_drag_moved = false


func _end_beat_drag() -> void:
	if _drag_moved:
		_suppress_click = true  # don't toggle selection on the drag release
		_refresh_shape_option()  # selection may have changed count mid-drag
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_drag_beat = -1
	_drag_moved = false


## Converts a viewport mouse x into beat ms via the markers' local coords.
## Clamped to [0, song length] so beats can't leave the waveform.
func _mouse_to_beat_ms(mouse_pos: Vector2) -> int:
	return int(round(_mouse_to_time_sec(mouse_pos) * 1000.0))


## Same as above as float seconds (for scrub-seek).
func _mouse_to_time_sec(mouse_pos: Vector2) -> float:
	if _markers_root == null:
		return 0.0
	var to_local: Transform2D = _markers_root.get_global_transform_with_canvas().affine_inverse()
	var t := (to_local * mouse_pos).x / _px_per_sec()
	t = maxf(0.0, t)
	if mapping_player.stream != null:
		t = minf(t, mapping_player.stream.get_length())
	return t


## Moves a beat to a new time. Returns false when another beat already owns
## the target (the marker stays put). Updates selection and any shape holding
## the beat; y is never touched.
func _move_beat(old_ms: int, new_ms: int) -> bool:
	if new_ms == old_ms:
		return true
	if not beat_times_ms.has(old_ms) or beat_times_ms.has(new_ms):
		return false
	beat_times_ms.erase(old_ms)
	beat_times_ms.append(new_ms)
	beat_times_ms.sort()
	var node = _marker_nodes.get(old_ms)
	if node != null:
		_marker_nodes.erase(old_ms)
		_marker_nodes[new_ms] = node
		node.beat_ms = new_ms
		node.position = Vector2(float(new_ms) / 1000.0 * _px_per_sec(), MARKER_Y)
	if _selected.has(old_ms):
		# Inline selection update (not _set_selected): the option dropdown
		# refresh is deferred to drag end so it doesn't rebuild per pixel.
		var sel := _selected.duplicate()
		sel.erase(old_ms)
		sel.append(new_ms)
		sel.sort()
		_selected = sel
		_refresh_marker_selection()
	var shapes_touched := false
	for shape in _shapes:
		var times: Array = shape["times_ms"]
		if times.has(old_ms):
			times.erase(old_ms)
			times.append(new_ms)
			times.sort()
			shapes_touched = true
	if shapes_touched:
		_rebuild_beat_shape_map()
		_refresh_shapes()
	return true


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


## Selects a shape by index (-1 = none). Clicking the selected shape again
## unselects it. Shape and beat selections are mutually exclusive.
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


## Shape nodes are ColorRects, so clicks arrive via gui_input (no hit-test).
func _on_shape_gui_input(event: InputEvent, node: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			var idx := _shape_nodes.find(node)
			if idx < 0:
				return
			_select_shape(-1 if idx == _selected_shape else idx)
			node.accept_event()


## Deletes the selected shape: frees the node, drops the record and releases
## its beats back to the pool (indices shift, so the map is rebuilt).
func _delete_selected_shape() -> void:
	if _selected_shape < 0 or _selected_shape >= _shapes.size():
		return
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


## Removes a beat from any shape holding it. Shapes left empty are deleted.
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


# --- transport -------------------------------------------------------------


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
		# NOTE: `playing` stays true while paused, so remember the pause or
		# every seek would unpause the song (and prev/next would unpause too).
		var was_paused := mapping_player.stream_paused
		mapping_player.play(clamped)
		mapping_player.stream_paused = was_paused
	_update_scroll()


func current_time() -> float:
	# While paused the live position is frozen, so the timeline (the actual
	# seek target) is the truth — otherwise prev/next keep computing from
	# the same stale head and only ever work once.
	if mapping_player.playing and not mapping_player.stream_paused:
		return mapping_player.get_playback_position()
	return float(timeline.value)


func _on_timeline_changed(v: float) -> void:
	if _scrubbing or not mapping_player.playing or mapping_player.stream_paused:
		seek(v)
		return
	# While actively playing, dragging would fight _process; just scroll.
	_update_scroll()


# --- waveform zoom -----------------------------------------------------------


func _on_waveform_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_waveform(1)
				waveform.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_waveform(-1)
				waveform.accept_event()


## Scroll up zooms in (more px per second), scroll down zooms out.
## Only the strip width changes (song_length * zoom); the repeating texture
## tiles natively, so zooming never allocates anything big.
## The playhead stays anchored: _update_scroll() keeps "now" at RECEPTOR_X.
func _zoom_waveform(steps: int) -> void:
	if waveform == null or steps == 0:
		return
	var target := clampf(_view_pps * pow(ZOOM_FACTOR, steps), MIN_PX_PER_SEC, MAX_PX_PER_SEC)
	if is_equal_approx(target, _view_pps):
		return
	_view_pps = target
	_size_waveform_strip()
	_rebuild_markers()
	_refresh_shapes()
	_update_scroll()


# --- beats -----------------------------------------------------------------


func add_beat_at_current() -> void:
	if mapping_player.stream == null:
		return
	var ms := int(round(current_time() * 1000.0))
	if beat_times_ms.has(ms):
		return
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
		# N with a selection deletes the whole selection, not the playhead beat.
		for t in _selected.duplicate():
			if beat_times_ms.has(t):
				beat_times_ms.erase(t)
				_strip_beat_from_shapes(t)
		_rebuild_markers()
		_set_selected([])
		return
	var now_ms := int(round(current_time() * 1000.0))
	var best := -1
	var best_err := int(DELETE_WINDOW_SEC * 1000.0)
	for t in beat_times_ms:
		var err := absi(t - now_ms)
		if err <= best_err:
			best_err = err
			best = t
	if best >= 0:
		beat_times_ms.erase(best)
		_strip_beat_from_shapes(best)
		_rebuild_markers()
		var sel := _selected.duplicate()
		sel.erase(best)
		_set_selected(sel)


func get_beat_times_ms() -> Array[int]:
	return beat_times_ms.duplicate()


func get_selected_beats_ms() -> Array[int]:
	return _selected.duplicate()


func get_shapes() -> Array[Dictionary]:
	return _shapes.duplicate()


func clear_beats() -> void:
	beat_times_ms.clear()
	_delete_all_shapes()
	_rebuild_markers()
	_set_selected([])


## Groups the selected beats into one shape_point child using ShapeOption's
## shape. The node spans first->last selected beat and scrolls with the column.
## Each beat can only belong to one shape, and the selection count must match
## the shape's required beats (shape_points.size() - 1). Custom uses precise
## point-click editor: points are 0..1 (same as mapping.gd:719-735) and count is
## constrained to beats + 1 (mirrors preset need = points-1) so output stays 0-1.
func _on_add_shape_pressed() -> void:
	if _selected.is_empty():
		push_warning(
			"mapping: select at least one beat first (click a marker, Shift+click for multi)."
		)
		return
	if _shapes_root == null:
		push_error("mapping: shapes container missing.")
		return
	var shape_name := "Square"
	if _shape_option != null and _shape_option.selected >= 0:
		shape_name = _shape_option.get_item_text(_shape_option.selected)
	var times := _selected.duplicate()
	times.sort()
	if shape_name == CUSTOM_SHAPE_NAME:
		for t in times:
			if _beat_shape_map.has(t):
				push_warning(
					(
						"mapping: beat %d is already used in shape %d, remove that shape first."
						% [t, int(_beat_shape_map[t])]
					)
				)
				return
		_show_custom_editor(times)
		return
	var need := _shape_required_beats(shape_name)
	if times.size() != need:
		push_warning(
			"mapping: %s needs %d selected beats, got %d." % [shape_name, need, times.size()]
		)
		return
	for t in times:
		if _beat_shape_map.has(t):
			push_warning(
				(
					"mapping: beat %d is already used in shape %d, remove that shape first."
					% [t, int(_beat_shape_map[t])]
				)
			)
			return
	_create_shape_entry(shape_name, times, _shape_points(shape_name), shape_name == "Square")
	_select_shape(_shapes.size() - 1)


## Shared constructor for editor shapes (Add button + chart import).
## Appends the record, spawns/positions the node and rebuilds the beat map.
## Assumes times are sorted ints and not already used by another shape.
## points are 0..1 normalized (same as mapping.gd:719-735); if empty, falls back
## to preset lookup.
func _create_shape_entry(shape_name: String, times: Array, points: PackedVector2Array = PackedVector2Array(), closed: bool = false) -> void:
	if _shapes_root == null:
		push_error("mapping: shapes container missing.")
		return
	var clean: Array[int] = []
	for t in times:
		clean.append(int(t))
	clean.sort()
	var pts := points
	if pts.is_empty():
		pts = _shape_points(shape_name)
		closed = shape_name == "Square"
	# Clamp custom points to 0..1 to guarantee output stays 0-1.
	if shape_name == CUSTOM_SHAPE_NAME:
		var clamped := PackedVector2Array()
		for p in pts:
			clamped.append(Vector2(clampf(p.x, 0.0, 1.0), clampf(p.y, 0.0, 1.0)))
		pts = clamped
	var shape_node = EDITOR_SHAPE_POINT.instantiate()
	_position_shape_node(shape_node, clean)
	var tag := Label.new()
	tag.text = "%s (%d)" % [shape_name, clean.size()]
	tag.theme = load("res://resources/theme/Theme.tres")
	tag.add_theme_font_size_override("font_size", 10)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shape_node.add_child(tag)
	shape_node.gui_input.connect(_on_shape_gui_input.bind(shape_node))
	_shapes_root.add_child(shape_node)
	shape_node.init(pts)
	_shapes.append({"shape": shape_name, "times_ms": clean, "points": pts, "closed": closed})
	_shape_nodes.append(shape_node)
	_rebuild_beat_shape_map()


## Positions/sizes a shape node from its beat times at the current zoom.
func _position_shape_node(shape_node: Control, times: Array) -> void:
	var pps := _px_per_sec()
	var x0 := float(times[0]) / 1000.0 * pps
	var x1 := float(times[times.size() - 1]) / 1000.0 * pps
	shape_node.position = Vector2(x0, SHAPE_Y)
	var w := maxf(42.0, x1 - x0 + 42.0)
	shape_node.custom_minimum_size = Vector2(w, 42.0)
	shape_node.size = Vector2(w, 42.0)


## Re-anchor all shape nodes after a zoom (same idea as _rebuild_markers).
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


## Required beats for a shape = outline points - 1 (closing point reuses one).
## Square = 4, U = 3, L = 2, HLine/VLine = 1. Custom needs beats+1 points so
## need = beats (points = beats+1), constrained relative to selected beats.
func _shape_required_beats(shape_name: String) -> int:
	if shape_name == CUSTOM_SHAPE_NAME:
		# Dynamic: Custom always expects selected.size() beats -> points = beats+1.
		# When no selection, show as needing 1 so it appears disabled correctly.
		if _selected.is_empty():
			return 1
		return _selected.size()
	return maxi(1, _shape_points(shape_name).size() - 1)


func _custom_total_point_count() -> int:
	# N beats -> N+1 total points (Square 4 beats -> 5 pts), 0..1 normalized.
	return maxi(2, _custom_pending_times.size() + 1)


func _custom_expected_point_count() -> int:
	# Kept for compat — total points. Closed user input is total-1 (auto duplicate).
	return _custom_total_point_count()


func _custom_user_needed() -> int:
	var total := _custom_total_point_count()
	if _custom_closed:
		return maxi(1, total - 1)
	return total


## ShapeOption only offers shapes matching the current selection count, so the
## Add button is only usable with a valid beat count. Empty selection restores
## the full list (with Add disabled). Preset + Custom: Custom is always offered
## when beats are selected (constrained to beats+1 points).
func _refresh_shape_option() -> void:
	if _shape_option == null:
		return
	var prev := ""
	if _shape_option.selected >= 0 and _shape_option.item_count > 0:
		prev = _shape_option.get_item_text(_shape_option.selected)
	_shape_option.clear()
	if _selected.is_empty():
		for s in SHAPE_NAMES:
			_shape_option.add_item(s)
	else:
		for s in SHAPE_NAMES:
			if _shape_required_beats(s) == _selected.size():
				_shape_option.add_item(s)
		# Preset + Custom: Custom is constrained relative to selected beats.
		_shape_option.add_item(CUSTOM_SHAPE_NAME)
	var pick := 0
	for i in range(_shape_option.item_count):
		if _shape_option.get_item_text(i) == prev:
			pick = i
			break
	if _shape_option.item_count > 0:
		_shape_option.select(pick)
	var valid := not _selected.is_empty() and _shape_option.item_count > 0
	_shape_option.disabled = not valid and not _selected.is_empty()
	if _btn_add_shape != null:
		_btn_add_shape.disabled = not valid


## Normalized 0..1 points — editor_shape_point.init() scales them by 40px.
func _shape_points(shape_name: String) -> PackedVector2Array:
	match shape_name:
		"L":
			return PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)])
		"L90":
			return PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
		"L180":
			return PackedVector2Array([Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		"L270":
			return PackedVector2Array([Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)])
		"LFlip":
			return PackedVector2Array([Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)])
		"U":
			return PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
		"UInv":
			return PackedVector2Array([Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
		"Square":
			return PackedVector2Array(
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]
			)
		"Triangle":
			return PackedVector2Array([Vector2(0.5, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0.5, 0)])
		"HLine":
			return PackedVector2Array([Vector2(0, 0.5), Vector2(1, 0.5)])
		"VLine":
			return PackedVector2Array([Vector2(0.5, 0), Vector2(0.5, 1)])
		"Diag":
			return PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
		"DiagInv":
			return PackedVector2Array([Vector2(1, 0), Vector2(0, 1)])
		"ZigZag":
			return PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	return PackedVector2Array(
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]
	)


# --- custom shape editor (precise point-click, 0-1, beat-constrained) -----

func _setup_custom_editor() -> void:
	# Declarative tscn version — just wire draw/input, hide initially.
	if _custom_panel != null:
		_custom_panel.visible = false
	if _custom_grid != null and not _custom_grid.draw.is_connected(_on_custom_grid_draw):
		_custom_grid.draw.connect(_on_custom_grid_draw)
	if _custom_canvas != null and not _custom_canvas.gui_input.is_connected(_on_custom_canvas_input):
		_custom_canvas.gui_input.connect(_on_custom_canvas_input)
	# Buttons/CheckBox are wired via tscn [connection] to _on_custom_*.


func _ensure_custom_editor() -> void:
	# Compat shim — now declarative.
	_setup_custom_editor()


func _show_custom_editor(times: Array) -> void:
	_ensure_custom_editor()
	_custom_pending_times = []
	for t in times:
		_custom_pending_times.append(int(t))
	_custom_points = PackedVector2Array()
	_custom_closed = false
	if _custom_closed_check != null:
		_custom_closed_check.button_pressed = false
	_custom_drag_idx = -1
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
	var need := _custom_expected_point_count()
	var user_need := _custom_user_needed()
	# Closed cannot be checked if needed point < 4 (total < 4)
	if _custom_closed_check != null:
		_custom_closed_check.disabled = total < 4
		if total < 4 and _custom_closed:
			_custom_closed = false
			_custom_closed_check.button_pressed = false
	if _custom_closed:
		_custom_info_label.text = "Beats: %d  • Need %d (+1 auto) = %d pts (0..1)  • Placed: %d" % [_custom_pending_times.size(), user_need, total, _custom_points.size()]
	else:
		_custom_info_label.text = "Beats: %d  • Need %d points (0..1)  • Placed: %d" % [_custom_pending_times.size(), need, _custom_points.size()]
	_custom_confirm_btn.disabled = _custom_points.size() != total
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
	# If user has placed N-1 distinct points, auto-generate Nth = first.
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
	# 0..1 border
	_custom_grid.draw_rect(Rect2(Vector2.ZERO, s), Color(0.5, 0.5, 0.5, 0.6), false, 1.0)
	# Grid lines
	_custom_grid.draw_line(Vector2(s.x * 0.5, 0), Vector2(s.x * 0.5, s.y), Color(0.3, 0.3, 0.3, 1), 1.0)
	_custom_grid.draw_line(Vector2(0, s.y * 0.5), Vector2(s.x, s.y * 0.5), Color(0.3, 0.3, 0.3, 1), 1.0)
	var pts := _custom_points
	for i in range(pts.size()):
		var pos := Vector2(pts[i].x * s.x, pts[i].y * s.y)
		var col := Color(0.2, 0.8, 1.0, 1.0) if i == pts.size() - 1 else Color(1.0, 0.85, 0.2, 1.0)
		_custom_grid.draw_circle(pos, 5.0, col)
		_custom_grid.draw_string(ThemeDB.fallback_font, pos + Vector2(6, -6), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _on_custom_canvas_input(event: InputEvent) -> void:
	if _custom_canvas == null:
		return
	var total := _custom_total_point_count()
	# For closed, user only places total-1 distinct, last auto-generated.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var local := mb.position
			var s := _custom_canvas.size
			# Check drag existing point
			var idx := _hit_custom_point(local, s)
			if idx >= 0:
				# Don't allow dragging the auto-generated last point directly when closed
				if _custom_closed and idx == _custom_points.size() - 1 and _custom_points.size() == total:
					idx = 0
				_custom_drag_idx = idx
				_custom_canvas.accept_event()
				return
			if _custom_points.size() >= total:
				return
			# Closed flow: placing the (N-1)th point auto-generates Nth == first
			if _custom_closed and _custom_points.size() == total - 1:
				return
			var norm := Vector2(clampf(local.x / s.x, 0.0, 1.0), clampf(local.y / s.y, 0.0, 1.0))
			_custom_points.append(norm)
			if _custom_closed and _custom_points.size() == total - 1:
				# Auto-generate fifth point on the first point (N-1 -> N)
				_custom_points.append(_custom_points[0])
			_update_custom_editor()
			_custom_canvas.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_custom_drag_idx = -1
			_update_custom_editor()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_on_custom_undo()
			_custom_canvas.accept_event()
	elif event is InputEventMouseMotion:
		if _custom_drag_idx >= 0 and _custom_drag_idx < _custom_points.size():
			var s := _custom_canvas.size
			var local := (event as InputEventMouseMotion).position
			_custom_points[_custom_drag_idx] = Vector2(clampf(local.x / s.x, 0.0, 1.0), clampf(local.y / s.y, 0.0, 1.0))
			if _custom_closed and _custom_points.size() == total:
				if _custom_drag_idx == 0:
					_custom_points[_custom_points.size() - 1] = _custom_points[0]
				elif _custom_drag_idx == _custom_points.size() - 1:
					_custom_points[0] = _custom_points[_custom_drag_idx]
			_update_custom_editor()


func _hit_custom_point(pos: Vector2, canvas_size: Vector2) -> int:
	for i in range(_custom_points.size()):
		var pp := Vector2(_custom_points[i].x * canvas_size.x, _custom_points[i].y * canvas_size.y)
		if pos.distance_to(pp) < 10.0:
			return i
	return -1


func _on_custom_closed_toggled(v: bool) -> void:
	var total := _custom_total_point_count()
	if total < 4 and v:
		# Closed not allowed when needed point < 4
		if _custom_closed_check != null:
			_custom_closed_check.button_pressed = false
		return
	_custom_closed = v
	if _custom_closed:
		# If user already placed N-1 points, auto-generate Nth
		if _custom_points.size() == total - 1:
			_custom_points.append(_custom_points[0])
		elif _custom_points.size() == total:
			_custom_points[total - 1] = _custom_points[0]
	else:
		# Unchecking closed: if last == first duplicate, remove auto point
		if _custom_points.size() == total and _custom_points.size() >= 2 and _custom_points[0].is_equal_approx(_custom_points[_custom_points.size() - 1]):
			_custom_points.remove_at(_custom_points.size() - 1)
	_update_custom_editor()


func _on_custom_undo() -> void:
	if _custom_points.size() == 0:
		return
	# If closed and last is auto duplicate, remove it together with undo logic
	if _custom_closed:
		var total := _custom_total_point_count()
		if _custom_points.size() == total and _custom_points.size() >= 2 and _custom_points[0].is_equal_approx(_custom_points[_custom_points.size() - 1]):
			_custom_points.remove_at(_custom_points.size() - 1)
			_update_custom_editor()
			return
	_custom_points.remove_at(_custom_points.size() - 1)
	_update_custom_editor()


func _on_custom_clear() -> void:
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
	# Closed output still has N+1 points where last == first (Square: 4 beats -> 5 pts)
	if _custom_closed and pts.size() >= 2:
		pts[pts.size() - 1] = pts[0]
	_hide_custom_editor()
	var times := _custom_pending_times.duplicate()
	_custom_pending_times.clear()
	_create_shape_entry(CUSTOM_SHAPE_NAME, times, pts, _custom_closed)
	_select_shape(_shapes.size() - 1)

# --- chart import / song loading -------------------------------------------


func _on_level_creator_chart_imported(chart: ChartData) -> void:
	if chart == null or chart.metadata.is_empty():
		return
	var metadata: Dictionary = chart.metadata
	if metadata.has("song"):
		_load_song(chart.song_path())
	_import_beats_and_shapes(chart)


## Rebuilds editor beats + shapes from a parsed ChartData.
## All @ times become beat markers; notes grouped by shape id become editor
## shapes with their type inferred from beat count (and H/V geometry for
## single-beat shapes). Custom/unsupported groups (e.g. 5+ beats, rotated
## geometry) keep their beats as solo markers so no timing is lost.
func _import_beats_and_shapes(chart: ChartData) -> void:
	clear_beats()
	if chart.notes.is_empty():
		return
	# Group note times by shape id, preserving chart sort (by start time).
	var times_by_id: Dictionary = {}
	var order: Array = []
	for note in chart.notes:
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
	# Order shape ids by first beat time (matches parser's shape sort).
	order.sort_custom(
		func(a: String, b: String) -> bool:
			var ta: Array = times_by_id[a]
			var tb: Array = times_by_id[b]
			return int((ta as Array)[0]) < int((tb as Array)[0])
	)
	for sid in order:
		var times: Array = (times_by_id[sid] as Array).duplicate()
		times.sort()
		var pts := chart.shape_points_by_id(sid)
		# Normalize imported pts to 0..1 already stored that way.
		var editor_shape := _infer_editor_shape(times.size(), pts)
		if editor_shape.is_empty():
			# Custom/unsupported: preserve as Custom (0..1) so no timing is lost.
			if pts.size() >= 2:
				var is_closed := pts.size() >= 3 and pts[0].is_equal_approx(pts[pts.size() - 1])
				var clean_pts := pts
				if is_closed:
					# Keep duplicate for Square-style but editor stores without dup + closed flag.
					# For custom we keep points as-is and set closed.
					pass
				_create_shape_entry(CUSTOM_SHAPE_NAME, times, clean_pts, is_closed)
			continue
		if times.size() != _shape_required_beats(editor_shape):
			# Fallback to Custom if count mismatch but geometry exists
			if pts.size() >= 2:
				var is_closed2 := pts.size() >= 3 and pts[0].is_equal_approx(pts[pts.size() - 1])
				_create_shape_entry(CUSTOM_SHAPE_NAME, times, pts, is_closed2)
			continue
		var is_closed := editor_shape == "Square" or editor_shape == "Triangle"
		_create_shape_entry(editor_shape, times, _shape_points(editor_shape), is_closed)
	_rebuild_markers()
	_refresh_shapes()
	_set_selected([])
	_select_shape(-1)
	seek(0.0)


## Maps a chart shape back to an editor shape type.
## Now handles new templates: L rotations, UInv, Triangle, Diag etc.
## Count is primary, geometry refines (except circle which is excluded).
func _infer_editor_shape(count: int, pts: PackedVector2Array) -> String:
	match count:
		4:
			if _pts_match(pts, _shape_points("Square")):
				return "Square"
			return "Square"
		3:
			if _pts_match(pts, _shape_points("Triangle")):
				return "Triangle"
			if _pts_match(pts, _shape_points("ZigZag")):
				return "ZigZag"
			if _pts_match(pts, _shape_points("UInv")):
				return "UInv"
			if _pts_match(pts, _shape_points("U")):
				return "U"
			return "U"
		2:
			for n in ["L", "L90", "L180", "L270", "LFlip"]:
				if _pts_match(pts, _shape_points(n)):
					return n
			return "L"
		1:
			if _pts_match(pts, _shape_points("Diag")):
				return "Diag"
			if _pts_match(pts, _shape_points("DiagInv")):
				return "DiagInv"
			if pts.size() >= 2:
				var dx := 0.0
				var dy := 0.0
				for i in range(1, pts.size()):
					dx = maxf(dx, absf(pts[i].x - pts[i - 1].x))
					dy = maxf(dy, absf(pts[i].y - pts[i - 1].y))
				if _pts_match(pts, _shape_points("VLine")) or dy > dx:
					return "VLine"
				if _pts_match(pts, _shape_points("HLine")):
					return "HLine"
			return "HLine"
	return ""


func _pts_match(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


func _load_song(path: String) -> void:
	var p := path.strip_edges()
	if p.is_empty():
		return
	if metadata_group == null or not metadata_group.has_method("_load_audio_stream"):
		push_error("mapping: METADATA group missing _load_audio_stream().")
		return
	var stream: AudioStream = metadata_group._load_audio_stream(p)
	if stream == null:
		push_error("mapping: could not load audio: " + p)
		return
	mapping_player.stop()
	mapping_player.stream_paused = false
	mapping_player.stream = stream
	_size_waveform_strip()
	_sync_timeline_range()
	seek(0.0)


# --- internals ---------------------------------------------------------------


func _px_per_sec() -> float:
	return _view_pps


func _sync_timeline_range() -> void:
	if mapping_player.stream == null:
		timeline.max_value = 0.0
		return
	timeline.max_value = maxf(0.0, mapping_player.stream.get_length())
	timeline.set_value_no_signal(0.0)


func _update_scroll() -> void:
	if beat_column == null:
		return
	# Scroll the waveform left as the song plays so "now" stays at RECEPTOR_X.
	beat_column.position = Vector2(COLUMN_BASE.x - current_time() * _px_per_sec(), COLUMN_BASE.y)


## Called every frame while preview is playing: if an editor_beat_point's
## x in MAPPING space has just crossed the unique LineGenerator (x=144),
## play the hitsound (via %HitSound, also unique). Uses geometric check
## beat_column.x + marker.x <= _line_generator.x so it stays correct at any zoom.
## _hitsound_fired prevents retrigger until the beat moves ahead again (seek/rewind).
func _check_beats_passed_line_generator(_pos: float) -> void:
	if _line_generator == null or beat_column == null or _markers_root == null:
		return
	# Unique access verified: level_creator.tscn has %LineGenerator (unique_name_in_owner)
	var line_x := _line_generator.position.x # MAPPING-local, 144.0
	var col_x := beat_column.position.x
	for t in beat_times_ms:
		var marker = _marker_nodes.get(t)
		if marker == null or not is_instance_valid(marker):
			continue
		# marker.position is in _markers_root-local (which is at 0 inside beat_column)
		var marker_x_in_mapping : float= col_x + marker.position.x
		var passed := marker_x_in_mapping <= line_x + 0.1 # tiny epsilon for float/1px mismatch
		var was_fired: bool = _hitsound_fired.has(t)
		if passed and not was_fired:
			# hitsound is also unique (%HitSound) in level_creator.tscn
			if hitsound != null:
				hitsound.play()
			_hitsound_fired[t] = true
		elif not passed and was_fired:
			_hitsound_fired.erase(t)


## Sizes the tiling strip to song_length * zoom. It starts at song time 0
## in column space, so markers (x = time * pps) always line up with it.
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
	_end_beat_drag()  # nodes are freed below; a drag can't survive a rebuild
	for child in _markers_root.get_children():
		child.queue_free()
	_marker_nodes.clear()
	# prune fired entries for beats that no longer exist (keeps rewind logic)
	for k in _hitsound_fired.keys():
		if not beat_times_ms.has(k):
			_hitsound_fired.erase(k)
	for t in beat_times_ms:
		var marker = EDITOR_BEAT_POINT.instantiate()
		marker.position = Vector2(float(t) / 1000.0 * _px_per_sec(), MARKER_Y)
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
