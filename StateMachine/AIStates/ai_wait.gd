## AI state where the mind pauses and idles before making its next behavioral decision.
class_name AIWait
extends AIState

## State to transition to after wait timeout.
@export var next_state: AIState
## Duration of the wait period in seconds.
@export var wait_duration: float = 2.0

var timer: SceneTreeTimer


func enter(_previous_state_path: String, _data := {}) -> void:
	if ai_state_machine != null:
		ai_state_machine.command_stop()
	timer = get_tree().create_timer(wait_duration)
	timer.timeout.connect(end_wait, CONNECT_ONE_SHOT)


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree() or ai_state_machine == null or not character.is_alive():
		return
	ai_state_machine.command_stop()


func exit() -> void:
	if timer != null and timer.timeout.is_connected(end_wait):
		timer.timeout.disconnect(end_wait)


func end_wait() -> void:
	if character != null and not character.is_alive():
		return
	if ai_state_machine != null:
		var target: Character = ai_state_machine.get_target()
		if target != null and character != null:
			character.look_at_target(target.global_position)
	if next_state != null:
		finished.emit(next_state.name)
