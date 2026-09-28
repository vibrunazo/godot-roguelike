## AI state entered by flow (e.g. from AIMeander or AIWait) that orders an
## attack on the body (see AIAttackBase) and then moves to one of next_states
## at random.
class_name AIAttack
extends AIAttackBase

## Potential AI states to transition to randomly after the attack finishes.
@export var next_states: Array[AIState] = []


func _next_state() -> AIState:
	return next_states.pick_random() if not next_states.is_empty() else null
