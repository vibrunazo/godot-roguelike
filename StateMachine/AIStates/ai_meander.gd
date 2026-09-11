## AI state where the mind randomly wanders between points on the navigation mesh.
class_name AIMeander
extends AIState

## State to transition to when target is in attack range or navigation target is reached.
@export var attack_state: AIState
## Distance to target in meters at which the AI will transition to attacking.
@export var attack_range: float = 4.0
## State to transition to upon reaching the patrol point (fallback if attack_state is null).
@export var wait_state: AIState
## Optional state to transition to when an enemy target is detected within range.
@export var pursue_state: AIState
## Optional detection radius to trigger pursuit of targets (0.0 to disable).
@export var detection_range: float = 0.0


func enter(_previous_state_path: String, _data := {}) -> void:
	if character == null or not character.is_inside_tree() or character.navigation_agent_3d == null:
		return
	var random_point: Vector3 = NavigationServer3D.map_get_random_point(
		character.get_world_3d().navigation_map,
		1,
		true
	)
	character.navigation_agent_3d.target_position = random_point


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree() or ai_state_machine == null or not character.is_alive():
		return

	var target: Character = ai_state_machine.get_target()

	# Check for optional pursuit trigger
	if pursue_state != null and detection_range > 0.0 and target != null:
		var dist_sq: float = character.global_position.distance_squared_to(target.global_position)
		if dist_sq <= (detection_range * detection_range):
			finished.emit(pursue_state.name)
			return

	var nav_agent: NavigationAgent3D = character.navigation_agent_3d
	if nav_agent == null:
		return

	# Check if target is within attack range
	var in_range: bool = false
	if target != null:
		var dist_sq: float = character.global_position.distance_squared_to(target.global_position)
		in_range = dist_sq <= (attack_range * attack_range)

	var can_attack: bool = false
	if attack_state != null:
		if attack_state is AIAttack:
			can_attack = not (attack_state as AIAttack).is_on_cooldown()
		else:
			can_attack = true

	# Transition to attack or wait if destination is reached or target is in range
	if in_range and can_attack:
		ai_state_machine.command_stop()
		if target != null and character != null:
			character.look_at_target(target.global_position)
		finished.emit(attack_state.name)
		return

	if nav_agent.is_target_reached():
		ai_state_machine.command_stop()
		if target != null and character != null:
			character.look_at_target(target.global_position)
		if in_range and can_attack:
			finished.emit(attack_state.name)
			return
		elif wait_state != null:
			finished.emit(wait_state.name)
			return

	var destination: Vector3 = nav_agent.get_next_path_position()
	var local_direction: Vector3 = destination - character.global_position
	local_direction.y = 0.0
	ai_state_machine.command_move(local_direction.normalized(), destination)
