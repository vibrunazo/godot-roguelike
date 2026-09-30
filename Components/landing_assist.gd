## Aim assist for committed horizontal moves (dash, attack lunge, leap): keeps
## a probable mistake from dropping the character into a pit.
##
## Whoever starts the move calls steer() with its direction, its travel
## distance and the speed it hands over at when it ends. When that move would
## leave the character over a pit, steer() returns the nearest direction,
## rotated at most max_correction_angle degrees, whose move ends on ground.
## When the original landing is safe, or no direction within the limit is, it
## returns the direction unchanged: crossing a small gap stays possible, and a
## deliberate move straight into an abyss still falls.
##
## A landing is predicted by sweeping the character's own collision shape
## along the move (walls stop it, as they stop the move). Three points must
## stand on ground: where the move ends; where the character comes to rest
## when it lets go of the controls and brakes its exit speed; and where it
## would be after reaction_time more of moving on along the direction it
## asked for (the player still holding the stick). Each point is checked under
## the character's whole footprint, so a pit rim or a thin wall top never
## counts as ground. The path itself may cross pits freely.
class_name LandingAssist
extends Resource

## Number of ground probes spread on the footprint's circle, around the one
## under its center.
const FOOTPRINT_PROBES: int = 8

## Largest rotation, in degrees, the assist may apply to the move. Landings
## that can only be saved by turning further count as deliberate.
@export_range(0.0, 90.0, 0.5, "degrees") var max_correction_angle: float = 30.0
## Angle between the candidate directions tried on each side, in degrees.
## Smaller steps find a closer save at the cost of more physics queries.
@export_range(1.0, 45.0, 0.5, "degrees") var angle_step: float = 5.0
## Seconds of moving on at movement speed, along the originally asked
## direction, that must stay on ground after the move ends: the time a player
## still holding the direction gets to let go before walking into a pit.
@export var reaction_time: float = 0.2
## Size of the footprint that must stand on ground, as a fraction of the
## character's collision radius. Below 1.0 so a landing against a wall does
## not probe behind it.
@export_range(0.0, 1.0, 0.05) var footprint_scale: float = 0.75
## Deepest drop below the character's feet that still counts as ground, in
## meters (steps, ledges). Anything deeper is a pit.
@export var max_safe_drop: float = 1.5
## Height the path sweep is lifted by, in meters, so floor seams and steps up
## to this height do not stop the predicted move the way walls do.
@export var step_height: float = 0.3
## Obstacle hits the predicted move slides along before it counts as stopped.
@export var max_slides: int = 4


## Returns the direction the character should move along to travel distance
## meters, then brake from exit_speed (m/s, 0.0 when the move stops dead),
## without ending over a pit: direction itself when its landing is safe, else
## the closest rotation (within max_correction_angle) whose landing is, else
## direction unchanged. The result is horizontal and normalized.
func steer(character: Character, direction: Vector3, distance: float, exit_speed: float = 0.0) -> Vector3:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.is_zero_approx() or distance <= 0.0 or not character.is_inside_tree():
		return direction
	flat = flat.normalized()
	if is_safe_landing(character, flat, distance, exit_speed, flat):
		return flat
	var step: float = maxf(angle_step, 0.01)
	var angle: float = step
	while angle <= max_correction_angle + 0.001:
		for side: float in [1.0, -1.0]:
			var candidate: Vector3 = flat.rotated(Vector3.UP, deg_to_rad(angle * side))
			if is_safe_landing(character, candidate, distance, exit_speed, flat):
				return candidate
		angle += step
	return flat


## True when a move of distance meters along direction (horizontal, unit)
## leaves the character on ground: at the end of the move, at its resting
## point after braking from exit_speed, and after reaction_time of moving on
## along intent (horizontal, unit: the direction the move was asked for).
func is_safe_landing(character: Character, direction: Vector3, distance: float, exit_speed: float, intent: Vector3) -> bool:
	var lift: Vector3 = Vector3.UP * step_height
	var lifted: Transform3D = character.global_transform.translated(lift)
	var stop: Vector3 = _sweep(character, lifted, direction * distance)
	if not _is_supported(character, stop - lift):
		return false
	var move_speed: float = character.attribute_component.get_current(AttributeComponent.STAT_SPEED)
	if exit_speed > 0.0:
		var slide: float = character.get_braking_distance(direction * exit_speed, move_speed)
		var rest: Vector3 = _sweep(character, Transform3D(lifted.basis, stop), direction * slide)
		if not _is_supported(character, rest - lift):
			return false
	var moving_on: Vector3 = _sweep(character, Transform3D(lifted.basis, stop), intent * move_speed * reaction_time)
	return _is_supported(character, moving_on - lift)


## Where the character's shape ends up when moved by motion from transform
## from, sliding along obstacles on its collision mask the way move_and_slide
## does (the motion left at each hit continues along the obstacle, so it rides
## up slopes and low edges), for at most max_slides hits.
func _sweep(character: Character, from: Transform3D, motion: Vector3) -> Vector3:
	var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.from = from
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	var remaining: Vector3 = motion
	for slide: int in range(max_slides + 1):
		if remaining.is_zero_approx():
			break
		params.motion = remaining
		if not PhysicsServer3D.body_test_motion(character.get_rid(), params, result):
			params.from.origin += remaining
			break
		params.from.origin += result.get_travel()
		remaining = result.get_remainder().slide(result.get_collision_normal())
	return params.from.origin


## True when a character whose origin stands at position has ground under the
## center and the whole rim of its footprint (see footprint_scale).
func _is_supported(character: Character, position: Vector3) -> bool:
	if not _has_ground_below(character, position):
		return false
	var radius: float = character.get_body_size().x * footprint_scale
	if radius <= 0.0:
		return true
	for index: int in range(FOOTPRINT_PROBES):
		var offset: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, TAU * index / FOOTPRINT_PROBES) * radius
		if not _has_ground_below(character, position + offset):
			return false
	return true


## True when ground lies under a character whose origin stands at position,
## no more than max_safe_drop below its feet.
func _has_ground_below(character: Character, position: Vector3) -> bool:
	var feet: Vector3 = position - Vector3.UP * character.get_origin_height()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * step_height,
		feet - Vector3.UP * max_safe_drop,
		character.collision_mask,
		[character.get_rid()])
	query.hit_from_inside = true
	return not character.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
