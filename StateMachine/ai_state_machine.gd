## StateMachine controlling the behavioral decisions (Mind) of AI entities.
## Runs concurrently with the physical StateMachine (Body).
class_name AIStateMachine
extends StateMachine

## The character controlled by this AI state machine.
@export var character: Character
## Target node group to track and attack ("player" by default).
@export var target_group: String = "player"

## Currently resolved target character.
var target: Character = null


func _ready() -> void:
	# Mind executes before physical body StateMachine (priority -1 vs 0) to avoid 1-frame latency.
	process_physics_priority = -1
	if character == null:
		character = get_parent() as Character
	super._ready()


func _physics_process(delta: float) -> void:
	if character != null and not character.is_alive():
		return
	_evaluate_state_triggers(delta)
	super._physics_process(delta)


## Orchestrates conditional interrupts across child AIState nodes.
## Allows inactive AI states (such as cooldown attacks or phase changes) to preemptively activate.
## Evaluates states in descending priority order (higher priority evaluated first; ties preserve node order).
func _evaluate_state_triggers(delta: float) -> void:
	var candidates: Array[AIState] = []
	for child: Node in get_children():
		if child is AIState and child != state:
			candidates.append(child as AIState)
	candidates.sort_custom(func(a: AIState, b: AIState) -> bool:
		return a.priority > b.priority
	)
	for ai_child: AIState in candidates:
		if ai_child.evaluate_trigger(delta):
			break


## Returns the active target, finding the closest living member of target_group if needed.
func get_target() -> Character:
	if target != null and is_instance_valid(target) and target.is_alive():
		return target
	if character != null:
		target = character.get_nearest_target(target_group)
	else:
		target = null
	return target


## Sets desired movement direction and optional facing orientation target on the body.
func command_move(direction: Vector3, face_pos: Vector3 = Vector3.ZERO) -> void:
	if character != null and character.is_alive():
		character.move_direction = direction
		character.face_target = face_pos


## Orders the body to cease movement.
func command_stop() -> void:
	if character != null:
		character.move_direction = Vector3.ZERO
		character.face_target = Vector3.ZERO


## Raises an edge-triggered attack intent on the body for body states to consume.
## AIController counterpart to PlayerInputComponent.command_attack (same interface).
func command_attack() -> void:
	if character != null:
		character.attack_requested = true


## Raises an edge-triggered dash intent on the body for body states to consume.
## AIController counterpart to PlayerInputComponent.command_dash (same interface).
func command_dash() -> void:
	if character != null:
		character.dash_requested = true


## Orders the body into attack_state (an attack or ability on the body
## StateMachine) when the body accepts the order (Character.can_accept_order():
## not dead, falling or already in it; out of stun only when can_break_stun).
## Returns whether the body took the order.
func order_attack(attack_state: CharacterState, can_break_stun: bool = false, data: Dictionary = {}) -> bool:
	if character == null or not character.can_accept_order(attack_state, can_break_stun):
		return false
	return character.state_machine.request_state(attack_state.name, data)


## Wakes the mind from an idle state (waiting, meandering) into combat: the
## current state's alert_transition(). A mind already engaged stays as it is.
func alert() -> void:
	if character == null or not character.is_alive() or not state is AIState:
		return
	var next: AIState = (state as AIState).alert_transition()
	if next != null and next != state:
		request_state(next.name)
