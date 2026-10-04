## AI state that fights from a distance: the mind keeps the body about
## preferred_range from its target, backing away (still facing it, so a
## shield stays toward the foe) when the target comes closer than that minus
## range_tolerance, walking up when it is farther than that plus it, and
## standing facing it in between. It never attacks itself: conditional attack
## states (AIConditionalAttack) interrupt it when their range opens (a bash
## up close, a charge from afar). Losing the target moves it to
## lost_target_state.
class_name AIKeepDistance
extends AIState

## Distance in meters the body tries to hold from its target.
@export var preferred_range: float = 7.0
## Half-width in meters of the band around preferred_range in which the body
## stands still.
@export var range_tolerance: float = 1.0
## How far behind itself the body plans each step back, as a navigation
## target, so walls and pits are respected while retreating.
@export var retreat_step: float = 3.0
## AI state to move to when the target is lost or defeated.
@export var lost_target_state: AIState


func physics_update(delta: float) -> void:
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
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance < preferred_range - range_tolerance:
		var away: Vector3 = -to_target.normalized() if distance > 0.001 else -_facing()
		nav_agent.target_position = character.global_position + away * retreat_step
		_step(nav_agent, target)
	elif distance > preferred_range + range_tolerance:
		nav_agent.target_position = target.global_position
		_step(nav_agent, target)
	else:
		ai_state_machine.command_stop()
		character.look_at_target(target.global_position, delta)


## One step along the navigation path, facing the target rather than the way
## the body walks.
func _step(nav_agent: NavigationAgent3D, target: Character) -> void:
	var destination: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = destination - character.global_position
	direction.y = 0.0
	ai_state_machine.command_move(direction.normalized(), target.global_position)


## The body's horizontal facing.
func _facing() -> Vector3:
	if character.mesh_mount == null:
		return Vector3.BACK
	var front: Vector3 = character.mesh_mount.global_basis.z
	front.y = 0.0
	return front.normalized() if not front.is_zero_approx() else Vector3.BACK
