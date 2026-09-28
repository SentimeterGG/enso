# note_manager.gd — Scrolling-note spawner facade: computes lane length from
# spawner-to-receptor distance for sync timing and forwards spawn() calls to
# the beat column with hit time, scroll speed and color.
# RETURN: scrolling beat notes spawned down the lane
extends VBoxContainer

@export var px_per_second: float = 400.0
@onready var shape_column: Control = $shape_column
@onready var beat_column: Control = $beat_column
const BEAT_SCENE: PackedScene = preload("res://scenes/beat_point.tscn")
const SHAPE_SCENE: PackedScene = preload("res://scenes/shape_point.tscn")
const NOTE_SIZE := 42.0
const RESYNC_INTERVAL := 30.0
const RESYNC_DURATION := 0.2
var next_resync = 30.0
var resync_end = 30.1
enum ScrollMode { DELTA, MUSIC_CLOCK }
var scroll_mode: ScrollMode = ScrollMode.DELTA
@onready var _start_x = %beat_receptor.position.x
# @onready var resync_label: Label = %resync_label
var start = false
var add_counter = true
var resync_counter = 0


func _start():
	start = true


func _process(delta: float) -> void:
	var music_time = BgMusic.get_playback_position()
	if start:
		if music_time > next_resync:
			if add_counter == true:
				resync_counter += 1
				add_counter = false
			scroll_mode = ScrollMode.MUSIC_CLOCK
			resync_end = music_time + RESYNC_DURATION
			next_resync = music_time + RESYNC_INTERVAL
		elif scroll_mode == ScrollMode.MUSIC_CLOCK and music_time > resync_end:
			scroll_mode = ScrollMode.DELTA
			add_counter = true
		match scroll_mode:
			ScrollMode.DELTA:
				self.position.x -= px_per_second * delta
				# resync_label.text = "RESYNC TRIGGERED: " + str(resync_counter) + "x" + "\n DELTA"
			ScrollMode.MUSIC_CLOCK:
				self.position.x = _start_x - BgMusic.get_playback_position() * px_per_second
				# resync_label.text = (
				# 	"RESYNC TRIGGERED: " + str(resync_counter) + "x" + "\n MUSIC_CLOCK"
				# )


func bake(chart_data: ChartData):
	px_per_second = Global.settingsData.scroll_speed
	if chart_data == null or chart_data.is_empty():
		return
	var beat_layer: Control = $beat_column
	var shape_layer: Control = $shape_column
	for index in chart_data.note_count():
		var note: Dictionary = chart_data.get_note(index)
		var ms := chart_data.note_time(index)
		if ms <= 0.0:
			ms = float(note.get("time", 0.0))
		var id := str(note.get("id", ""))
		var beat_point := BEAT_SCENE.instantiate() as Control
		beat_point.position = Vector2(ms / 1000.0 * px_per_second, 0.0)
		beat_point.set("hit_time", ms / 1000.0)
		beat_point.set("beat_id", id)
		beat_point.self_modulate = chart_data.shape_colors.get(id, Color.WHITE)
		beat_point.mouse_filter = Control.MOUSE_FILTER_IGNORE
		beat_layer.add_child(beat_point)
	for index in chart_data.shape_count():
		var shape_id := ""
		if index < chart_data.shape_ids.size():
			shape_id = str(chart_data.shape_ids[index])
		var shape_time: Array = chart_data.shape_time(index)
		var start_ms := float(shape_time[0])
		var end_ms := float(shape_time[1])
		var width_px := NOTE_SIZE + maxf(0.0, end_ms - start_ms) / 1000.0 * px_per_second
		var shape_point := SHAPE_SCENE.instantiate() as Control
		shape_point.position = Vector2(start_ms / 1000.0 * px_per_second, 0.0)
		shape_point.size = Vector2(width_px, NOTE_SIZE)
		shape_point.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: Color = chart_data.shape_colors.get(shape_id, Color.WHITE)
		shape_point.color = col
		shape_layer.add_child(shape_point)
		shape_point.init(chart_data.shape_points_at(index))
