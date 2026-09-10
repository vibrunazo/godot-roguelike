## Physical state handling enemy hit reaction and recovery.
class_name EnemyStun
extends EnemyState

## State to transition to after the stun animation finishes.
@export var next_state: EnemyState


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	if not character.is_on_floor() and fall_state != null:
		finished.emit(fall_state.name)
	if character.knockback_component != null and character.knockback_component.is_active():
		character.velocity = character.knockback_component.magnitude
	else:
		character.velocity = Vector3.ZERO
	character.move_and_slide()


func enter(_previous_state_path: String, _data := {}) -> void:
	if character != null and character.animation_tree != null:
		character.animation_tree.change_immediate("Stun")
		connect_one_shot(character.animation_tree.animation_finished, end_stun)


func exit() -> void:
	if character != null and character.animation_tree != null:
		disconnect_safe(character.animation_tree.animation_finished, end_stun)


func end_stun(_animation_name: String) -> void:
	if next_state != null:
		finished.emit(next_state.name)
