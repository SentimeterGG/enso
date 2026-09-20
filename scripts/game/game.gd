# game.gd — Main gameplay controller: loads the .enso chart, plays the music,
# Main responsibilities: chart loading, music playback, note/shape scheduling.
# RETURN: synced notes, target shape display and music timing for drawing and judging
extends Node2D


@export var CHART_PATH := "res://levels/Wasurete Yaranai by kessoku band mapped by ENSO Team/chart.enso"
@onready var draw_manager: Line2D = $draw
@onready var note_manager: Node2D = $note_manager
@onready var target_shape: Line2D = $target_shape
@onready var animator: AnimationPlayer = $animator
@onready var video_stream_player = %VideoStreamPlayer
@onready var bg_sprite : TextureRect = %BG

var note_scheduler: NoteScheduler = NoteScheduler.new()

var _preroll_sec := 0.0

var _virtual_time := 0.0
var _music_started := false


func get_preroll_sec() -> float:
	return _preroll_sec


func get_virtual_song_time() -> float:
	if _music_started and BgMusic.playing:
		return BgMusic.get_playback_position() + _preroll_sec
	return _virtual_time


func is_preroll_silence() -> bool:
	return note_scheduler.playing and not _music_started and _preroll_sec > 0.001


## Auto preroll: travel time (lane_length/px_per_sec) minus first note time.
## If first beat is already past the travel time, no silence is needed.
func _compute_preroll_sec() -> float:
	if note_manager == null:
		return 0.0
	var px: float = note_manager.px_per_sec
	if px <= 0.0:
		return 0.0
	var lead_ms: float = note_manager.lane_length() / px * 1000.0
	var chart := Global.current_chart
	if chart == null or chart.note_count() <= 0:
		return 0.0
	var first_ms: float = float(chart.note_time(0))
	if first_ms < lead_ms:
		return (lead_ms - first_ms) / 1000.0
	return 0.0


func _ready():
	BgMusic.change_song(null)
	Input.set_custom_mouse_cursor(SkinManager.cursor_sprite, Input.CURSOR_ARROW, Vector2(12,12))
	animator.play("Intro")
	if Global.current_chart == null:
		Global.current_chart = LevelLoader.load_chart(CHART_PATH)
	if Global.current_chart.get_video_background() != "":
		video_stream_player.stream = load(Global.current_chart.get_video_background())
	if Global.current_chart.get_bg() != "":
		bg_sprite.texture = load(Global.current_chart.get_bg())
	if Global.settingsData.video_bg:
		if Global.current_chart.get_video_background() == "":
			%BG.visible = true
			%VideoStreamPlayer.visible = false
		else:
			%BG.visible = false
			%VideoStreamPlayer.visible = true
	else:
		%BG.visible = true
		%VideoStreamPlayer.visible = false
	DiscordRPC.set_activity("Drawing Shape", (Global.current_chart.get_song_title() + " - " + Global.current_chart.get_song_source()))


func _process(delta: float) -> void:
	if note_scheduler.playing and not _music_started:
		_virtual_time = minf(_virtual_time + delta, _preroll_sec)
	note_scheduler.process(note_manager, get_virtual_song_time(), Global.current_chart, target_shape)


func _on_animator_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Intro":
		# Auto preroll so the first note spawns exactly at the spawner.
		# Notes scroll during the silence; input stays blocked until music plays.
		_preroll_sec = _compute_preroll_sec()
		_virtual_time = 0.0
		_music_started = false
		note_scheduler.start(note_manager, _preroll_sec)
		target_shape.clear_points()
		draw_manager.start()
		var sc := get_node_or_null("%accuracy_manager")
		if sc != null and sc.has_method("reset"):
			sc.refresh_od()
			sc.reset()
		if _preroll_sec > 0.001:
			await get_tree().create_timer(_preroll_sec, false).timeout
			if not is_inside_tree():
				return
		BgMusic.start_song(load(Global.current_chart.song_path()))
		_music_started = true
		animator.play("bg_fade")
		video_stream_player.play()
	%TransOffset.modulate = Color(1.0, 1.0, 1.0, Global.settingsData.bg_visibilty*0.01)
	
func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(load("res://assets/sprites/UI/crosshair.png"), Input.CURSOR_ARROW, Vector2(12,12))
