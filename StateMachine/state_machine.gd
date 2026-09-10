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
	if state != null:
		state.handle_input(event)


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
