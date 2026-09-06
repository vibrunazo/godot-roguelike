## State handling enemy attack execution.
class_name EnemyAttack
extends EnemyState

## Name of the attack animation in the AnimationTree.
@export var attack_name: String
## State to transition to after the attack animation finishes.
@export var next_state: EnemyState


func physics_update(_delta: float) -> void:
	enemy.velocity = Vector3.ZERO
	enemy.move_and_slide()


func enter(_previous_state_path: String, _data := {}) -> void:
	enemy.animation_tree.change_immediate(attack_name)
	if not enemy.animation_tree.animation_finished.is_connected(end_attack):
		enemy.animation_tree.animation_finished.connect(end_attack, CONNECT_ONE_SHOT)


func exit() -> void:
	if enemy.animation_tree.animation_finished.is_connected(end_attack):
		enemy.animation_tree.animation_finished.disconnect(end_attack)


func end_attack(_animation_name: String) -> void:
	if next_state:
		finished.emit(next_state.name)
