## Where a character aims: a point on the floor, seen along a line of sight.
## The player's line of sight is the camera ray through the mouse cursor and
## its floor point is where that ray hits the level, on whatever floor the
## cursor is over; AI and auto-aim aim at a character, seen from straight
## above. Actions resolve their own direction from it at the moment they
## need one (AbilityCastState: from the cast origin, at release), so the aim
## stays right while the caster moves, jumps or turns.
## Immutable: build one with from_sight(), at() or toward().
class_name AimTarget
extends RefCounted

## Horizontal distance, in meters, of the stand-in point toward() aims at: far
## enough that the direction from anywhere on the caster's body is the same.
const DIRECTION_AIM_DISTANCE: float = 1000.0

## The aimed point on the floor (or on whatever level geometry the line of
## sight hit).
var floor_point: Vector3 = Vector3.ZERO
## A point on the line of sight.
var sight_origin: Vector3 = Vector3.ZERO
## The line of sight's direction (unit length), toward the floor point.
var sight_direction: Vector3 = Vector3.DOWN
## False when only a direction was aimed (toward()): floor_point is then a
## stand-in far along it, not a place, and ground-targeted actions pick their
## own landing point.
var has_point: bool = true


## Aims at floor_point along the line of sight from origin in direction (a
## camera ray through the cursor).
static func from_sight(origin: Vector3, direction: Vector3, point: Vector3) -> AimTarget:
	var aim: AimTarget = AimTarget.new()
	aim.floor_point = point
	aim.sight_origin = origin
	aim.sight_direction = direction.normalized()
	return aim


## Aims at point (a character's feet), seen from straight above.
static func at(point: Vector3) -> AimTarget:
	var aim: AimTarget = AimTarget.new()
	aim.floor_point = point
	aim.sight_origin = point + Vector3.UP
	aim.sight_direction = Vector3.DOWN
	return aim


## Aims at a target node: a character's feet, any other node's position.
static func at_node(target: Node3D) -> AimTarget:
	if target is Character:
		return AimTarget.at((target as Character).get_feet_position())
	return AimTarget.at(target.global_position)


## Aims along the horizontal direction from from_point, at no place in
## particular (an order that only gives a direction).
static func toward(from_point: Vector3, direction: Vector3) -> AimTarget:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	var aim: AimTarget = AimTarget.at(from_point + flat * DIRECTION_AIM_DISTANCE)
	aim.has_point = false
	return aim


## The point on the line of sight at world height y: what the aimer sees at
## that height. A vertical line of sight gives the point above (or below) the
## floor point.
func point_at_y(y: float) -> Vector3:
	if absf(sight_direction.y) < 0.0001:
		return Vector3(floor_point.x, y, floor_point.z)
	var t: float = (y - sight_origin.y) / sight_direction.y
	return sight_origin + sight_direction * t


## The point on the line of sight height meters above the floor point.
func point_at_height(height: float) -> Vector3:
	return point_at_y(floor_point.y + height)


## The horizontal direction (unit length) from from_point toward what the aimer
## sees at from_point's height; zero when that point is right above or below.
func flat_direction_from(from_point: Vector3) -> Vector3:
	var to_point: Vector3 = point_at_y(from_point.y) - from_point
	to_point.y = 0.0
	return to_point.normalized() if not to_point.is_zero_approx() else Vector3.ZERO
