# volume_popup.gd — Popup volume control: hidden until scroll wheel,
# then shows with a pop-out tween, updates sliders & master bus volume.
# RETURN: visible popup that tracks scroll wheel for master volume
extends Control

const POP_DURATION := 0.25
const POP_SCALE_START := 0.9
const POP_SCALE_END := 1.0
const VOLUME_STEP := 5.0
const VOLUME_MIN := -60.0
const VOLUME_MAX := 0.0
const HIDE_DELAY := 2.0

@onready var music_slider: HSlider = $CenterContainer/VBoxContainer/VBoxContainer/HBoxContainer/Music
@onready var music_label: Label = $CenterContainer/VBoxContainer/VBoxContainer/HBoxContainer/Label
@onready var master_slider: HSlider = $CenterContainer/VBoxContainer/VBoxContainer2/HBoxContainer/Music
@onready var master_label: Label = $CenterContainer/VBoxContainer/VBoxContainer2/HBoxContainer/Label
@onready var effects_slider: HSlider = $CenterContainer/VBoxContainer/VBoxContainer3/HBoxContainer/Music
@onready var effects_label: Label = $CenterContainer/VBoxContainer/VBoxContainer3/HBoxContainer/Label

var _is_visible := false
var _pop_tween: Tween
var _hide_token := 0
var can_popup: bool = true

func _ready() -> void:
	visible = false
	modulate.a = 0.0
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_ignore_recursive(self)
	grab_volume_config()
	_set_scale(POP_SCALE_START)
	_connect_sliders()
	_sync_sliders_to_audio()


func _set_ignore_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is HSlider:
			continue # sliders must stay STOP to be draggable
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_ignore_recursive(child)

func grab_volume_config():
	_apply_bus_volume("Effect", Global.settingsData.effects_volume)
	_update_label(effects_slider, effects_label)
	_apply_bus_volume("Master", Global.settingsData.master_volume)
	_update_label(master_slider, master_label)
	_apply_bus_volume("Music", Global.settingsData.music_volume)
	_update_label(music_slider, music_label)

# Just pushes to AudioServer — no Global writes, no disk saves.
func _apply_bus_volume(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, _slider_to_db(value))



func save_volume():
	Global.settingsData.effects_volume = effects_slider.value
	Global.settingsData.master_volume = master_slider.value
	Global.settingsData.music_volume = music_slider.value
	Global.save(Global.settingsData, Global.settingsData.save_file_name)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and not _mouse_over_slider() and can_popup:
			_scroll_volume(VOLUME_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not _mouse_over_slider() and can_popup:
			_scroll_volume(-VOLUME_STEP)


func _scroll_volume(delta: float) -> void:
	_show_popup()
	_adjust_master_volume(delta)
	_restart_hide_timer()


func _show_popup() -> void:
	_sync_sliders_to_audio()
	if _is_visible:
		return
	_is_visible = true

	_kill_tween()
	pivot_offset = size / 2.0
	visible = true

	# Always start from the same state so the pop looks identical every time,
	# even if the hide tween was still running.
	modulate.a = 0.0
	_set_scale(POP_SCALE_START)

	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(self, "modulate:a", 1.0, POP_DURATION)
	(
		_pop_tween
		. tween_property(self, "scale", Vector2.ONE * POP_SCALE_END, POP_DURATION)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_BACK)
	)


func _hide_popup() -> void:
	if not _is_visible:
		return
	_is_visible = false

	_kill_tween()

	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(self, "modulate:a", 0.0, POP_DURATION)
	(
		_pop_tween
		. tween_property(self, "scale", Vector2.ONE * POP_SCALE_START, POP_DURATION)
		. set_ease(Tween.EASE_IN)
		. set_trans(Tween.TRANS_BACK)
	)
	_pop_tween.chain().tween_callback(_on_hide_finished)


func _on_hide_finished() -> void:
	visible = false
	modulate.a = 0.0
	_set_scale(POP_SCALE_START)


func _kill_tween() -> void:
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = null


func _restart_hide_timer() -> void:
	_hide_token += 1
	var token := _hide_token
	var timer := get_tree().create_timer(HIDE_DELAY)
	timer.timeout.connect(func() -> void:
		# Ignore timers superseded by a newer scroll.
		if token == _hide_token:
			_hide_popup()
	)


func _adjust_master_volume(delta: float) -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index == -1:
		return
	var current_db: float = AudioServer.get_bus_volume_db(bus_index)
	var new_db: float = clamp(current_db + delta, VOLUME_MIN, VOLUME_MAX)

	if new_db == current_db:
		return

	AudioServer.set_bus_volume_db(bus_index, new_db)
	master_slider.set_value_no_signal(_db_to_slider(new_db))
	_update_label(master_slider, master_label)
	%OsuHitSound.play()



func _connect_sliders() -> void:
	music_slider.value_changed.connect(_on_music_changed)
	master_slider.value_changed.connect(_on_master_changed)
	effects_slider.value_changed.connect(_on_effects_changed)


func _sync_sliders_to_audio() -> void:
	music_slider.set_value_no_signal(_get_bus_slider_value("Music"))
	master_slider.set_value_no_signal(_get_bus_slider_value("Master"))
	effects_slider.set_value_no_signal(_get_bus_slider_value("Effect"))
	_update_label(music_slider, music_label)
	_update_label(master_slider, master_label)
	_update_label(effects_slider, effects_label)


func _on_music_changed(value: float) -> void:
	_set_bus_volume("Music", value)
	_update_label(music_slider, music_label)
	_restart_hide_timer()
	%OsuHitSound.play()


func _on_master_changed(value: float) -> void:
	_set_bus_volume("Master", value)
	_update_label(master_slider, master_label)
	_restart_hide_timer()
	%OsuHitSound.play()


func _on_effects_changed(value: float) -> void:
	_set_bus_volume("Effect", value)
	_update_label(effects_slider, effects_label)
	_restart_hide_timer()
	%OsuHitSound.play()



func _set_bus_volume(bus_name: String, value: float) -> void:
	_apply_bus_volume(bus_name, value)
	save_volume()


func _get_bus_slider_value(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return _db_to_slider(AudioServer.get_bus_volume_db(idx))
	return 100.0



func _slider_to_db(val: float) -> float:
	return lerp(VOLUME_MIN, VOLUME_MAX, val / 100.0)


func _db_to_slider(db: float) -> float:
	return (db - VOLUME_MIN) / (VOLUME_MAX - VOLUME_MIN) * 100.0


func _update_label(slider: HSlider, label: Label) -> void:
	label.text = "%d%%" % roundi(slider.value)


func _set_scale(s: float) -> void:
	scale = Vector2.ONE * s

func _mouse_over_slider() -> bool:
	var mouse_pos := get_global_mouse_position()
	
	if music_slider.get_global_rect().has_point(mouse_pos):
		return true
	
	if master_slider.get_global_rect().has_point(mouse_pos):
		return true
	
	if effects_slider.get_global_rect().has_point(mouse_pos):
		return true
	
	return false
