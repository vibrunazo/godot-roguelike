## Airborne attack state executing a flying jump kick.
class_name PlayerJumpKick
extends CharacterAttack

## State to transition to after landing on the floor and completing the attack.
@export var running_state: CharacterState


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return

	if check_dash():
		return
	if check_jump():
		return

	_update_hitstop(delta)
	var motion_scale: float = clampf(self_hitstop_scale, 0.0, 1.0) if is_in_hitstop() else 1.0

	if not character.is_on_floor():
		character.velocity += character.get_gravity() * delta
	elif character.velocity.y < 0.0:
		character.velocity.y = 0.0

	if lunging:
		character.velocity.x = lunge_direction.x * dash_speed * motion_scale
		character.velocity.z = lunge_direction.z * dash_speed * motion_scale
	elif movement_speed > 0.0:
		character.velocity.x = move_toward(character.velocity.x, character.move_direction.x * movement_speed, 15.0 * delta)
		character.velocity.z = move_toward(character.velocity.z, character.move_direction.z * movement_speed, 15.0 * delta)

	if not is_in_hitstop():
		character.look_toward_direction(aim_direction, delta)

	character.move_and_slide()


func finish_attack(_animation_name: String) -> void:
	if character == null or character.state_machine == null:
		return
	if character.is_on_floor():
		if running_state != null:
			character.state_machine.request_state(running_state.name)
		elif not next_states.is_empty():
			var next: CharacterState = next_states.pick_random()
			if next != null:
				character.state_machine.request_state(next.name)
	else:
		if fall_state != null:
			character.state_machine.request_state(fall_state.name)
		elif running_state != null:
			character.state_machine.request_state(running_state.name)
		elif not next_states.is_empty():
			var next: CharacterState = next_states.pick_random()
			if next != null:
				character.state_machine.request_state(next.name)
