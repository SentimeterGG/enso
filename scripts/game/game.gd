# game.gd — Main gameplay controller: loads the .enso chart, plays the music,
# Main responsibilities: chart loading, music playback, note/shape scheduling.
# RETURN: synced notes, target shape display and music timing for drawing and judging
extends Control
class_name gameplay_manager

@export
var CHART_PATH := "res://levels/Wasurete Yaranai by kessoku band mapped by ENSO Team/chart.enso"
@onready var draw_manager: Line2D = %draw
@onready var note_manager: VBoxContainer = %note_column
@onready var target_shape: Line2D = $target_shape
@onready var animator: AnimationPlayer = %animator
@onready var video_stream_player = %VideoStreamPlayer
@onready var accuracy_manager := %accuracy_manager
var video_bg_visible = false
var _video_fade_tween: Tween = null


func _ready():
	%video_bg.modulate = Color(1.0, 1.0, 1.0, Global.settingsData.bg_visibilty * 0.01)
	GlobalBackground.disable_parallax()
	BgMusic.change_song(null)
	BgMusic._disable_loop()
	Input.set_custom_mouse_cursor(SkinManager.cursor_sprite, Input.CURSOR_ARROW, Vector2(12, 12))
	animator.play("Intro")
	if Global.current_chart == null:
		Global.current_chart = LevelLoader.load_chart(CHART_PATH)
	if Global.current_chart.get_video_background() != "":
		video_stream_player.stream = Global.load_safely(Global.current_chart.get_video_background())
	if Global.settingsData.video_bg:
		if Global.current_chart.get_video_background() == "":
			video_bg_visible = false
			%video_bg.visible = false
		else:
			video_bg_visible = true
	else:
		video_bg_visible = false
	note_manager.bake(Global.current_chart)
	note_manager.reposition()
	BgMusic.load_song(Global.load_safely(Global.current_chart.song_path()))
	DiscordRPC.set_activity(
		"Drawing Shape",
		Global.current_chart.get_song_title() + " - " + Global.current_chart.get_song_source()
	)


func _on_animator_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Intro":
		# Auto preroll so the first note spawns exactly at the spawner.
		# Notes scroll during the silence; input stays blocked until music plays.
		target_shape.clear_points()
		draw_manager.start()
		BgMusic.connect("finished", _on_bg_music_finished)
		accuracy_manager.reset()
		accuracy_manager.get_od()
		var hb := get_node_or_null("UI/health_bar")
		if hb != null and hb.has_method("reset_health"):
			hb.reset_health()
		note_manager._start()
		var preroll: float = note_manager.calc_preroll()
		await get_tree().create_timer(preroll).timeout
		if not is_inside_tree():
			return
		BgMusic.start()
		GlobalBackground.set_base_alpha(Global.settingsData.bg_visibilty * 0.01)
		if video_bg_visible == true:
			_fade_in_video_bg(0.7)
			video_stream_player.play()
	elif anim_name == "Outro":
		# Failed during the outro: the game-over menu already owns the screen.
		var go := %"Game Over"
		if go == null or not go.visible:
			%WinScreen._show(%accuracy_manager._get_counts(), %accuracy_manager.avg_accuracy)


func _fade_in_video_bg(duration: float) -> void:
	var bg: CanvasItem = %video_bg
	bg.visible = true
	bg.modulate.a = 0.0
	if _video_fade_tween != null and _video_fade_tween.is_valid():
		_video_fade_tween.kill()
	_video_fade_tween = bg.create_tween()
	(
		_video_fade_tween
		. tween_property(bg, "modulate:a", 1.0, duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


func _on_bg_music_finished():
	draw_manager.stop()
	animator.play("Outro")
	pass


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(
		load("res://assets/sprites/UI/crosshair.png"), Input.CURSOR_ARROW, Vector2(21, 21)
	)
	BgMusic.enable_loop()
	GlobalBackground.enable_parallax()
