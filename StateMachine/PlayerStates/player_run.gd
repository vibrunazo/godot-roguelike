## Physical state handling player running, movement blending, and action inputs.
class_name PlayerRun
extends CharacterState


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	# Intent checks run before movement (same priority raw input had): a consumed
	# intent transitions synchronously, so the old state's motion must not run.
	if check_dash():
		return
	if check_attack():
		return
	core_movement(delta, character.movement_speed, character.move_direction)
	if character.animation_tree != null:
		if not character.move_direction.is_zero_approx():
			character.animation_tree.blend_target = 1.0
		else:
			character.animation_tree.blend_target = -1.0
	if not character.is_on_floor() and fall_state != null:
		finished.emit(fall_state.name)
	character.move_and_slide()
