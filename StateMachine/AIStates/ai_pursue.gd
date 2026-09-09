## AI state where the mind actively navigates toward an opposing target and orders body attacks.
class_name AIPursue
extends AIState

## The name of the physical attack state on the body StateMachine to execute when in range.
@export var attack_state_name: String = "EnemyAttack"
## Attack range threshold in meters.
@export var attack_range: float = 3.0
## AI state to transition to if the target is lost or defeated.
@export var lost_target_state: AIState


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree() or ai_state_machine == null or not character.is_alive():
		return

	var target: Character = ai_state_machine.get_target()
	if target == null:
		ai_state_machine.command_stop()
		if lost_target_state != null:
			finished.emit(lost_target_state.name)
		return

	var nav_agent: NavigationAgent3D = character.navigation_agent_3d
	if nav_agent == null:
		return

	var dist_sq: float = character.global_position.distance_squared_to(target.global_position)
	if dist_sq < (attack_range * attack_range):
		ai_state_machine.command_stop()
		character.look_at_target(target.global_position)
		ai_state_machine.order_attack(attack_state_name)
		return

	nav_agent.target_position = target.global_position
	var destination: Vector3 = nav_agent.get_next_path_position()
	var local_destination: Vector3 = destination - character.global_position
	local_destination.y = 0.0
	ai_state_machine.command_move(local_destination.normalized(), destination)
