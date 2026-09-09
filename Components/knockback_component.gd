extends Node
class_name KnockbackComponent

## Exponential decay rate for knockback momentum over time.
@export var decay: float = 8.0
## Maximum allowable knockback velocity vector magnitude.
@export var max_knockback: float = 50.0

var magnitude := Vector3.ZERO:
	set(value):
		magnitude = value.limit_length(max_knockback)


func _physics_process(delta: float) -> void:
	magnitude = magnitude.lerp(Vector3.ZERO, 1.0 - exp(-decay * delta))


func add_knockback(magnitude_in: Vector3) -> void:
	magnitude += magnitude_in


func is_active() -> bool:
	return magnitude.length() > 1.0
