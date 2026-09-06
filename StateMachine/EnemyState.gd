class_name EnemyState
extends State

## Reference to the Enemy controlled by this state.
@export var enemy: Enemy


func core_movement(speed: float, direction: Vector3) -> void:
	if direction:
		enemy.velocity.x = direction.x * speed
		enemy.velocity.z = direction.z * speed
	else:
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, speed)
		enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, speed)
