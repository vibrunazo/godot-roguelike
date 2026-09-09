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
