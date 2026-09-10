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
	super._physics_process(delta)


## Returns the active target, finding the closest living member of target_group if needed.
func get_target() -> Character:
	if target != null and is_instance_valid(target) and target.health_component != null and target.health_component.current_health > 0.0:
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


## Orders the physical body StateMachine to execute an attack state if available.
## AI-side policy (liveness, stun/defeat/fall veto) wraps the shared transition API.
func order_attack(attack_state_name: String = "") -> bool:
	if character == null or not character.is_alive():
		return false
	if character.state_machine == null or character.state_machine.state == null:
		return false
	var current_body_state: String = character.state_machine.state.name
	if current_body_state == attack_state_name or current_body_state == "EnemyStun" or current_body_state == "EnemyDefeat" or current_body_state == "EnemyFall":
		return false
	if character.state_machine.get_node_or_null(attack_state_name) == null:
		push_warning("AIStateMachine: order_attack('%s') requested non-existent state on body StateMachine." % attack_state_name)
		return false
	return character.state_machine.request_state(attack_state_name)
