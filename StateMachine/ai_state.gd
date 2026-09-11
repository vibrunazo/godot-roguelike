## Base state for AI decision states (Mind).
class_name AIState
extends State

## Reference to the owning AIStateMachine.
@export var ai_state_machine: AIStateMachine

## Reference to the Character controlled by the AI.
var character: Character:
	get:
		return ai_state_machine.character if ai_state_machine != null else null


func _ready() -> void:
	if ai_state_machine == null:
		ai_state_machine = get_parent() as AIStateMachine


## Evaluates whether this AI state wants to preemptively interrupt the active state and activate itself.
## Returns true if the state triggered and requested a transition to itself.
func evaluate_trigger(_delta: float) -> bool:
	return false
