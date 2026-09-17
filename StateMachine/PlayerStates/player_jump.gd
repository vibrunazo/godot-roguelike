## Physical state handling player jumping, vertical impulse, and air control.
class_name PlayerJump
extends CharacterState

## Peak jump height in meters.
@export var jump_height: float = 2.5
## Ratio of horizontal movement control in mid-air (1.0 = full control, 0.0 = no air control).
@export_range(0.0, 1.0) var control_ratio: float = 1.0
## State to transition to after landing on the floor.
@export var running_state: CharacterState
## Optional audio stream player for jump sound effects.
@export var jump_audio: AudioStreamPlayer3D

var _launch_velocity: Vector3 = Vector3.ZERO
var _has_left_floor: bool = false


func enter(_previous_state_path: String, _data := {}) -> void:
	if character == null:
		return
	if jump_audio == null and character != null:
		jump_audio = character.get_node_or_null("JumpAudio") as AudioStreamPlayer3D
	if jump_audio != null:
		jump_audio.play()

	var speed: float = character.attribute_component.get_current(AttributeComponent.STAT_SPEED) if character.attribute_component != null else 8.0
	_launch_velocity = Vector3(character.velocity.x, 0.0, character.velocity.z)
	var direction: Vector3 = _data.get("direction", character.move_direction)
	if not direction.is_zero_approx():
		_launch_velocity = direction * speed
		character.velocity.x = _launch_velocity.x
		character.velocity.z = _launch_velocity.z

	var gravity_mag: float = character.get_gravity().length()
	if is_zero_approx(gravity_mag):
		gravity_mag = 9.8
	character.velocity.y = sqrt(2.0 * gravity_mag * jump_height)
	_has_left_floor = false

	if character.animation_tree != null:
		character.animation_tree.change_immediate("Jump")


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return

	if check_attack():
		return

	character.velocity += character.get_gravity() * delta

	if character.knockback_component != null and character.knockback_component.is_active():
		character.velocity.x = character.knockback_component.magnitude.x
		character.velocity.z = character.knockback_component.magnitude.z
	else:
		if control_ratio > 0.0 and not character.move_direction.is_zero_approx():
			var speed: float = character.attribute_component.get_current(AttributeComponent.STAT_SPEED) if character.attribute_component != null else 8.0
			var target_velocity: Vector3 = character.move_direction * speed
			var accel: float = speed * 6.0 * control_ratio
			character.velocity.x = move_toward(character.velocity.x, target_velocity.x, accel * delta)
			character.velocity.z = move_toward(character.velocity.z, target_velocity.z, accel * delta)
		var current_h: Vector3 = Vector3(character.velocity.x, 0.0, character.velocity.z)
		if not current_h.is_zero_approx():
			character.look_toward_direction(current_h.normalized(), delta)

	character.move_character()

	if not character.is_on_floor():
		_has_left_floor = true
	elif _has_left_floor and character.velocity.y <= 0.0:
		if running_state != null:
			finished.emit(running_state.name)
