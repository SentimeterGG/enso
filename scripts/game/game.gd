# game.gd — Main gameplay controller: loads the .enso chart, plays the music,
# Main responsibilities: chart loading, music playback, note/shape scheduling.
# RETURN: synced notes, target shape display and music timing for drawing and judging
extends Node2D

const CHART_PATH := "res://levels/Wasurete-Yaranai/chart.enso"
@onready var draw_manager: Line2D = $draw
@onready var note_manager: Node2D = $note_manager
@onready var target_shape: Line2D = $target_shape
@onready var animator: AnimationPlayer = $animator
@onready var video_stream_player = %VideoStreamPlayer
@onready var bg_sprite : TextureRect = %BG
var note_scheduler: NoteScheduler = NoteScheduler.new()


func _ready():
	MouseOverlay.process_mode = Node.PROCESS_MODE_DISABLED
	MouseOverlay.hide()
	BgMusic.change_song(null)
	Input.set_custom_mouse_cursor(SkinManager.cursor_sprite, Input.CURSOR_ARROW, Vector2(12,12))
	animator.play("Intro")
	if Global.current_chart == null:
		Global.current_chart = LevelLoader.load_chart(CHART_PATH)
		if Global.current_chart.get_video_background() != "":
			video_stream_player.stream = load(Global.current_chart.get_video_background())
		if Global.current_chart.get_bg() != "":
			bg_sprite.texture = load(Global.current_chart.get_bg())
		DiscordRPC.set_activity("Drawing Shape", (Global.current_chart.get_song_title() + " - " + Global.current_chart.get_song_source()))


func _process(_delta: float) -> void:
	note_scheduler.process(note_manager, BgMusic, Global.current_chart, target_shape)


func _on_animator_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Intro":
		BgMusic.change_song(load(Global.current_chart.song_path()))
		animator.play("bg_fade")
		video_stream_player.play()
		target_shape.clear_points()
		note_scheduler.start(note_manager)
		draw_manager.start()
	pass  # Replace with function body.
