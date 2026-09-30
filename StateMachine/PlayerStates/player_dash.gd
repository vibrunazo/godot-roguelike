## Physical state handling the player's rapid dash movement, VFX, and cooldown.
class_name PlayerDash
extends CharacterState

## Time, in seconds, the summed physics ticks may fall short of dash_duration
## and still count as the full dash (float rounding).
const DURATION_EPSILON: float = 0.0001

## State to transition to after the dash duration finishes.
@export var running_state: PlayerRun
## Speed during dash in meters per second.
@export var dash_speed: float = 50.0
## How long the dash moves at dash_speed, in seconds (physics clock). The dash
## covers exactly dash_speed * dash_duration meters at any physics tick rate,
## then the running state brakes the leftover speed.
@export var dash_duration: float = 0.1
## Sound effect played when the dash starts.
@export var dash_audio: AudioStreamPlayer3D
## Steers the dash away from ending over a pit when that looks like a mistake
## (see LandingAssist). Null dashes exactly where it is pointed.
@export var landing_assist: LandingAssist

var direction: Vector3
## Physics time, in seconds, the current dash has moved for.
var _elapsed: float = 0.0
## True when the dash duration expired naturally (vs. interrupted by a forced
## state change). Reported through the ENDED event's "completed" data key.
var _dash_completed: bool = false
var dash_root: Node3D
var dash_animation_player: AnimationPlayer


func enter(_previous_state_path: String, _data := {}) -> void:
	if character == null:
		return
	_dash_completed = false
	_elapsed = 0.0
	if dash_audio != null:
		dash_audio.play()

	direction = _data.get("direction", Vector3.ZERO)
	if direction.is_zero_approx() and character.mesh_mount != null:
		direction = character.mesh_mount.global_basis.z.normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	if landing_assist != null:
		direction = landing_assist.steer(character, direction, get_dash_distance(), dash_speed)

	character.velocity = direction * dash_speed
	# The body owns the cooldown: can_dash() reads the same timer.
	if character.dash_cooldown != null:
		character.dash_cooldown.start()

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

	broadcast_ability_event(AbilityEvent.Phase.STARTED, {}, direction)


## Horizontal distance a full dash covers, in meters.
func get_dash_distance() -> float:
	return dash_speed * dash_duration



## Moves at dash_speed until dash_duration of physics time has passed; the
## last tick moves only the time that was left, so the dash length never
## depends on the tick rate. Hands over to running_state on that same tick.
func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	var step: float = minf(delta, dash_duration - _elapsed)
	_elapsed += delta
	if step > 0.0:
		character.velocity = direction * dash_speed * (step / delta)
		character.move_character()
	# Summed ticks land a hair short of the duration (6 * 1/60 < 0.1).
	if _elapsed >= dash_duration - DURATION_EPSILON and running_state != null:
		_dash_completed = true
		character.velocity = direction * dash_speed
		finished.emit(running_state.name)


## Broadcasts the ENDED lifecycle event (with "completed" reporting whether the
## dash ran its full duration), so granted passives fire exactly once per dash
## however it ended.
func exit() -> void:
	broadcast_ability_event(AbilityEvent.Phase.ENDED, {"completed": _dash_completed}, direction)
