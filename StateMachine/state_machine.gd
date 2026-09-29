## The StateMachine is a Node in the Player scene. Each State the StateMachine can transition
## into is another Node child of the StateMachine.
class_name StateMachine 
extends Node

## State entered when the owner is ready. Null uses the first child state.
@export var initial_state: State = null

@onready var state: State = (func get_initial_state() -> State:
	if initial_state != null:
		return initial_state
	return get_child(0) as State if get_child_count() > 0 else null
).call()


func _ready() -> void:
	for state_node: State in find_children("*", "State"):
		state_node.finished.connect(_transition_to_next_state)

	# States enter once the whole owner is ready (they read its components).
	# A machine built at runtime has no owner and enters at once.
	if owner != null and not owner.is_node_ready():
		await owner.ready
	if state != null:
		state.enter("")


## Shared controller-facing transition API used by the PlayerController
## (PlayerInputComponent orders) and the AIController (AIStateMachine orders).
## Runs the same transition path as the finished signal; returns false (with a
## warning) when the target state does not exist.
func request_state(target_state_path: String, data: Dictionary = {}) -> bool:
	return _transition_to_next_state(target_state_path, data)


func _physics_process(delta: float) -> void:
	if not is_inside_tree() or state == null:
		return
	state.physics_update(delta)


## Exits the current state and enters target_state_path (the finished
## signals land here too). Returns false, with an error, for a missing state.
func _transition_to_next_state(target_state_path: String, data: Dictionary = {}) -> bool:
	if not has_node(target_state_path):
		printerr("%s: Trying to transition to state %s but it does not exist." % [owner.name if owner != null else name, target_state_path])
		return false

	var previous_state_path: String = ""
	if state != null:
		previous_state_path = state.name
		state.exit()
	state = get_node(target_state_path) as State
	if state != null:
		state.enter(previous_state_path, data)
	_clear_stale_intents()
	return true


## Drops edge intents pending on the newly entered state's character, so a press
## raised while a non-checking state (fall, stun, dash) was active never leaks
## into later states. Consume-on-read already covers checking states; this covers
## transitions away from states that never check.
func _clear_stale_intents() -> void:
	var body_state: CharacterState = state as CharacterState
	if body_state != null and body_state.character != null:
		body_state.character.attack_requested = false
		body_state.character.dash_requested = false
		body_state.character.jump_requested = false
