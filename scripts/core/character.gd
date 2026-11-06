extends AnimatedSprite2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	play("idle")


func note_hit(accuracy: int) -> void:
	animation_player.stop()
	animation_player.play("on_hit_anim")
	match accuracy:
		HitResult.Kind.PERFECT:
			stop()
			play("perfect")
		HitResult.Kind.OK:
			stop()
			play("ok")
		HitResult.Kind.BAD:
			stop()
			play("bad")
		HitResult.Kind.MISS:
			stop()
			play("miss")
		_:
			stop()
			play("miss")
	frame = randi_range(1, 4)


func _on_animation_finished() -> void:
	play("idle")
