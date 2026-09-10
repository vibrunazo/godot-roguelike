## Physical state handling enemy defeat animation and disabling.
class_name EnemyDefeat
extends CharacterState


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	character.velocity = Vector3.ZERO
	character.move_direction = Vector3.ZERO
	character.face_target = Vector3.ZERO
	character.move_and_slide()


func enter(_previous_state_path: String, _data := {}) -> void:
	if character != null and character.animation_tree != null:
		character.animation_tree.change_immediate("Defeat")
