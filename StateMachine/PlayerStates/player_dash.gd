## Physical state handling the player's rapid dash movement, VFX, and cooldown.
class_name PlayerDash
extends PlayerState

## State to transition to after the dash duration finishes.
@export var running_state: PlayerRun
## Speed during dash in meters per second.
@export var dash_speed: float = 50.0

@onready var dash_duration: Timer = $DashDuration

var direction: Vector3
var dash_root: Node3D
var dash_animation_player: AnimationPlayer
var dash_cooldown: Timer
var dash_audio: AudioStreamPlayer3D


func enter(_previous_state_path: String, _data := {}) -> void:
	if character == null:
		return
	var input_comp: PlayerInputComponent = character.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp != null:
		dash_cooldown = input_comp.dash_cooldown
		dash_audio = input_comp.dash_audio
	if dash_audio != null:
		dash_audio.play()

	direction = _data.get("direction", Vector3.ZERO)
	if direction.is_zero_approx() and character.mesh_mount != null:
		direction = character.mesh_mount.global_basis.z.normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD

	character.velocity = direction * dash_speed
	if dash_cooldown != null:
		dash_cooldown.start()
	dash_duration.start()

	if character.animation_tree != null:
		character.animation_tree.change_immediate("DodgeForward")

	if dash_root == null:
		dash_root = character.get_node_or_null("DashRoot") as Node3D
	if dash_animation_player == null and dash_root != null:
		dash_animation_player = dash_root.get_node_or_null("AnimationPlayer") as AnimationPlayer

	if dash_root != null and not direction.is_zero_approx():
		dash_root.look_at(character.global_position + direction)
	if dash_animation_player != null:
		dash_animation_player.stop()
		dash_animation_player.play("dash")


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	if dash_duration.is_stopped() and running_state != null:
		finished.emit(running_state.name)
	character.move_and_slide()
