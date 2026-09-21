# health_bar.gd — Gameplay HP bar (node: UI/HealthBar): beat judgements move
# health, drawn as the width of the $Filled child. PERFECT/OK/BAD heal while
# MISS damages, scaled by chart OD (high OD = more damage/less heal, low OD
# = less damage/more heal, OD 5 neutral). Fed per-hit via
# ScoreManager.hit_applied; game.gd calls reset_health() on run start.
# RETURN: health 0..1 fraction plus health_changed / health_depleted signals
extends ColorRect

signal health_changed(health: float)
signal health_depleted

@export_group("Base Amounts")
@export_range(0.0, 0.2, 0.001) var perfect_heal: float = 0.015
@export_range(0.0, 0.2, 0.001) var ok_heal: float = 0.008
@export_range(0.0, 0.2, 0.001) var bad_heal: float = 0.003
@export_range(0.0, 0.5, 0.005) var miss_damage: float = 0.06

@export_group("OD Scaling")
## Extra damage multiplier per OD step above 5 (OD 10 ~= 1.6x by default).
@export_range(0.0, 0.3, 0.01) var damage_od_step: float = 0.12
## Lost heal multiplier per OD step above 5 (OD 10 ~= 0.5x by default).
@export_range(0.0, 0.3, 0.01) var heal_od_step: float = 0.10
## Floor for both scales so extreme ODs never zero out or invert.
@export_range(0.0, 1.0, 0.05) var min_scale: float = 0.2

@export_group("Display")
## Bar fill follows real health at this lerp rate (higher = snappier).
@export_range(0.5, 20.0, 0.5) var smooth_speed: float = 8.0

## Current health as a 0..1 fraction. 1.0 = full, 0.0 = depleted.
var health := 1.0

var _display := 1.0
var _od := 5.0
var _dead := false

@onready var filled: ColorRect = $Filled


func _ready() -> void:
	_od = GestureRecognizer.od_from_chart(Global.current_chart)
	var score := get_node_or_null("%accuracy_manager")
	if score != null and score.has_signal("hit_applied"):
		score.connect("hit_applied", _on_hit_applied)
	_display = health
	_update_bar()


func _process(delta: float) -> void:
	if filled == null:
		return
	if is_equal_approx(_display, health):
		return
	_display = lerpf(_display, health, clampf(smooth_speed * delta, 0.0, 1.0))
	if absf(_display - health) < 0.0005:
		_display = health
	_update_bar()


## Full HP, re-reads OD from the current chart. Called on run start.
func reset_health() -> void:
	_od = GestureRecognizer.od_from_chart(Global.current_chart)
	health = 1.0
	_display = 1.0
	_dead = false
	_update_bar()
	health_changed.emit(health)


## Applies one beat judgement. BAD_DRAW and unknown kinds are ignored.
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


func damage_scale() -> float:
	return maxf(min_scale, 1.0 + (_od - 5.0) * damage_od_step)


func heal_scale() -> float:
	return maxf(min_scale, 1.0 - (_od - 5.0) * heal_od_step)


func _heal(amount: float) -> void:
	_set_health(health + amount * heal_scale())


func _damage(amount: float) -> void:
	_set_health(health - amount * damage_scale())


func _set_health(value: float) -> void:
	health = clampf(value, 0.0, 1.0)
	_update_bar()
	health_changed.emit(health)
	if health <= 0.0 and not _dead:
		_dead = true
		health_depleted.emit()


func _on_hit_applied(kind: int) -> void:
	apply_hit(kind)


func _update_bar() -> void:
	if filled == null:
		return
	var full := size.x
	if full <= 0.0:
		full = 209.0
	filled.offset_right = filled.offset_left + full * _display
