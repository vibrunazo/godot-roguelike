## AI state that evaluates custom conditions (cooldown, range, stun state) while inactive
## and preemptively interrupts the active AI state to execute a specialized attack.
class_name AIConditionalAttack
extends AIState

## The name of the physical attack state on the body StateMachine to execute.
@export var attack_state_name: String = "EnemyAttack"
## Cooldown time in seconds between attack executions.
@export var cooldown: float = 8.0
## Maximum distance to target to trigger this attack.
@export var trigger_range: float = 3.5
## Minimum distance to target to trigger this attack (0.0 = no minimum).
@export var min_range: float = 0.0
## Whether this attack can be ordered even if the physical body is currently in EnemyStun.
@export var can_break_stun: bool = true
## AI state to transition to after the attack animation finishes.
@export var next_state: AIState
## Initial cooldown applied when entering the scene (0.0 = ready immediately).
@export var initial_cooldown: float = 0.0

## Remaining cooldown time in seconds before this attack can trigger again.
var cooldown_timer: float = 0.0
var _attack_ordered: bool = false


func _ready() -> void:
	super._ready()
	cooldown_timer = initial_cooldown


## Evaluates whether this conditional attack is ready to trigger and preempt the active state.
func evaluate_trigger(delta: float) -> bool:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta

	if character == null or not character.is_inside_tree() or not character.is_alive():
		return false
	if cooldown_timer > 0.0:
		return false
	if ai_state_machine == null:
		return false

	var target: Character = ai_state_machine.get_target()
	if target == null:
		return false

	var dist_sq: float = character.global_position.distance_squared_to(target.global_position)
	if dist_sq > (trigger_range * trigger_range):
		return false
	if min_range > 0.0 and dist_sq < (min_range * min_range):
		return false

	if character.state_machine == null or character.state_machine.state == null:
		return false

	var current_body_state: String = character.state_machine.state.name
	if current_body_state == attack_state_name or current_body_state == "EnemyDefeat" or current_body_state == "EnemyFall":
		return false
	if current_body_state == "EnemyStun" and not can_break_stun:
		return false

	ai_state_machine.request_state(name)
	return true


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	cooldown_timer = cooldown
	_attack_ordered = false
	if ai_state_machine != null:
		ai_state_machine.command_stop()
		var target: Character = ai_state_machine.get_target()
		if target != null and character != null:
			character.look_at_target(target.global_position)
		_attack_ordered = ai_state_machine.order_attack(attack_state_name, can_break_stun)
		if not _attack_ordered:
			_finish_attack.call_deferred()


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
	if next_state != null:
		finished.emit(next_state.name)
