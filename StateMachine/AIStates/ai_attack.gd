## AI state where the mind orders an attack action on the physical body and transitions upon completion.
class_name AIAttack
extends AIState

## The name of the physical attack state on the body StateMachine to execute.
@export var attack_state_name: String = "EnemyAttack"
## Potential AI states to transition to randomly after the attack finishes.
@export var next_states: Array[AIState] = []

var _internal_cooldown: float = 0.0
var _internal_cooldown_timer: float = 0.0
var _attack_ordered: bool = false

## Cooldown time in seconds between attack executions (delegates to physical attack state if present).
var cooldown: float:
	get:
		var att: CharacterState = get_attack_state()
		if att != null and "cooldown" in att:
			return att.cooldown
		return _internal_cooldown
	set(val):
		_internal_cooldown = val
		var att: CharacterState = get_attack_state()
		if att != null and "cooldown" in att:
			att.cooldown = val

## Remaining cooldown time in seconds before this attack can be executed again (delegates to physical attack state).
var cooldown_timer: float:
	get:
		var att: CharacterState = get_attack_state()
		if att != null and "cooldown_timer" in att:
			return att.cooldown_timer
		return _internal_cooldown_timer
	set(val):
		_internal_cooldown_timer = val
		var att: CharacterState = get_attack_state()
		if att != null and "cooldown_timer" in att:
			att.cooldown_timer = val


## Helper to look up the physical attack state on the body StateMachine.
func get_attack_state() -> CharacterState:
	if character == null or character.state_machine == null:
		return null
	return character.state_machine.get_node_or_null(attack_state_name) as CharacterState


## Returns true if this attack is currently on cooldown.
func is_on_cooldown() -> bool:
	var att: CharacterState = get_attack_state()
	if att != null and att.has_method("is_on_cooldown"):
		return att.is_on_cooldown()
	return cooldown_timer > 0.0


## Updates the cooldown timer while this state is inactive so cooldown progresses.
func evaluate_trigger(delta: float) -> bool:
	var att: CharacterState = get_attack_state()
	if att != null and att.has_method("tick_cooldown"):
		att.tick_cooldown(delta)
	elif _internal_cooldown_timer > 0.0:
		_internal_cooldown_timer -= delta
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
	var att: CharacterState = get_attack_state()
	if att != null and att.has_method("tick_cooldown"):
		att.tick_cooldown(delta)
	elif _internal_cooldown_timer > 0.0:
		_internal_cooldown_timer -= delta
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
