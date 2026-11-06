extends Control
class_name gameplay_manager

@export var CHART_PATH := "res://levels/Wasurete Yaranai by kessoku band mapped by ENSO Team/chart.enso"

var video_bg_visible = false

var _video_fade_tween: Tween = null

@onready var draw_manager: Line2D = %draw
@onready var note_manager: VBoxContainer = %note_column
@onready var target_shape: Line2D = $target_shape
@onready var animator: AnimationPlayer = %animator
@onready var video_stream_player = %VideoStreamPlayer
@onready var accuracy_manager := %accuracy_manager
@onready var bg: CanvasItem = %video_bg
@onready var video_bg = %video_bg
@onready var win_screen = %WinScreen
@onready var health_bar := get_node_or_null("UI/health_bar")
@onready var game_over := %"Game Over"


func _ready() -> void:
	_configure_environment()
	_load_gameplay_chart()
	_setup_video_background()
	_initialize_note_engine()


func _on_animator_animation_finished(anim_name: StringName) -> void:
	match anim_name:
		"Intro":
			_start_gameplay_sequence()
		"Outro":
			_handle_outro_sequence()


func _configure_environment() -> void:
	video_bg.modulate = Color(1.0, 1.0, 1.0, Global.settingsData.bg_visibilty * 0.01)
	GlobalBackground.disable_parallax()

	BgMusic.change_song(null)
	BgMusic._disable_loop()

	Input.set_custom_mouse_cursor(SkinManager.cursor_sprite, Input.CURSOR_ARROW, Vector2(12, 12))
	animator.play("Intro")


func _load_gameplay_chart() -> void:
	if Global.current_chart == null:
		Global.current_chart = LevelLoader.load_chart(CHART_PATH)

	var video_path: String = Global.current_chart.get_video_background()
	if not video_path.is_empty():
		video_stream_player.stream = Global.load_safely(video_path)


func _setup_video_background() -> void:
	var has_video: bool = not Global.current_chart.get_video_background().is_empty()

	if Global.settingsData.video_bg and has_video:
		video_bg_visible = true
	else:
		video_bg_visible = false
		video_bg.visible = false


func _initialize_note_engine() -> void:
	note_manager.bake(Global.current_chart)
	note_manager.reposition()

	BgMusic.load_song(Global.load_safely(Global.current_chart.song_path()))

	var rpc_details := "%s - %s" % [
		Global.current_chart.get_song_title(),
		Global.current_chart.get_song_source(),
	]
	DiscordRPC.set_activity("Drawing Shape", rpc_details)


func _start_gameplay_sequence() -> void:
	target_shape.clear_points()
	draw_manager.start()

	BgMusic.connect("finished", _on_bg_music_finished)
	accuracy_manager.reset()
	accuracy_manager.get_od()
	Global.call_if_exists(health_bar, "reset_health")
	note_manager._start()

	var preroll: float = note_manager.calc_preroll()
	await get_tree().create_timer(preroll).timeout
	if not is_inside_tree():
		return

	BgMusic.start()
	GlobalBackground.set_base_alpha(Global.settingsData.bg_visibilty * 0.01)

	if video_bg_visible:
		_fade_in_video_bg(0.7)
		video_stream_player.play()


func _handle_outro_sequence() -> void:
	var is_game_over_visible: bool = game_over and game_over.visible

	if not is_game_over_visible:
		win_screen.show_win_screen(
			accuracy_manager.get_counts(), accuracy_manager.avg_accuracy, accuracy_manager.max_combo
		)


func _fade_in_video_bg(duration: float) -> void:
	bg.visible = true
	bg.modulate.a = 0.0
	if _video_fade_tween != null and _video_fade_tween.is_valid():
		_video_fade_tween.kill()
	_video_fade_tween = bg.create_tween()
	(
		_video_fade_tween
		.tween_property(bg, "modulate:a", 1.0, duration)
		.set_trans(Tween.TRANS_QUAD)
		.set_ease(Tween.EASE_OUT)
	)


func _on_bg_music_finished():
	draw_manager.stop()
	animator.play("Outro")
	pass


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(
		load("res://assets/textures/ui/crosshair.png"),
		Input.CURSOR_ARROW,
		Vector2(21, 21),
	)
	BgMusic.enable_loop()
	GlobalBackground.enable_parallax()
