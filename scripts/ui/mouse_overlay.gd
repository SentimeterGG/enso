# mouse_overlay.gd — Custom cursor follower: a Sprite2D that snaps to the global
# mouse position every physics frame, used as a mouse overlay/cursor visual.
# RETURN: cursor sprite tracking the mouse every frame
extends Sprite2D


func _physics_process(_delta: float) -> void:
	global_position = get_global_mouse_position()
