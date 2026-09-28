## AI state where the mind randomly wanders between points on the navigation mesh.
class_name AIMeander
extends AIState

## State to transition to when target is in attack range or navigation target is reached.
@export var attack_state: AIState
## Distance to target in meters at which the AI will transition to attacking.
@export var attack_range: float = 4.0
## State to transition to upon reaching the patrol point (fallback if attack_state is null).
@export var wait_state: AIState
## Optional state to transition to when an enemy target is detected within range.
@export var pursue_state: AIState
## Optional detection radius to trigger pursuit of targets (0.0 to disable).
@export var detection_range: float = 0.0


func enter(_previous_state_path: String, _data := {}) -> void:
	if character == null or not character.is_inside_tree() or character.navigation_agent_3d == null:
		return
	var target_pt: Vector3 = Vector3.ZERO
	if character.home_spawn_area != null and character.home_spawn_area.has_method("get_random_spawn_point"):
		target_pt = character.home_spawn_area.get_random_spawn_point()
	elif not character.home_position.is_zero_approx():
		var nav_map: RID = character.get_world_3d().navigation_map
		var offset: Vector3 = Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0))
		target_pt = NavigationServer3D.map_get_closest_point(nav_map, character.home_position + offset)
	else:
		target_pt = NavigationServer3D.map_get_random_point(
			character.get_world_3d().navigation_map,
			1,
			true
		)
	character.navigation_agent_3d.target_position = target_pt


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree() or ai_state_machine == null or not character.is_alive():
		return
	var target: Character = ai_state_machine.get_target()
	if pursue_state != null and _within(target, detection_range):
		finished.emit(pursue_state.name)
		return
	var nav_agent: NavigationAgent3D = character.navigation_agent_3d
	if nav_agent == null:
		return
	var can_attack: bool = _within(target, attack_range) and _attack_ready()
	if can_attack:
		_stop_and_face(target, delta)
		finished.emit(attack_state.name)
		return
	if nav_agent.is_target_reached():
		_stop_and_face(target, delta)
		if wait_state != null:
			finished.emit(wait_state.name)
			return
	follow_nav_path(nav_agent)


## True when there is a target within range (a range <= 0 never matches).
func _within(target: Character, reach: float) -> bool:
	if target == null or reach <= 0.0:
		return false
	return character.global_position.distance_squared_to(target.global_position) <= reach * reach


## True when the attack state exists and is off cooldown.
func _attack_ready() -> bool:
	if attack_state == null:
		return false
	if attack_state is AIAttack:
		return not (attack_state as AIAttack).is_on_cooldown()
	return true


## Stops walking and turns toward the target, if there is one.
func _stop_and_face(target: Character, delta: float) -> void:
	ai_state_machine.command_stop()
	if target != null:
		character.look_at_target(target.global_position, delta)
