# level_selector.gd — Level selector screen controller: plays the opening/closing
# animations (Out returns to main menu, or enters game.tscn after a triangle
# "play" gesture confirms the current selection via LevelLoader), leaves for
# main menu on a circle gesture, and only enables drawing while the mouse
# hovers the side panel. Enter/ui_accept also confirms the selection.
# RETURN: route to main menu or game scene; drawing gated to the side panel
extends Control

const GAME_SCENE_PATH := "res://scenes/game.tscn"
const PULSE_STRENGTH := 0.12
const PULSE_FALLOFF := 0.25

var _pending_game := false
var _preview_chart_path: String = ""
var _current_bpm: float = 0.0
var _current_offset: float = 0.0
var _last_beat: int = -1
var _pulse_tween: Tween = null
var _transitioning: bool = false
## Stream the beat clock is synced to. BgMusic.change_song() swaps the
## stream ~0.3s after hover (fade tween), so hover-time beat state goes stale
## on first launch. Re-arming on the real swap keeps beats working.
var _synced_stream: AudioStream = null
## Blocks preview song swaps until the initial auto-select runs. The list
## auto-hovers index 0 on reload, whose change_song() tween would otherwise
## fire ~0.3s later and override the real selection's song.
var _initial_select_done: bool = false
@onready var draw_here_label: Label = %"Draw Here"
@onready var beat_sound: AudioStreamPlayer = $"beat_sound"
@onready var draw_manager: Line2D = $draw
@onready var level_list: Control = $"Main Content/HBoxContainer/RSide/Level List"
@onready var _notification: Control = get_node_or_null("%Notification")


func _ready() -> void:
	$AnimationPlayer.play("Opening")
	call_deferred("_warn_skipped_incomplete")
	call_deferred("_select_current_bg_song")
	DiscordRPC.set_activity("Choosing A Map", "")


## Toast when level_list hid incomplete (solo-note) charts.
func _warn_skipped_incomplete() -> void:
	if level_list == null or not level_list.has_method("get_skipped_incomplete_count"):
		return
	var n := int(level_list.call("get_skipped_incomplete_count"))
	if n <= 0:
		return
	var msg := "%d incomplete level%s hidden (solo notes need setup)." % [n, "" if n == 1 else "s"]
	if _notification != null and _notification.has_method("show_message"):
		_notification.call("show_message", msg, false, 4.0)
	else:
		push_warning("level_selector: " + msg)


## Center/highlight the row matching what BgMusic is playing, so the
## song keeps playing (see same-song guard in _on_level_item_hovered)
## instead of restarting from index 0's preview.
func _select_current_bg_song() -> void:
	if level_list == null:
		return
	var levels: Array = level_list.get("levels")
	if levels.is_empty():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	levels = level_list.get("levels")
	if levels.is_empty():
		return
	var selected_index := int(level_list.get("selected_index"))
	var target := -1
	# 1) Live audio wins: match whatever BgMusic is actually playing.
	# Hovering a row only previews its song (Global.current_chart is left
	# alone until play), so after level_selector -> main_menu the stored
	# chart is stale while BgMusic still plays the last previewed song.
	if has_node("/root/BgMusic"):
		var bg := get_node("/root/BgMusic") as AudioStreamPlayer
		if bg != null and bg.stream != null and bg.playing:
			var cur := (bg.stream as AudioStream).resource_path.simplify_path()
			for i in levels.size():
				var cpath := str((levels[i] as Dictionary).get("chart_path", ""))
				if cpath.is_empty():
					continue
				var meta := ChartParser.parse_metadata(cpath)
				var song := str(meta.get("song", ""))
				if song.is_empty():
					continue
				if not (song.begins_with("res://") or song.begins_with("user://")):
					song = cpath.get_base_dir().path_join(song).simplify_path()
				if song == cur:
					target = i
					break
	# 2) Fallback: exact chart match (main_menu stores its random pick here).
	# Covers the fresh-boot race where change_song()'s fade tween hasn't
	# swapped BgMusic's stream yet, so the live-audio match above misses.
	if (
		target == -1
		and Global.current_chart != null
		and not Global.current_chart.chart_path.is_empty()
	):
		for i in levels.size():
			if (
				str((levels[i] as Dictionary).get("chart_path", ""))
				== Global.current_chart.chart_path
			):
				target = i
				break
	if target == selected_index:
		_initial_select_done = true
		# Already centered on it, but the index-0 hover was swallowed
		# above: force the hover now so bpm/beat/song sync.
		_preview_chart_path = ""
		_on_level_item_hovered(str((levels[target] as Dictionary).get("chart_path", "")))
		return
	if target < 0:
		# No match for the current song: fall back to previewing whatever
		# is selected (its initial hover was swallowed above).
		_initial_select_done = true
		_preview_chart_path = ""
		if selected_index >= 0 and selected_index < levels.size():
			_on_level_item_hovered(
				str((levels[selected_index] as Dictionary).get("chart_path", ""))
			)
		return
	_initial_select_done = true
	_preview_chart_path = ""
	if level_list.has_method("select"):
		level_list.call("select", target)


func play_selected() -> void:
	if level_list == null:
		push_warning("level_selector: level list not found.")
		return
	if has_node("/root/BgMusic"):
		var bg := get_node("/root/BgMusic") as AudioStreamPlayer
		if bg != null:
			bg.change_song()
	var chart := LevelLoader.load_selected(level_list)
	if chart.is_empty():
		push_warning("level_selector: selected chart failed to load, staying put.")
		return
	_pending_game = true
	$AnimationPlayer.play("Out")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Out":
		if _pending_game:
			get_tree().change_scene_to_file(GAME_SCENE_PATH)
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_draw_guessed_shape(shape: String) -> void:
	if shape == "circle":
		_pending_game = false
		$AnimationPlayer.play("Out")
	elif shape == "triangle":
		play_selected()


func _on_l_side_mouse_entered() -> void:
	draw_manager.start()


func _on_l_side_mouse_exited() -> void:
	draw_manager.stop()


func _physics_process(_delta: float) -> void:
	if _current_bpm <= 0.0 or draw_here_label == null:
		return
	if BgMusic == null or not BgMusic.playing:
		return
	var beat_duration := 1.0 / _current_bpm
	var audio_time := BgMusic.get_playback_position() - _current_offset
	if audio_time < 0.0:
		return
	var current_beat := int(audio_time / beat_duration)
	if BgMusic.stream != _synced_stream:
		# Song actually swapped (post-fade): re-arm from the live position.
		_synced_stream = BgMusic.stream
		_transitioning = true
		_last_beat = current_beat
		return
	if not _transitioning and current_beat < _last_beat:
		# Position jumped backward (seek/replay): re-arm the same way.
		_transitioning = true
		_last_beat = current_beat
		return
	if _transitioning:
		if current_beat > _last_beat:
			_last_beat = current_beat
			_transitioning = false
		else:
			return
	if current_beat != _last_beat and current_beat >= 0:
		_last_beat = current_beat
		_emit_beat()
		beat_sound.play()


func _emit_beat() -> void:
	if draw_here_label == null:
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


func _on_level_item_hovered(chart_path: String) -> void:
	if chart_path.is_empty() or chart_path == _preview_chart_path:
		return
	_preview_chart_path = chart_path
	if not has_node("/root/BgMusic"):
		return
	var bg := get_node("/root/BgMusic") as AudioStreamPlayer
	if bg == null or not bg.has_method("change_song"):
		return
	var chart := ChartParser.load(chart_path)
	if chart.is_empty():
		return
	_current_bpm = chart.get_bpm()
	_current_offset = chart.beat_offset()
	_transitioning = true
	var beat_duration := 1.0 / _current_bpm if _current_bpm > 0.0 else 0.5
	var preview := chart.preview_start()
	_last_beat = int(preview / beat_duration) - 1
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if draw_here_label != null:
		draw_here_label.offset_transform_scale = Vector2.ONE
	if not _initial_select_done:
		# Pre-selection hover (index 0 auto-hover on reload): sync the beat
		# visuals only, never queue a song swap that would stomp the real
		# selection ~0.3s later when its fade tween fires.
		_synced_stream = null
		return
	var song := chart.song_path()
	if song.is_empty() or not ResourceLoader.exists(song):
		return
	var stream := load(song) as AudioStream
	if stream == null:
		return
	if bg.playing and bg.stream != null:
		var cur_path := bg.stream.resource_path
		var new_path := stream.resource_path
		var same_song := bg.stream == stream or (not cur_path.is_empty() and cur_path == new_path)
		if same_song:
			# Same song already playing: don't reset it, just re-sync the beat clock
			# to the live playback position with the new chart's bpm/offset.
			_synced_stream = bg.stream
			_transitioning = false
			var audio_time := bg.get_playback_position() - _current_offset
			_last_beat = int(audio_time / beat_duration) if audio_time >= 0.0 else -1
			return
	bg.change_song(stream, chart.preview_start())
