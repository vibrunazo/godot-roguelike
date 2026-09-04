class_name HealthBar
extends Node3D

## Reference to the health component driving this health bar.
@export var health_component: HealthComponent

@onready var front_progress_bar: ProgressBar = $SubViewport/FrontProgressBar

func _ready() -> void:
	if health_component != null:
		health_component.health_changed.connect(update_health_value)

func update_health_value(value_in: float) -> void:
	if health_component != null and health_component.max_health > 0.0:
		front_progress_bar.value = (value_in / health_component.max_health) * 100.0
