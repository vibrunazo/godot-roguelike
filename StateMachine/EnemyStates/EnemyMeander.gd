class_name EnemyMeander
extends EnemyState


func enter(_previous_state_path: String, _data := {}) -> void:
	enemy.animation_tree.change_immediate("WalkSpace")
	enemy.animation_tree.blend_target = 1.0
	var target: Vector3 = NavigationServer3D.map_get_random_point(
		enemy.get_world_3d().navigation_map,
		1,
		true
	)
	enemy.navigation_agent_3d.target_position = target


func physics_update(_delta: float) -> void:
	var destination: Vector3 = enemy.navigation_agent_3d.get_next_path_position()
	var local_direction: Vector3 = destination - enemy.global_position
	var direction: Vector3 = local_direction.normalized()
	core_movement(4.0, direction)
	look_at_target(destination)
	enemy.move_and_slide()
