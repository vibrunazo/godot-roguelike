## Base class for player-specific physical states.
class_name PlayerState
extends CharacterState

## State to transition to when dash action is pressed.
@export var dash_state: CharacterState
## State to transition to when attack action is pressed.
@export var attack_state: CharacterState


## Checks for dash input and transitions to dash_state if available.
func check_dash(event: InputEvent) -> void:
	if character == null or dash_state == null:
		return
	var input_comp: PlayerInputComponent = character.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp != null and not input_comp.can_dash():
		return
	if event.is_action_pressed("dash"):
		var direction: Vector3 = character.move_direction
		if direction.is_zero_approx() and character.mesh_mount != null:
			direction = character.mesh_mount.global_basis.z.normalized()
		if direction.is_zero_approx():
			direction = Vector3.FORWARD
		finished.emit(dash_state.name, {"direction": direction})


## Checks for attack input and transitions to attack_state if available.
func check_attack(event: InputEvent) -> void:
	if attack_state != null and event.is_action_pressed("click"):
		finished.emit(attack_state.name, {"direction": character.move_direction})
