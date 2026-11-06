extends CanvasLayer

enum GoTo {
	NONE,
	PLAY,
	SETTINGS,
	EDITOR,
}

const PULSE_STRENGTH := 0.05
const PULSE_FALLOFF := 0.25

var go_to: GoTo = GoTo.NONE
var app_version = ProjectSettings.get_setting("application/config/version", "1.0.0")
var mouse_hovered: bool = false
var bg_current: String
var bg_main_menu: Array[String] = [
	"res://assets/textures/backgrounds/bg2.png",
	"res://assets/textures/backgrounds/ShapesBG.png",
]

var _pulse_tween: Tween = null
var _current_bpm: float
var _last_beat: int = -1
var _current_bpm_start: float

@onready var draw_manager: Line2D = %draw
@onready var draw_here_label = %"Draw Here"
@onready var title = %Title
@onready var version_label = %Version
@onready var updater = %updater
@onready var transition = %Transition


func _ready() -> void:
	randomize()
	DiscordRPC.set_activity("in Main Menu", "Chilling...")
	_set_bg()
	_set_version_label()
	VolumePopup.can_popup = true
	if Global.first_time_playing:
		_set_random_music()
		Global.first_time_playing = false
		transition.play("first_time_opening")
	else:
		transition.play("Opening")
	draw_manager.start()


func _set_version_label():
	version_label.text = "v" + app_version


func _set_random_music():
	while true:
		var chart = Global.choose_random_chart()
		if chart == null or chart.is_empty():
			Notification.show_toast(
				"failed to start music",
				"there's no chart available to pick",
				NotificationToast.Kind.WARN,
			)
			return

		var song_path := chart.song_path()
		if song_path.is_empty():
			continue

		_current_bpm = chart.get_bpm()
		_current_bpm_start = chart.beat_offset()
		BgMusic.change_song(Global.load_safely(song_path), chart.preview_start())
		return


func _set_bg():
	bg_current = bg_main_menu.pick_random()
	GlobalBackground.set_base_alpha(1.0)
	GlobalBackground.change(bg_current)
	GlobalBackground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	if BgMusic == null or not BgMusic.playing:
		return
	var beat_duration := 1.0 / _current_bpm
	var audio_time: float = BgMusic.get_playback_position() - _current_bpm_start
	if audio_time < 0.0:
		return
	var current_beat := int(audio_time / beat_duration)
	if current_beat != _last_beat and current_beat >= 0:
		_last_beat = current_beat
		if mouse_hovered:
			_emit_beat()


func _on_transition_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Opening":
		pass
	elif anim_name == "Out":
		match go_to:
			GoTo.PLAY:
				get_tree().change_scene_to_file("res://scenes/menus/level_selector.tscn")
			GoTo.SETTINGS:
				get_tree().change_scene_to_file("res://scenes/ui/settings_tab.tscn")
			GoTo.EDITOR:
				get_tree().change_scene_to_file("res://scenes/menus/level_creator.tscn")
			_:
				pass
	elif anim_name == "Exit Game":
		get_tree().quit()


func _on_draw_guessed_shape(shape: String) -> void:
	match shape:
		"circle":
			go_to = GoTo.PLAY
			GlobalBackground.change(null)
			%Transition.play("Out")
		"line":
			go_to = GoTo.SETTINGS
			GlobalBackground.change(null)
			%Transition.play("Out")
		"square":
			go_to = GoTo.EDITOR
			GlobalBackground.change(null)
			%Transition.play("Out")
		"exit":
			%Transition.play("Exit Game")
			BgMusic.FADE_DURATION = 1.6
			BgMusic.change_song(null)


func _emit_beat() -> void:
	if draw_here_label == null or title == null:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var target_scale := 1.0 + PULSE_STRENGTH
	var tween := create_tween()
	tween.set_parallel(true)
	(
		tween
		.tween_property(draw_here_label, "offset_transform_scale", Vector2(
			target_scale,
			target_scale,
		), PULSE_FALLOFF * 0.2)
		.set_ease(Tween.EASE_OUT)
	)
	(
		tween
		.tween_property(draw_here_label, "offset_transform_scale", Vector2.ONE, PULSE_FALLOFF)
		.set_delay(PULSE_FALLOFF * 0.2)
		.set_ease(Tween.EASE_OUT)
	)
	_pulse_tween = tween


func _on_draw_here_mouse_entered() -> void:
	mouse_hovered = true


func _on_draw_here_mouse_exited() -> void:
	mouse_hovered = false
