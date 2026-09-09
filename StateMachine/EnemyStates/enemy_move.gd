## Physical state handling baseline enemy movement, idling, and walking animation blending.
class_name EnemyMove
extends EnemyState


func enter(_previous_state_path: String, _data := {}) -> void:
	if character != null and character.animation_tree != null:
		character.animation_tree.change_immediate("WalkSpace")


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree() or not character.is_alive():
		return

	core_movement(delta, character.movement_speed, character.move_direction)

	if character.animation_tree != null:
		if character.move_direction.is_zero_approx():
			character.animation_tree.blend_target = -1.0
		else:
			character.animation_tree.blend_target = 1.0

	if not character.face_direction.is_zero_approx():
		look_at_target(character.face_direction)

	character.move_and_slide()
