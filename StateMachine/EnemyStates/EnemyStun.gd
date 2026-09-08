class_name EnemyStun
extends EnemyState

## State to transition to after the stun animation finishes.
@export var next_state: EnemyState


func physics_update(_delta: float) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	if not enemy.is_on_floor() and fall_state:
		finished.emit(fall_state.name)
	if enemy.knockback_component.is_active():
		enemy.velocity = enemy.knockback_component.magnitude
	else:
		enemy.velocity = Vector3.ZERO
	enemy.move_and_slide()


func enter(_previous_state_path: String, _data := {}) -> void:
	enemy.animation_tree.change_immediate("Stun")
	if not enemy.animation_tree.animation_finished.is_connected(end_stun):
		enemy.animation_tree.animation_finished.connect(end_stun, CONNECT_ONE_SHOT)


func exit() -> void:
	if enemy.animation_tree.animation_finished.is_connected(end_stun):
		enemy.animation_tree.animation_finished.disconnect(end_stun)


func end_stun(_animation_name: String) -> void:
	finished.emit(next_state.name)
