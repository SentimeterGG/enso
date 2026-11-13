extends Control

const DEFAULT_PANEL_POSITION := Vector2(0, -60)

var _showing: bool = false

@onready var _label: Label = %Label
@onready var _panel: PanelContainer = %PanelContainer
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
var _default_panel_position: Vector2


func _ready() -> void:
	_default_panel_position = _panel.position
	_label.resized.connect(_sync_panel_size)


func _sync_panel_size() -> void:
	_panel.size = _label.get_minimum_size()


func show_tooltip(text: String) -> void:
	visible = true
	_animation_player.stop()
	_panel.position = _default_panel_position
	_label.text = text
	_showing = true
	_follow_mouse()
	_animation_player.play("spawn_animation")


func hide_tooltip() -> void:
	_showing = false
	_animation_player.play("dismis_animation")


func _process(_delta: float) -> void:
	if _showing:
		_follow_mouse()


func _follow_mouse() -> void:
	global_position = get_global_mouse_position()


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "dismis_animation":
		visible = false
