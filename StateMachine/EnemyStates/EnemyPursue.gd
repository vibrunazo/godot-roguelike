class_name EnemyPursue
extends EnemyState

@export var attack_state: EnemyState
@export var attack_range: float = 3.0


func enter(_previous_state_path: String, _data := {}) -> void:
	enemy.animation_tree.change_immediate("WalkSpace")
	enemy.animation_tree.blend_target = 1.0


func physics_update(_delta: float) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree() or not is_instance_valid(enemy.player):
		return
	enemy.navigation_agent_3d.target_position = enemy.player.global_position
	var destination: Vector3 = enemy.navigation_agent_3d.get_next_path_position()
	var local_destination: Vector3 = destination - enemy.global_position
	local_destination.y = 0.0
	look_at_target(destination)
	if enemy.distance_to_player() < attack_range:
		if attack_state:
			finished.emit(attack_state.name)
		return
	core_movement(enemy.base_speed, local_destination.normalized())
	enemy.move_and_slide()

