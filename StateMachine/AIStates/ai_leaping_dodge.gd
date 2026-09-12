## AI state that evaluates conditions (cooldown, player distance < 5m) while inactive
## and preemptively interrupts the active AI state to execute the leaping dodge ability.
class_name AILeapingDodge
extends AIConditionalAttack

## The name of the physical leaping dodge state on the body StateMachine to execute.
@export var ability_state_name: String = "EnemyLeapingDodge"
## Maximum range of the leap in meters (15.0m default).
@export var max_range: float = 15.0


func _ready() -> void:
	super._ready()
	# Set default values for leaping dodge if not explicitly overridden
	if attack_state_name == "EnemyAttack":
		attack_state_name = ability_state_name
	if is_equal_approx(cooldown, 8.0):
		cooldown = 12.0
	if is_equal_approx(trigger_range, 3.5):
		trigger_range = 5.0
	can_break_stun = false


## Evaluates whether this leaping dodge is ready to trigger and preempt the active state.
## Triggers whenever target player is closer than 5 meters and cooldown is expired.
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

	var target_body_state: String = attack_state_name if attack_state_name != "" else ability_state_name
	var current_body_state: String = character.state_machine.state.name
	if current_body_state == target_body_state or current_body_state == "EnemyDefeat" or current_body_state == "EnemyFall":
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
		var away_dir: Vector3 = Vector3.ZERO
		if target != null and character != null:
			away_dir = character.global_position - target.global_position
			away_dir.y = 0.0
			if not away_dir.is_zero_approx():
				away_dir = away_dir.normalized()
				character.look_toward_direction(away_dir, 1.0)

		var target_body_state: String = attack_state_name if attack_state_name != "" else ability_state_name
		var leap_data: Dictionary = {"direction": away_dir}
		_attack_ordered = ai_state_machine.order_attack(target_body_state, can_break_stun, leap_data)

		if not _attack_ordered:
			_finish_attack.call_deferred()


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree() or ai_state_machine == null or not character.is_alive():
		return
	ai_state_machine.command_stop()
	if _attack_ordered:
		var target_body_state: String = attack_state_name if attack_state_name != "" else ability_state_name
		if character.state_machine == null or character.state_machine.state == null or character.state_machine.state.name != target_body_state:
			_finish_attack()
