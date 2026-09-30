## Floating health bar over a character or a prop, following an
## AttributeComponent's health pool. Always shown by default; with a
## show_duration it stays hidden and only pops up for that long after its
## owner's health changes (props such as destructible barrels).
class_name HealthBar
extends Node3D

## AttributeComponent driving this health bar (health pool + max_health stat).
@export var attribute_component: AttributeComponent
## Tint color applied to the front progress bar.
@export var health_color: Color
## Seconds the back (lagging) bar takes to catch up after damage.
@export var damage_lag_duration: float = 0.2
## Seconds the bar takes to fade out, after its owner is defeated or when a
## temporary bar's show_duration runs out.
@export var fade_out_duration: float = 0.2
## Seconds the bar stays up after health changes before fading out; it is
## hidden until then. 0: the bar is always shown.
@export var show_duration: float = 0.0

@onready var front_progress_bar: ProgressBar = $SubViewport/FrontProgressBar
@onready var health_progress_bar: ProgressBar = $SubViewport/HealthProgressBar
@onready var sprite_3d: Sprite3D = $Sprite3D

func _ready() -> void:
	if attribute_component != null:
		attribute_component.attribute_changed.connect(_on_attribute_changed)
		attribute_component.defeat.connect(defeat)
	# Start from the owner's actual health, not an assumed full bar.
	var start_percentage: float = _health_percentage()
	front_progress_bar.value = start_percentage
	health_progress_bar.value = start_percentage
	var fill_style: StyleBoxFlat = front_progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = health_color
	if show_duration > 0.0:
		visible = false

var health_tween: Tween
## Hold-then-fade of a temporary bar (show_duration > 0), restarted on every
## health change.
var _visibility_tween: Tween

## Refreshes the bar from the attribute health pool when the pool or its max
## stat changes.
func _on_attribute_changed(attribute_name: StringName, _value: float) -> void:
	if attribute_component == null or not is_instance_valid(attribute_component):
		return
	if attribute_name == AttributeComponent.POOL_HEALTH or attribute_name == AttributeComponent.STAT_MAX_HEALTH:
		update_health_value(attribute_component.get_current(AttributeComponent.POOL_HEALTH))
		_reveal()

## Shows a temporary bar and restarts its countdown: it holds for
## show_duration, then fades out over fade_out_duration and hides.
func _reveal() -> void:
	if show_duration <= 0.0:
		return
	if _visibility_tween and _visibility_tween.is_valid():
		_visibility_tween.kill()
	visible = true
	sprite_3d.transparency = 0.0
	_visibility_tween = create_tween()
	_visibility_tween.tween_interval(show_duration)
	_visibility_tween.tween_property(sprite_3d, "transparency", 1.0, fade_out_duration)
	_visibility_tween.tween_callback(hide)

## Current health as a percentage of max health (100.0 when unknown).
func _health_percentage() -> float:
	if attribute_component == null or not is_instance_valid(attribute_component):
		return 100.0
	var max_health: float = attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
	if max_health <= 0.0:
		return 100.0
	return attribute_component.get_current(AttributeComponent.POOL_HEALTH) / max_health * 100.0


## Moves the bars to value_in health: the front bar snaps, and the back bar
## lags behind on damage.
func update_health_value(value_in: float) -> void:
	if attribute_component == null or not is_instance_valid(attribute_component):
		return
	var max_health: float = attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
	if max_health <= 0.0:
		return
	if health_tween and health_tween.is_valid():
		health_tween.kill()
	var target_health_percentage: float = (value_in / max_health) * 100.0
	if target_health_percentage < front_progress_bar.value:
		health_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		health_tween.tween_property(health_progress_bar, "value", target_health_percentage, damage_lag_duration).from(front_progress_bar.value)
	else:
		health_progress_bar.value = target_health_percentage
	front_progress_bar.value = target_health_percentage

## Fades the bar out and frees it once its owner is defeated.
func defeat() -> void:
	if _visibility_tween and _visibility_tween.is_valid():
		_visibility_tween.kill()
	var tween: Tween = create_tween()
	tween.tween_property(sprite_3d, "transparency", 1.0, fade_out_duration).from(0.0)
	tween.tween_callback(queue_free)
