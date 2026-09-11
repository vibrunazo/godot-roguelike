## AI state where the mind orders an attack action on the physical body and transitions upon completion.
class_name AIAttack
extends AIState

## The name of the physical attack state on the body StateMachine to execute.
@export var attack_state_name: String = "EnemyAttack"
## Potential AI states to transition to randomly after the attack finishes.
@export var next_states: Array[AIState] = []
## Cooldown time in seconds between attack executions (0.0 = no cooldown).
@export var cooldown: float = 0.0

## Remaining cooldown time in seconds before this attack can be executed again.
var cooldown_timer: float = 0.0
var _attack_ordered: bool = false


## Returns true if this attack is currently on cooldown.
func is_on_cooldown() -> bool:
	return cooldown_timer > 0.0


## Updates the cooldown timer while this state is inactive so cooldown progresses.
func evaluate_trigger(delta: float) -> bool:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
	return false


func enter(_previous_state_path: String, _data := {}) -> void:
	cooldown_timer = cooldown
	if ai_state_machine != null:
		ai_state_machine.command_stop()
		var target: Character = ai_state_machine.get_target()
		if target != null and character != null:
			character.look_at_target(target.global_position)
		_attack_ordered = ai_state_machine.order_attack(attack_state_name)
		if not _attack_ordered:
			# If the body is unable to attack (e.g. stunned/falling), transition out deferred
			# to prevent synchronous re-entrant state transitions while still entering this state.
			_finish_attack.call_deferred()


func physics_update(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
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
