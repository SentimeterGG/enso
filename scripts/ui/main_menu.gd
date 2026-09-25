# main_menu.gd — Main menu controller: plays the logo idle + opening transition
# animations, enables free drawing after the intro, and goes to the level
# selector scene when a circle gesture is recognized.
# RETURN: route to the level selector when a circle is drawn
extends Control

enum GoTo { NONE, PLAY, SETTINGS, EDITOR }
const PULSE_STRENGTH := 0.05
const PULSE_FALLOFF := 0.25
@onready var draw_manager: Line2D = $draw
@onready var draw_here_label = $"Draw Here"
@onready var title = $RB/Title
@onready var version_label = $Version
@onready var updater = $updater
var go_to: GoTo = GoTo.NONE
var _pulse_tween: Tween = null
var _current_bpm: float
var _last_beat: int = -1
var _current_bpm_start: float
var app_version = ProjectSettings.get_setting("application/config/version", "1.0.0")


func _ready() -> void:
	version_label.text = app_version
	updater.check_update(app_version)
	randomize()
	VolumePopup.can_popup = true
	if Global.first_time_playing:
		var random_music = Global.choose_random_chart()
		# choose_random_chart() returns null when no charts are found (e.g.
		# custom .enso files missing from the exported package). Guard so a
		# missing chart skips the preview instead of crashing on Nil.
		if random_music != null and not random_music.is_empty():
			var song_path := random_music.song_path()
			# Feed the beat clock: without these _physics_process() bails at
			# the `<= 0.0` guard and the pulse tween never fires.
			_current_bpm = random_music.get_bpm()
			_current_bpm_start = random_music.beat_offset()
			if not song_path.is_empty():
				BgMusic.change_song(Global.load_safely(song_path), random_music.preview_start())
			else:
				push_warning("main_menu: random chart song missing: " + song_path)
		else:
			push_warning("main_menu: no charts available for random pick.")
		Global.first_time_playing = false
		$Transition.play("first_time_opening")
	else:
		$Transition.play("Opening")
	draw_manager.start()


func _physics_process(_delta: float) -> void:
	# Guard Rail
	if _current_bpm <= 0.0 or draw_here_label == null or title == null:
		return
	if BgMusic == null or not BgMusic.playing:
		return
	var beat_duration := 1.0 / _current_bpm
	var audio_time: float = BgMusic.get_playback_position() - _current_bpm_start
	if audio_time < 0.0:
		return
	var current_beat := int(audio_time / beat_duration)
	if current_beat != _last_beat and current_beat >= 0:
		_last_beat = current_beat
		_emit_beat()


func _on_transition_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Opening":
		pass
	elif anim_name == "Out":
		match go_to:
			GoTo.PLAY:
				get_tree().change_scene_to_file("res://scenes/level_selector.tscn")
			GoTo.SETTINGS:
				get_tree().change_scene_to_file("res://scenes/settings_tab.tscn")
			GoTo.EDITOR:
				get_tree().change_scene_to_file("res://scenes/level_creator.tscn")
			_:
				pass
	elif anim_name == "Exit Game":
		get_tree().quit()


func _on_draw_guessed_shape(shape: String) -> void:
	match shape:
		"circle":
			go_to = GoTo.PLAY
			$Transition.play("Out")
		"line":
			go_to = GoTo.SETTINGS
			$Transition.play("Out")
		"square":
			go_to = GoTo.EDITOR
			$Transition.play("Out")
		"exit":
			$Transition.play("Exit Game")
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
		. tween_property(
			draw_here_label,
			"offset_transform_scale",
			Vector2(target_scale, target_scale),
			PULSE_FALLOFF * 0.2
		)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(draw_here_label, "offset_transform_scale", Vector2.ONE, PULSE_FALLOFF)
		. set_delay(PULSE_FALLOFF * 0.2)
		. set_ease(Tween.EASE_OUT)
	)
	_pulse_tween = tween
