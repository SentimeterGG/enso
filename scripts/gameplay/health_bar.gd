extends ProgressBar

signal health_changed(health: float)
signal health_depleted

@export_group("Base Amounts")
@export_range(0.0, 0.2, 0.001) var perfect_heal: float = 0.05
@export_range(0.0, 0.2, 0.001) var ok_heal: float = 0.025
@export_range(0.0, 0.2, 0.001) var bad_heal: float = 0.005
@export_range(0.0, 0.5, 0.005) var miss_damage: float = 0.05

@export_group("OD Scaling")
@export_range(0.0, 0.3, 0.01) var damage_od_step: float = 0.12
@export_range(0.0, 0.3, 0.01) var heal_od_step: float = 0.10
@export_range(0.0, 1.0, 0.05) var min_scale: float = 0.2

@export_group("Display")
@export_range(0.5, 20.0, 0.5) var smooth_speed: float = 8.0

var health := 1.0

var _display := 1.0
var _od := 5.0
var _dead := false


func _ready() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 0.001
	_setup_styles()
	_od = GestureRecognizer.od_from_chart(Global.current_chart)
	var score := get_node_or_null("%accuracy_manager")
	if score != null and score.has_signal("hit_applied"):
		score.connect("hit_applied", _on_hit_applied)
	_display = health
	_update_bar()


func _process(delta: float) -> void:
	if is_equal_approx(_display, health):
		return
	_display = lerpf(_display, health, clampf(smooth_speed * delta, 0.0, 1.0))
	if absf(_display - health) < 0.0005:
		_display = health
	_update_bar()


func reset_health() -> void:
	_od = GestureRecognizer.od_from_chart(Global.current_chart)
	health = 1.0
	_display = 1.0
	_dead = false
	_update_bar()
	health_changed.emit(health)


func apply_hit(kind: int) -> void:
	match kind:
		HitResult.Kind.PERFECT:
			_heal(perfect_heal)
		HitResult.Kind.OK:
			_heal(ok_heal)
		HitResult.Kind.BAD:
			_heal(bad_heal)
		HitResult.Kind.MISS:
			_damage(miss_damage)
		HitResult.Kind.BAD_DRAW:
			_damage(miss_damage)


func damage_scale() -> float:
	return maxf(min_scale, 1.0 + (_od - 5.0) * damage_od_step)


func heal_scale() -> float:
	return maxf(min_scale, 1.0 - (_od - 5.0) * heal_od_step)


func _heal(amount: float) -> void:
	_set_health(health + amount * heal_scale())


func _damage(amount: float) -> void:
	_set_health(health - amount * damage_scale())


func _set_health(health_value: float) -> void:
	health = clampf(health_value, 0.0, 1.0)
	_update_bar()
	health_changed.emit(health)
	if health <= 0.0 and not _dead:
		_dead = true
		health_depleted.emit()


func _on_hit_applied(kind: int) -> void:
	apply_hit(kind)


func _update_bar() -> void:
	value = clampf(_display, 0.0, 1.0)


func _setup_styles() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.20152658, 0.20152658, 0.20152658, 1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0, 0, 1)
	add_theme_stylebox_override("background", bg)
	add_theme_stylebox_override("fill", fill)
