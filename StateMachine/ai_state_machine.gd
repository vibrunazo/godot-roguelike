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


## Sets desired movement direction and optional facing orientation on the body.
func command_move(direction: Vector3, face_dir: Vector3 = Vector3.ZERO) -> void:
	if character != null and character.is_alive():
		character.move_direction = direction
		character.face_direction = face_dir


## Orders the body to cease movement.
func command_stop() -> void:
	if character != null:
		character.move_direction = Vector3.ZERO
		character.face_direction = Vector3.ZERO


## Orders the physical body StateMachine to execute an attack state if available.
func order_attack(attack_state_name: String = "") -> bool:
	if character == null or not character.is_alive() or character.state_machine == null or character.state_machine.state == null:
		return false
	if character.state_machine.state.name == attack_state_name or character.state_machine.state.name == "EnemyStun" or character.state_machine.state.name == "EnemyDefeat" or character.state_machine.state.name == "EnemyFall":
		return false
	character.state_machine.state.finished.emit(attack_state_name)
	return true
