extends TextureRect

var hit_time: float = 0.0
var beat_id: String = ""

var _judged := false
var _pending_free := false
var _home := Vector2.ZERO

@onready var hitsound: AudioStreamPlayer = $HitSound
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var outline: TextureRect = $CircleOutline


func _ready() -> void:
	texture = SkinManager.beat_point_bg
	outline.texture = SkinManager.beat_point_outline
	_home = position
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_judged() -> bool:
	return _judged


func is_awaiting_free() -> bool:
	return _pending_free


func is_offscreen() -> bool:
	# check if the beat_note is going offscreen to the left
	if not is_inside_tree():
		return true
	var position_x := global_position.x
	return position_x < -100.0


func miss() -> void:
	if _judged:
		return
	_judged = true
	_pending_free = true


func hit() -> void:
	if _judged:
		return
	_judged = true
	animation_player.play("jump")
	hitsound.play()


func vibrate() -> void:
	if _judged:
		return
	animation_player.play("vibrate")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "jump":
		call_deferred("queue_free")
