class_name HealthBar
extends Node3D

## AttributeComponent driving this health bar (health pool + max_health stat).
@export var attribute_component: AttributeComponent
## Tint color applied to the front progress bar.
@export var health_color: Color
## Seconds the back (lagging) bar takes to catch up after damage.
@export var damage_lag_duration: float = 0.2
## Seconds the bar takes to fade out after its owner is defeated.
@export var fade_out_duration: float = 0.2

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

var health_tween: Tween

## Refreshes the bar from the attribute health pool when the pool or its max
## stat changes.
func _on_attribute_changed(attribute_name: StringName, _value: float) -> void:
	if attribute_component == null or not is_instance_valid(attribute_component):
		return
	if attribute_name == AttributeComponent.POOL_HEALTH or attribute_name == AttributeComponent.STAT_MAX_HEALTH:
		update_health_value(attribute_component.get_current(AttributeComponent.POOL_HEALTH))

## Current health as a percentage of max health (100.0 when unknown).
func _health_percentage() -> float:
	if attribute_component == null or not is_instance_valid(attribute_component):
		return 100.0
	var max_health: float = attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
	if max_health <= 0.0:
		return 100.0
	return attribute_component.get_current(AttributeComponent.POOL_HEALTH) / max_health * 100.0


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

func defeat() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(sprite_3d, "transparency", 1.0, fade_out_duration).from(0.0)
	tween.tween_callback(queue_free)
