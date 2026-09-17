## Physical state handling player defeat animation and disabling.
## Mirrors EnemyDefeat: zeroes motion every frame so the corpse rests where it
## fell, and plays the Defeat animation once on entry. Never exits; the
## game-over screen takes over from here.
class_name PlayerDefeat
extends CharacterState


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	character.velocity = Vector3.ZERO
	character.move_direction = Vector3.ZERO
	character.face_target = Vector3.ZERO
	character.move_character()


func enter(_previous_state_path: String, _data := {}) -> void:
	if character != null and character.animation_tree != null:
		character.animation_tree.change_immediate("Defeat")
