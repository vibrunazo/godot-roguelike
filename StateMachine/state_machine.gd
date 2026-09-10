## The StateMachine is a Node in the Player scene. Each State the StateMachine can transition
## into is another Node child of the StateMachine.
class_name StateMachine 
extends Node

@export var initial_state: State = null

@onready var state: State = (func get_initial_state() -> State:
	if initial_state != null:
		return initial_state
	return get_child(0) as State if get_child_count() > 0 else null
).call()


func _ready() -> void:
	for state_node: State in find_children("*", "State"):
		state_node.finished.connect(_transition_to_next_state)

	await owner.ready
	if state != null:
		state.enter("")


func _unhandled_input(event: InputEvent) -> void:
	_bridge_action_to_intent(event)
	if state != null:
		state.handle_input(event)


## Shared controller-facing transition API used by the PlayerController
## (PlayerInputComponent orders) and the AIController (AIStateMachine orders).
## Runs the same transition path as the finished signal; returns false (with a
## warning) when the target state does not exist.
func request_state(target_state_path: String, data: Dictionary = {}) -> bool:
	if not has_node(target_state_path):
		var machine_name: String = owner.name if owner != null else name
		printerr(machine_name + ": Trying to transition to state " + target_state_path + " but it does not exist.")
		return false
	_transition_to_next_state(target_state_path, data)
	return true


## Test/live-input bridge: routes click/dash events through the PlayerController's
## orders, so existing sm._unhandled_input(...) drivers (and live input) keep the
## exact synchronous transition timing raw state input had. States additionally
## consume intents in physics_update for AI-raised flags.
func _bridge_action_to_intent(event: InputEvent) -> void:
	var body_state: CharacterState = state as CharacterState
	if body_state == null or body_state.character == null:
		return
	var input_comp: PlayerInputComponent = body_state.character.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp == null:
		return
	if event.is_action_pressed("click"):
		input_comp.order_attack()
	elif event.is_action_pressed("dash"):
		input_comp.order_dash()


func _physics_process(delta: float) -> void:
	if not is_inside_tree() or state == null:
		return
	state.physics_update(delta)


func _transition_to_next_state(target_state_path: String, data: Dictionary = {}) -> void:
	if not has_node(target_state_path):
		printerr(owner.name + ": Trying to transition to state " + target_state_path + " but it does not exist.")
		return

	var previous_state_path: String = ""
	if state != null:
		previous_state_path = state.name
		state.exit()
	state = get_node(target_state_path) as State
	if state != null:
		state.enter(previous_state_path, data)
	_clear_stale_intents()


## Drops edge intents pending on the newly entered state's character, so a press
## raised while a non-checking state (fall, stun, dash) was active never leaks
## into later states. Consume-on-read already covers checking states; this covers
## transitions away from states that never check.
func _clear_stale_intents() -> void:
	var body_state: CharacterState = state as CharacterState
	if body_state != null and body_state.character != null:
		body_state.character.attack_requested = false
		body_state.character.dash_requested = false
