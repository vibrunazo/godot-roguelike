## AI state that evaluates conditions (cooldown, target within trigger_range)
## while inactive and preemptively interrupts the active AI state to execute the
## leaping dodge ability (body_state: the body's EnemyLeapingDodge). Configure
## body_state, trigger_range and can_break_stun on the node like any
## AIConditionalAttack: this state never rewrites them. Unlike other
## conditional attacks it orders on entry, away from the target.
class_name AILeapingDodge
extends AIConditionalAttack


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
				character.look_toward_direction(away_dir, character.get_physics_process_delta_time())

		var leap_data: Dictionary = {"direction": away_dir}
		_attack_ordered = ai_state_machine.order_attack(body_state, can_break_stun, leap_data)

		if not _attack_ordered:
			_finish_attack.call_deferred()


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree() or ai_state_machine == null or not character.is_alive():
		return
	ai_state_machine.command_stop()
	if _attack_ordered:
		if character.state_machine == null or character.state_machine.state != body_state:
			_finish_attack()
