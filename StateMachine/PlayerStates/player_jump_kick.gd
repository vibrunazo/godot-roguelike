## Airborne attack state executing a flying jump kick.
class_name PlayerJumpKick
extends CharacterAttack

## State to transition to after landing on the floor and completing the attack.
@export var running_state: CharacterState


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	super.enter(_previous_state_path, _data)
	if character != null:
		_lunge_base_velocity = Vector3(character.velocity.x, 0.0, character.velocity.z)


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return

	if check_dash():
		return
	if check_jump():
		return
	check_attack()

	if character.is_on_floor() and character.velocity.y <= 0.0:
		_cancel_on_landing()
		return

	_update_hitstop(delta)
	var motion_scale: float = clampf(self_hitstop_scale, 0.0, 1.0) if is_in_hitstop() else 1.0

	if not character.is_on_floor():
		character.velocity += character.get_gravity() * delta
	elif character.velocity.y < 0.0:
		character.velocity.y = 0.0

	if lunging:
		character.velocity.x = (_lunge_base_velocity.x + lunge_direction.x * dash_speed) * motion_scale
		character.velocity.z = (_lunge_base_velocity.z + lunge_direction.z * dash_speed) * motion_scale
	else:
		character.velocity.x = _lunge_base_velocity.x * motion_scale
		character.velocity.z = _lunge_base_velocity.z * motion_scale

	if not is_in_hitstop():
		character.look_toward_direction(aim_direction, delta)

	character.move_character()

	if character.is_on_floor() and character.velocity.y <= 0.0:
		_cancel_on_landing()


func _cancel_on_landing() -> void:
	if character == null or character.state_machine == null:
		return
	var target_attack: CharacterState = attack_state
	if target_attack == null and character.state_machine != null:
		target_attack = character.state_machine.get_node_or_null("PlayerAttack") as CharacterState

	var should_attack: bool = queued_attack or (character != null and character.consume_attack_request())
	if should_attack and target_attack != null:
		character.state_machine.request_state(target_attack.name, {"direction": character.move_direction})
	elif running_state != null:
		if character.animation_tree != null:
			character.animation_tree.change_immediate("WalkSpace")
		character.state_machine.request_state(running_state.name)
	elif not next_states.is_empty():
		var next: CharacterState = next_states.pick_random()
		if next != null:
			character.state_machine.request_state(next.name)


func finish_attack(_animation_name: String) -> void:
	if character == null or character.state_machine == null:
		return
	if character.is_on_floor():
		_cancel_on_landing()
	else:
		if fall_state != null:
			character.state_machine.request_state(fall_state.name)
		elif running_state != null:
			character.state_machine.request_state(running_state.name)
		elif not next_states.is_empty():
			var next: CharacterState = next_states.pick_random()
			if next != null:
				character.state_machine.request_state(next.name)
