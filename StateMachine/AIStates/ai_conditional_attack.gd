## AI state that evaluates custom conditions (body state ready, range, stun
## rules) while inactive and preemptively interrupts the active AI state to
## execute a specialized attack or ability (see AIAttackBase), then moves to
## next_state.
class_name AIConditionalAttack
extends AIAttackBase

## Maximum distance to target to trigger this attack.
@export var trigger_range: float = 3.5
## Minimum distance to target to trigger this attack (0.0 = no minimum).
@export var min_range: float = 0.0
## Whether this attack can be ordered even while the body is in its stun state
## (Character.stun_state).
@export var can_break_stun: bool = true
## AI state to transition to after the attack animation finishes.
@export var next_state: AIState


## Triggers (switching the mind to this state) when the body state can
## activate (off cooldown, tags allow it), the target is between min_range and
## trigger_range, and the body would accept the order.
func evaluate_trigger(_delta: float) -> bool:
	if character == null or not character.is_inside_tree() or not character.is_alive() or ai_state_machine == null:
		return false
	if body_state == null or not body_state.can_activate():
		return false
	var target: Character = ai_state_machine.get_target()
	if target == null:
		return false
	var dist_sq: float = character.global_position.distance_squared_to(target.global_position)
	if dist_sq > trigger_range * trigger_range:
		return false
	if min_range > 0.0 and dist_sq < min_range * min_range:
		return false
	if not character.can_accept_order(body_state, can_break_stun):
		return false
	ai_state_machine.request_state(name)
	return true


func _breaks_stun() -> bool:
	return can_break_stun


func _next_state() -> AIState:
	return next_state
