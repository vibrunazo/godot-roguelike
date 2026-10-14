## Moves toward target_position at speed meters per second on the physics
## clock and emits arrived once, on the tick it gets there.
class_name Mover
extends Node3D

## Emitted once, on the tick the mover reaches its target.
signal arrived

## Meters per second.
@export var speed: float = 5.0
## Where the mover heads, in its parent's space.
@export var target_position: Vector3 = Vector3.ZERO

var _has_arrived: bool = false


func _physics_process(delta: float) -> void:
	if _has_arrived:
		return
	var to_target: Vector3 = target_position - position
	var step: float = speed * delta
	if to_target.length() <= step:
		position = target_position
		_has_arrived = true
		arrived.emit()
	else:
		position += to_target.normalized() * step
