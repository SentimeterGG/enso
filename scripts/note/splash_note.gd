extends Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	animation_player.play("splash")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "splash":
		call_deferred("queue_free")
	pass # Replace with function body.
