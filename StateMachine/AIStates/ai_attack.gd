## AI state where the mind orders an attack action on the physical body and transitions upon completion.
class_name AIAttack
extends AIState

## The name of the physical attack state on the body StateMachine to execute.
@export var attack_state_name: String = "EnemyAttack"
## Potential AI states to transition to randomly after the attack finishes.
@export var next_states: Array[AIState] = []

var _attack_ordered: bool = false


func enter(_previous_state_path: String, _data := {}) -> void:
	if ai_state_machine != null:
		ai_state_machine.command_stop()
		var target: Character = ai_state_machine.get_target()
		if target != null and character != null:
			character.look_at_target(target.global_position)
		_attack_ordered = ai_state_machine.order_attack(attack_state_name)
		if not _attack_ordered:
			# If the body is unable to attack (e.g. stunned/falling), transition out immediately
			_finish_attack()


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree() or ai_state_machine == null or not character.is_alive():
		return
	ai_state_machine.command_stop()
	if _attack_ordered:
		if character.state_machine == null or character.state_machine.state == null or character.state_machine.state.name != attack_state_name:
			_finish_attack()


func exit() -> void:
	_attack_ordered = false


func end_attack() -> void:
	_finish_attack()


func _finish_attack() -> void:
	_attack_ordered = false
	if character != null and not character.is_alive():
		return
	if ai_state_machine != null:
		var target: Character = ai_state_machine.get_target()
		if target != null and character != null:
			character.look_at_target(target.global_position)
	if not next_states.is_empty():
		var chosen_state: AIState = next_states.pick_random()
		if chosen_state != null:
			finished.emit(chosen_state.name)
