## Physical state handling the Firebomber enemy's high leaping dodge ability.
## Leaps high in the air along a ballistic trajectory to a new location away from threats.
class_name EnemyLeapingDodge
extends CharacterState

## State to transition to after completing the leap and landing.
@export var next_state: CharacterState
## Cooldown time in seconds for this ability (12.0s default).
@export var cooldown: float = 12.0
## Maximum horizontal range of the leap in meters (15.0m default).
@export var max_range: float = 15.0
## Minimum horizontal range of the leap in meters.
@export var min_range: float = 5.0
## Peak height in meters reached at the apex of the jump arc.
@export var peak_height: float = 5.0
## Total duration in seconds of the leap trajectory.
@export var leap_duration: float = 1.0
## Whether this ability has hyper-armor (cannot be interrupted into stun while active).
@export var uninterruptable: bool = true
## Name of the animation to trigger on the animation tree for the leap.
@export var leap_animation_name: String = "Jump_Full_Short"

## Starting position of the current leap in global 3D space.
var start_position: Vector3 = Vector3.ZERO
## Target landing position of the current leap in global 3D space.
var target_position: Vector3 = Vector3.ZERO
## Elapsed time in seconds since the leap started.
var elapsed_time: float = 0.0
## Horizontal velocity vector applied during the leap.
var horizontal_velocity: Vector3 = Vector3.ZERO
## Current vertical velocity in meters per second.
var vertical_velocity: float = 0.0
## Downward gravity acceleration applied during the leap.
var gravity_accel: float = 0.0
## Flag indicating whether a leap is actively in progress.
var is_leaping: bool = false


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	if character == null or not character.is_inside_tree():
		return

	start_position = character.global_position
	elapsed_time = 0.0
	is_leaping = true

	# Resolve target position
	if _data.has("target_position") and _data["target_position"] is Vector3:
		target_position = _data["target_position"] as Vector3
		var disp: Vector3 = target_position - start_position
		if disp.length() > max_range:
			target_position = start_position + disp.normalized() * max_range
	else:
		var dir: Vector3 = Vector3.ZERO
		if _data.has("direction") and _data["direction"] is Vector3:
			dir = _data["direction"] as Vector3
		if dir.is_zero_approx():
			var threat: Character = character.get_nearest_target("player")
			if threat != null:
				dir = character.global_position - threat.global_position
				dir.y = 0.0
		if dir.is_zero_approx() and character.mesh_mount != null:
			dir = -character.mesh_mount.global_basis.z.normalized()
		if dir.is_zero_approx():
			dir = Vector3.BACK

		dir = dir.normalized()
		var candidate: Vector3 = start_position + dir * max_range

		if character.is_inside_tree():
			var space_state: PhysicsDirectSpaceState3D = character.get_world_3d().direct_space_state
			candidate = _find_best_landing_position(space_state, dir)

		target_position = candidate

	# Ensure displacement does not exceed max_range
	var horiz_disp: Vector3 = target_position - start_position
	horiz_disp.y = 0.0
	if horiz_disp.length() > max_range:
		horiz_disp = horiz_disp.normalized() * max_range
		target_position = Vector3(start_position.x + horiz_disp.x, target_position.y, start_position.z + horiz_disp.z)

	# Calculate ballistic trajectory parameters
	var duration: float = maxf(leap_duration, 0.1)
	horizontal_velocity = horiz_disp / duration
	gravity_accel = (8.0 * peak_height) / (duration * duration)
	vertical_velocity = (4.0 * peak_height / duration) + ((target_position.y - start_position.y) / duration)

	character.velocity = Vector3(horizontal_velocity.x, vertical_velocity, horizontal_velocity.z)

	if not horizontal_velocity.is_zero_approx():
		character.look_toward_direction(horizontal_velocity.normalized(), 1.0)

	_trigger_animation()


## Finds the best open landing location evaluating primary direction and lateral escape angles when cornered.
func _find_best_landing_position(space_state: PhysicsDirectSpaceState3D, primary_dir: Vector3) -> Vector3:
	var angles_to_try: Array[float] = [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, 3.0 * PI / 4.0, -3.0 * PI / 4.0]
	var best_candidate: Vector3 = start_position + primary_dir * min_range
	var best_distance: float = -1.0
	var found_adequate: bool = false

	for angle: float in angles_to_try:
		var cur_dir: Vector3 = primary_dir.rotated(Vector3.UP, angle).normalized()
		var ray_start: Vector3 = start_position + Vector3(0.0, 0.5, 0.0)
		var ray_end: Vector3 = start_position + cur_dir * max_range + Vector3(0.0, 0.5, 0.0)
		var ray_query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1)
		var ray_res: Dictionary = space_state.intersect_ray(ray_query)

		var available_dist: float = max_range
		if not ray_res.is_empty():
			var hit_dist: float = (ray_res["position"] as Vector3).distance_to(start_position)
			available_dist = maxf(hit_dist - 1.0, 0.5)

		var test_pos: Vector3 = start_position + cur_dir * available_dist

		# Snap to navigation mesh if available and safe (does not cross walls)
		var map_rid: RID = character.get_world_3d().navigation_map
		if map_rid.is_valid() and NavigationServer3D.map_get_iteration_id(map_rid) > 0 and not NavigationServer3D.map_get_regions(map_rid).is_empty():
			var nav_point: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, test_pos)
			if nav_point.is_finite() and not nav_point.is_zero_approx() and nav_point.distance_to(start_position) <= (max_range + 1.0):
				var wall_check := PhysicsRayQueryParameters3D.create(ray_start, nav_point + Vector3(0.0, 0.5, 0.0), 1)
				var wall_res: Dictionary = space_state.intersect_ray(wall_check)
				if wall_res.is_empty():
					test_pos = nav_point
					available_dist = (test_pos - start_position).length()

		# Check for floor at test_pos
		var floor_query := PhysicsRayQueryParameters3D.create(
			test_pos + Vector3(0.0, 2.0, 0.0),
			test_pos + Vector3(0.0, -4.0, 0.0),
			1
		)
		var floor_res: Dictionary = space_state.intersect_ray(floor_query)
		var floor_y: float = start_position.y
		var has_floor: bool = false
		if not floor_res.is_empty():
			has_floor = true
			floor_y = (floor_res["position"] as Vector3).y + 1.0
		else:
			for fraction: float in [0.75, 0.5, 0.25]:
				var fb_pos: Vector3 = start_position.lerp(test_pos, fraction)
				floor_query.from = fb_pos + Vector3(0.0, 2.0, 0.0)
				floor_query.to = fb_pos + Vector3(0.0, -4.0, 0.0)
				floor_res = space_state.intersect_ray(floor_query)
				if not floor_res.is_empty():
					has_floor = true
					test_pos = fb_pos
					floor_y = (floor_res["position"] as Vector3).y + 1.0
					available_dist = (test_pos - start_position).length()
					break

		if has_floor:
			test_pos.y = floor_y
			if available_dist >= min_range:
				return test_pos
			if available_dist > best_distance:
				best_distance = available_dist
				best_candidate = test_pos
				found_adequate = true

	if found_adequate:
		return best_candidate

	return start_position + primary_dir * minf(min_range, max_range)


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree() or not character.is_alive():
		return

	elapsed_time += delta
	vertical_velocity -= gravity_accel * delta
	character.velocity = Vector3(horizontal_velocity.x, vertical_velocity, horizontal_velocity.z)
	character.move_and_slide()

	# Fall pit detection
	if character.global_position.y < -3.0 and fall_state != null:
		is_leaping = false
		finished.emit(fall_state.name)
		return

	# Touchdown conditions
	var past_apex: bool = elapsed_time >= (leap_duration * 0.4) and vertical_velocity <= 0.0
	var landed_on_floor: bool = past_apex and character.is_on_floor()
	var duration_floor_reached: bool = elapsed_time >= leap_duration and character.is_on_floor()
	var timeout_reached: bool = elapsed_time >= (leap_duration + 0.3)

	if landed_on_floor or duration_floor_reached or timeout_reached:
		_finish_leap()


func exit() -> void:
	is_leaping = false
	if character != null and character.is_inside_tree():
		character.velocity = Vector3.ZERO


func _finish_leap() -> void:
	is_leaping = false
	if character != null and character.is_inside_tree():
		character.velocity = Vector3.ZERO
		if character.animation_tree != null:
			character.animation_tree.change_immediate("WalkSpace")
	if next_state != null:
		finished.emit(next_state.name)


func _trigger_animation() -> void:
	if character == null or character.animation_tree == null:
		return
	if character.animation_tree.tree_root is AnimationNodeStateMachine:
		var root_sm: AnimationNodeStateMachine = character.animation_tree.tree_root as AnimationNodeStateMachine
		if root_sm.has_node(leap_animation_name):
			character.animation_tree.change_immediate(leap_animation_name)
		elif root_sm.has_node("Jump_Full_Short"):
			character.animation_tree.change_immediate("Jump_Full_Short")
		elif root_sm.has_node("LeapDodge"):
			character.animation_tree.change_immediate("LeapDodge")
