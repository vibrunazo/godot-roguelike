## Tells how long a walk has been stalled: how many seconds of physics time
## the walker has gone without moving min_distance (on the ground plane) from
## where it last made progress. Any AI state that walks to a point owns one:
## reset() when the walk starts (and while the walk is paused, e.g. the body is
## stunned), update() every physics tick, and give up past its own limit.
## Moving around an obstacle counts as progress; jittering in place against a
## wall or a crowd does not.
class_name BlockedWalkDetector
extends RefCounted

## Where the walker last made progress.
var _anchor: Vector3 = Vector3.ZERO
## Seconds since then.
var _stalled_time: float = 0.0


## Starts counting from position, with no stalled time.
func reset(position: Vector3) -> void:
	_anchor = position
	_stalled_time = 0.0


## Advances by delta seconds with the walker at position and returns how long
## it has been stalled. Moving min_distance from the last progress point
## restarts the count there.
func update(position: Vector3, delta: float, min_distance: float) -> float:
	if Vector2(position.x - _anchor.x, position.z - _anchor.z).length() >= min_distance:
		reset(position)
		return 0.0
	_stalled_time += delta
	return _stalled_time
