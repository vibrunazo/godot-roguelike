class_name EnemyPursue
extends EnemyState

@export var attack_state: EnemyState
@export var attack_range: float = 3.0


func enter(_previous_state_path: String, _data := {}) -> void:
	enemy.animation_tree.change_immediate("WalkSpace")
	enemy.animation_tree.blend_target = 1.0


func physics_update(_delta: float) -> void:
	if not enemy or not is_instance_valid(enemy.player):
		return
	enemy.navigation_agent_3d.target_position = enemy.player.global_position
	var destination: Vector3 = enemy.navigation_agent_3d.get_next_path_position()
	var local_direction: Vector3 = destination - enemy.global_position
	local_direction.y = 0.0
	var direction: Vector3 = local_direction.normalized()
	look_at_target(destination)
	if enemy.distance_to_player() < attack_range:
		if attack_state:
			finished.emit(attack_state.name)
		return
	core_movement(enemy.base_speed, direction)
	if not enemy.is_on_floor():
		enemy.velocity += enemy.get_gravity() * _delta
	else:
		enemy.velocity.y = 0.0
	enemy.move_and_slide()

