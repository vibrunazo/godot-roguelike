## AI state where the mind actively navigates toward an opposing target and orders body attacks.
class_name AIPursue
extends AIState

## The name of the physical attack state on the body StateMachine to execute when in range.
@export var attack_state_name: String = "EnemyAttack"
## Attack range threshold in meters.
@export var attack_range: float = 3.0
## AI state to transition to if the target is lost or defeated.
@export var lost_target_state: AIState
## Cooldown time in seconds between attack executions (0.0 = attack whenever ready).
@export var attack_cooldown: float = 0.0
## Whether this attack can be ordered even if the physical body is currently in EnemyStun.
@export var can_break_stun: bool = false
## Total facing cone in degrees toward the target required before ordering the
## attack (90.0 = within 45 degrees either side). 360.0 orders regardless of
## facing; 0.0 waits for perfect alignment. While outside the cone the mind
## keeps turning the body toward the target at its rotation speed limit and
## only orders once inside it, so attacks never start while facing away.
@export var desired_angle: float = 90.0

## Remaining cooldown time in seconds before this state can order an attack again.
var cooldown_timer: float = 0.0


## Updates the cooldown timer while this state is inactive so cooldown progresses.
func evaluate_trigger(delta: float) -> bool:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
	return false


func physics_update(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta

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
		# Only face the target when the body is not executing an attack. Once
		# the attack starts the enemy commits to its initial facing direction and
		# should not track the player mid-swing.
		var is_attacking: bool = (
			character.state_machine != null
			and character.state_machine.state != null
			and character.state_machine.state.name == attack_state_name
		)
		if not is_attacking:
			character.look_at_target(target.global_position, delta)
		# Order only inside the facing cone: the per-tick facing above turns
		# the body toward the target first, and the order carries the aim so
		# the body keeps converging during the swing. Failed orders (stunned
		# body) simply retry next tick since pursue never leaves this branch.
		if cooldown_timer <= 0.0 and is_facing_within_cone(target, desired_angle):
			if ai_state_machine.order_attack(attack_state_name, can_break_stun, build_aim_order_data(target)):
				cooldown_timer = attack_cooldown
		return

	nav_agent.target_position = target.global_position
	var destination: Vector3 = nav_agent.get_next_path_position()
	var local_destination: Vector3 = destination - character.global_position
	local_destination.y = 0.0
	ai_state_machine.command_move(local_destination.normalized(), destination)
