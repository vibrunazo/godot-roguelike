class_name HealthBar
extends Node3D

## AttributeComponent driving this health bar (health pool + max_health stat).
@export var attribute_component: AttributeComponent
## Tint color applied to the front progress bar.
@export var health_color: Color

@onready var front_progress_bar: ProgressBar = $SubViewport/FrontProgressBar
@onready var health_progress_bar: ProgressBar = $SubViewport/HealthProgressBar
@onready var sprite_3d: Sprite3D = $Sprite3D

func _ready() -> void:
	if attribute_component != null:
		attribute_component.attribute_changed.connect(_on_attribute_changed)
		attribute_component.defeat.connect(defeat)
	front_progress_bar.value = 100.0
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
		health_tween.tween_property(health_progress_bar, "value", target_health_percentage, 0.2).from(front_progress_bar.value)
	else:
		health_progress_bar.value = target_health_percentage
	front_progress_bar.value = target_health_percentage

func defeat() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(sprite_3d, "transparency", 1.0, 0.2).from(0.0)
	tween.tween_callback(queue_free)
