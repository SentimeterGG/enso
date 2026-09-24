extends VBoxContainer

const SEPARATION_SHOWN := 6
const SEPARATION_HIDDEN := -40
const TWEEN_DURATION := 0.25

var _sep_tween: Tween = null


func _ready() -> void:
	add_theme_constant_override("separation", SEPARATION_SHOWN)


func _on_button_pressed() -> void:
	var current: int = get_theme_constant("separation")
	var target: int = SEPARATION_HIDDEN if current == SEPARATION_SHOWN else SEPARATION_SHOWN
	_animate_separation(target)


func set_expanded(expanded: bool) -> void:
	_animate_separation(SEPARATION_SHOWN if expanded else SEPARATION_HIDDEN)


func is_expanded() -> bool:
	return get_theme_constant("separation") == SEPARATION_SHOWN


## Theme constants aren't tweenable properties, so interpolate via
## tween_method and push each step as an override. Starts from the
## live value, so reversing mid-animation stays smooth.
func _animate_separation(target: int) -> void:
	if _sep_tween != null and _sep_tween.is_valid():
		_sep_tween.kill()
	var from: int = get_theme_constant("separation")
	if from == target:
		return
	_sep_tween = create_tween()
	(
		_sep_tween
		. tween_method(_apply_separation, float(from), float(target), TWEEN_DURATION)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)


func _apply_separation(value: float) -> void:
	add_theme_constant_override("separation", int(round(value)))
