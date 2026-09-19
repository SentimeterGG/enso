extends Control
## Mapping tab: audition the song, scrub the timeline and tap M/N to drop beat
## markers on the waveform. Markers scroll with `beat_collumn` so the receptor
## Line2D (x ~= 144) always shows "now".
## Click a marker to select it (Shift+click for multi-select), then "Add Shape"
## groups the selected beats into one shape_point child using ShapeOption's shape.
## Click a shape to select it (gold highlight), Delete/Backspace removes it and
## releases its beats. N-deleted beats are stripped from shapes (emptied shapes
## are deleted); clear_beats() clears shapes too.
##
## Scene layout (scenes/level_creator.tscn, LevelCreator/MAPPING):
##   BEATSPAWNER (Node2D) .................. kept for compatibility, unused
##   HSlider (HSlider) ..................... timeline scrubber (seconds)
##   HBoxContainer/{go_to_start,go_to_prev_beat,start,go_to_next_beat,go_to_end}
##   MappingPreviewPlayer (AudioStreamPlayer, unique name)
##   beat_collumn (Node2D) ................. scrolled container (note the sic)
##     AudioStreamPreview (TextureRect) .... tiling strip sized to
##       song_length * px_per_sec; your own texture repeats across it
##       (stretch_mode = TILE), so no giant texture is ever allocated.
##   "Add Shape" (Button) + ShapeOption (OptionButton: L/U/Square/HLine/VLine)
## RETURN: transport playback + beat_times_ms markers + _shapes via get_shapes()

const EDITOR_BEAT_POINT := preload("res://scenes/editor_beat_point.tscn")
const EDITOR_SHAPE_POINT := preload("res://scenes/editor_shape_point.tscn")

@onready var mapping_player: AudioStreamPlayer = %MappingPreviewPlayer
@onready var timeline: HSlider = %MappingPreviewCurrentPos
@onready var beat_column: Node2D = $beat_collumn
@onready var waveform: TextureRect = $beat_collumn/AudioStreamPreview
@onready var metadata_group: Control = %METADATA
@onready var hitsound: AudioStreamPlayer = %HitSound

@onready var _btn_start: Button = $HBoxContainer/go_to_start
@onready var _btn_play: Button = $HBoxContainer/start
@onready var _btn_end: Button = $HBoxContainer/go_to_end
@onready var _btn_add_shape: Button = $"Add Shape"
@onready var _shape_option: OptionButton = $ShapeOption

## All shape names in ShapeOption (scenes/level_creator.tscn order).
const SHAPE_NAMES := ["L", "U", "Square", "HLine", "VLine"]
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
## Created shapes: {shape: String, times_ms: Array[int]}.
var _shapes: Array[Dictionary] = []
## Shape scene nodes parallel to _shapes (for zoom repositioning).
var _shape_nodes: Array = []
## beat time ms -> index into _shapes. A beat can only belong to one shape.
var _beat_shape_map: Dictionary = {}
var _scrubbing := false
var _markers_root: Node2D = null
var _shapes_root: Node2D = null
## beat time ms -> editor_beat_point instance.
var _marker_nodes: Dictionary = {}


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


func _process(_delta: float) -> void:
	if mapping_player.stream == null:
		return
	if mapping_player.playing:
		var pos := mapping_player.get_playback_position()
		timeline.set_value_no_signal(pos)
		_update_scroll()
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
	hitsound.play()
	beat_times_ms.sort()
	_rebuild_markers()


func remove_beat_at_current() -> void:
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
## the shape's required beats (shape_points.size() - 1).
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
	_create_shape_entry(shape_name, times)
	_select_shape(_shapes.size() - 1)


## Shared constructor for editor shapes (Add button + chart import).
## Appends the record, spawns/positions the node and rebuilds the beat map.
## Assumes times are sorted ints and not already used by another shape.
func _create_shape_entry(shape_name: String, times: Array) -> void:
	if _shapes_root == null:
		push_error("mapping: shapes container missing.")
		return
	var clean: Array[int] = []
	for t in times:
		clean.append(int(t))
	clean.sort()
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
	shape_node.init(_shape_points(shape_name))
	_shapes.append({"shape": shape_name, "times_ms": clean})
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
## Square = 4, U = 3, L = 2, HLine/VLine = 1.
func _shape_required_beats(shape_name: String) -> int:
	return maxi(1, _shape_points(shape_name).size() - 1)


## ShapeOption only offers shapes matching the current selection count, so the
## Add button is only usable with a valid beat count. Empty selection restores
## the full list (with Add disabled).
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
		"U":
			return PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
		"Square":
			return PackedVector2Array(
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]
			)
		"HLine":
			return PackedVector2Array([Vector2(0, 0.5), Vector2(1, 0.5)])
		"VLine":
			return PackedVector2Array([Vector2(0.5, 0), Vector2(0.5, 1)])
	return PackedVector2Array(
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]
	)


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
		var editor_shape := _infer_editor_shape(times.size(), pts)
		if editor_shape.is_empty():
			continue  # leave beats ungrouped (solo markers)
		if times.size() != _shape_required_beats(editor_shape):
			continue
		_create_shape_entry(editor_shape, times)
	_rebuild_markers()
	_refresh_shapes()
	_set_selected([])
	_select_shape(-1)
	seek(0.0)


## Maps a chart shape back to an editor shape type.
## Count is decisive (Square=4, U=3, L=2); single-beat shapes use geometry
## (wide => HLine, tall => VLine). Returns "" when not representable.
func _infer_editor_shape(count: int, pts: PackedVector2Array) -> String:
	match count:
		4:
			return "Square"
		3:
			return "U"
		2:
			return "L"
		1:
			if pts.size() >= 2:
				var dx := 0.0
				var dy := 0.0
				for i in range(1, pts.size()):
					dx = maxf(dx, absf(pts[i].x - pts[i - 1].x))
					dy = maxf(dy, absf(pts[i].y - pts[i - 1].y))
				if dy > dx:
					return "VLine"
			return "HLine"
	return ""


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
