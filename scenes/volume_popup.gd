extends CanvasLayer

@onready var volume_popup = $volume_popup
var test = false

var can_popup: bool = true:
	set = change_popup


func change_popup(pop_up_value: bool):
	volume_popup.can_popup = pop_up_value

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
