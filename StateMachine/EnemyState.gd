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


func look_at_player() -> void:
	if is_instance_valid(enemy) and is_instance_valid(enemy.player):
		look_at_target(enemy.player.global_position)


func look_at_target(target: Vector3) -> void:
	if not is_instance_valid(enemy) or not is_instance_valid(enemy.mesh_mount):
		return
	target.y = enemy.mesh_mount.global_position.y
	if enemy.mesh_mount.global_position.is_equal_approx(target):
		return
	enemy.mesh_mount.look_at(target, Vector3.UP, true)
