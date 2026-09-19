extends AnimatedSprite2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

enum HitAccuracy {
	PERFECT,
	OKAY,
	BAD,
	MISS
}

func _ready() -> void:
	play("idle")

func note_hit(accuracy: HitAccuracy):
	animation_player.stop()
	animation_player.play("on_hit_anim")
	if accuracy == HitAccuracy.PERFECT:
		stop()
		play("perfect")
	elif accuracy == HitAccuracy.OKAY:
		stop()
		play("ok")
	elif accuracy == HitAccuracy.BAD:
		stop()
		play("bad")
	elif accuracy == HitAccuracy.MISS:
		stop()
		play("miss")
	frame = randi_range(1, 4)


func _on_animation_finished() -> void:
	play("idle")
