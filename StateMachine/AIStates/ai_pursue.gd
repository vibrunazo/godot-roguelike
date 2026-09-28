## AI state where the mind actively navigates toward an opposing target and orders body attacks.
class_name AIPursue
extends AIState

## The body attack state (on the body StateMachine) this state orders when in
## range.
@export var body_state: CharacterState
## Attack range threshold in meters.
@export var attack_range: float = 3.0
## AI state to transition to if the target is lost or defeated.
@export var lost_target_state: AIState
## Cooldown time in seconds between attack executions (0.0 = attack whenever ready).
@export var attack_cooldown: float = 0.0
## Whether this attack can be ordered even while the body is in its stun state
## (Character.stun_state).
@export var can_break_stun: bool = false
## Total facing cone in degrees toward the target required before ordering the
## attack (90.0 = within 45 degrees either side). 360.0 orders regardless of
## facing; 0.0 waits for perfect alignment. While outside the cone the mind
## keeps turning the body toward the target at its rotation speed limit and
## only orders once inside it, so attacks never start while facing away.
@export var desired_angle: float = 90.0

## Remaining cooldown time in seconds before this state can order an attack again.
var cooldown_timer: float = 0.0


func _ready() -> void:
	super._ready()
	if body_state == null:
		push_error("%s: body_state is not set." % name)


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

	if character.global_position.distance_squared_to(target.global_position) < attack_range * attack_range:
		_engage(target, delta)
		return
	nav_agent.target_position = target.global_position
	follow_nav_path(nav_agent)


## In attack range: stop, turn toward the target unless mid-swing (an attack
## commits to its starting facing), and order the attack once the body faces
## the target and the cooldown allows. Failed orders (stunned body) simply
## retry next tick, since pursue stays in this branch.
func _engage(target: Character, delta: float) -> void:
	ai_state_machine.command_stop()
	var is_attacking: bool = character.state_machine != null and character.state_machine.state == body_state
	if not is_attacking:
		character.look_at_target(target.global_position, delta)
	if cooldown_timer <= 0.0 and is_facing_within_cone(target, desired_angle):
		if ai_state_machine.order_attack(body_state, can_break_stun, build_aim_order_data(target)):
			cooldown_timer = attack_cooldown
