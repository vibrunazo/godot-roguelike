class_name HealthBar
extends Node3D

## Reference to the health component driving this health bar.
@export var health_component: HealthComponent
## Tint color applied to the front progress bar.
@export var health_color: Color

@onready var front_progress_bar: ProgressBar = $SubViewport/FrontProgressBar
@onready var health_progress_bar: ProgressBar = $SubViewport/HealthProgressBar

func _ready() -> void:
	if health_component != null:
		health_component.health_changed.connect(update_health_value)
	front_progress_bar.value = 100.0
	var fill_style: StyleBoxFlat = front_progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = health_color

func update_health_value(value_in: float) -> void:
	if health_component == null or health_component.max_health <= 0.0:
		return
	var tween: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	var target_health_percentage: float = (value_in / health_component.max_health) * 100.0
	tween.tween_property(health_progress_bar, "value", target_health_percentage, 0.2).from(front_progress_bar.value)
	front_progress_bar.value = target_health_percentage
