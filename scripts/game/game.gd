# game.gd — Main gameplay controller: loads the .enso chart, plays the music,
# Main responsibilities: chart loading, music playback, note/shape scheduling.
# RETURN: synced notes, target shape display and music timing for drawing and judging
extends Node2D

const CHART_PATH := "res://levels/doppleganger/chart.enso"
@onready var draw_manager: Line2D = $draw
@onready var note_manager: Node2D = $note_manager
@onready var target_shape: Line2D = $target_shape
@onready var animator: AnimationPlayer = $animator
var note_scheduler: NoteScheduler = NoteScheduler.new()


func _ready():
	BgMusic.change_song(null)
	animator.play("Intro")


func _process(_delta: float) -> void:
	note_scheduler.process(note_manager, BgMusic, Global.current_chart, target_shape)


func _on_animator_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Intro":
		if Global.current_chart == null:
			Global.current_chart = LevelLoader.load_chart(CHART_PATH)
		BgMusic.change_song(load(Global.current_chart.song_path()))
		target_shape.clear_points()
		note_scheduler.start(note_manager)
		draw_manager.start()
	pass  # Replace with function body.
