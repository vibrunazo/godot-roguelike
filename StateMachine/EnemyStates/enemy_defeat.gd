## Physical state handling enemy defeat animation and disabling.
class_name EnemyDefeat
extends EnemyState


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	character.velocity = Vector3.ZERO
	character.move_direction = Vector3.ZERO
	character.face_direction = Vector3.ZERO
	character.move_and_slide()


func enter(_previous_state_path: String, _data := {}) -> void:
	if character != null:
		character.velocity = Vector3.ZERO
		character.move_direction = Vector3.ZERO
		character.face_direction = Vector3.ZERO
		if character.ai_state_machine != null:
			character.ai_state_machine.command_stop()
			character.ai_state_machine.set_physics_process(false)
		if character.animation_tree != null:
			character.animation_tree.change_immediate("Defeat")
