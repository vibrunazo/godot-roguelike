## Level 13: the real player, driven only by movement actions, climbs both
## stairways to the upper floor and comes back down. No teleport, jump,
## velocity override or stand-in collision. The authored spawn must also be
## clear of geometry.
extends "res://test/lib/test_suite.gd"

const LEVEL_SCENE: PackedScene = preload("res://Levels/level_13.tscn")
## Route from the spawn: up the north flight, back down, then up and down the
## south flight. y is the floor height above the spawn floor.
const ROUTE: Array[Vector3] = [Vector3(-6, 0, 2), Vector3(-6, 0, -6), Vector3(6, 2, -6), Vector3(-6, 0, -6), Vector3(-6, 0, 10), Vector3(6, 2, 10), Vector3(-6, 0, 10)]
## How close counts as arrived, horizontally and in height.
const ARRIVE_DISTANCE: float = 0.25
const ARRIVE_HEIGHT: float = 0.2
## Physics ticks allowed per leg of the route.
const LEG_FRAMES: int = 360
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back"]

var _player: Character
var _rest_height: float = 0.0


func after_each() -> void:
	_release_moves()


func test_the_player_climbs_and_descends_both_stairways() -> void:
	var level: Node3D = spawn(LEVEL_SCENE) as Node3D
	(level.get_node("WaveObjective") as WaveObjective).stop_spawning()
	_player = level.get_node("Player") as Character
	# Record the authored collider pose before physics can push an
	# overlapping spawn out; shrink it slightly to ignore floor contact.
	var collider: CollisionShape3D = _player.get_node("CollisionShape3D") as CollisionShape3D
	var spawn_pose: Transform3D = collider.global_transform
	var spawn_shape: CapsuleShape3D = collider.shape.duplicate() as CapsuleShape3D
	spawn_shape.radius *= 0.95
	spawn_shape.height *= 0.95
	var nav_map: RID = level.get_world_3d().navigation_map
	if not await wait_until(func() -> bool: return NavigationServer3D.map_get_iteration_id(nav_map) != 0 and not NavigationServer3D.map_get_closest_point(nav_map, _player.global_position).is_zero_approx(), "the level navmesh should register", 120):
		return
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = spawn_shape
	query.transform = spawn_pose
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	var overlaps: Array[Dictionary] = level.get_world_3d().direct_space_state.intersect_shape(query)
	check(overlaps.is_empty(), "the authored spawn should be clear of geometry (overlaps: %s)" % [overlaps])
	if not await wait_until(func() -> bool: return _player.is_on_floor(), "the player should land at the spawn"):
		return
	_rest_height = _player.global_position.y
	for target: Vector3 in ROUTE:
		if not await _walk_to(target):
			return


## Holds the movement actions toward the target (in camera space, as a player
## would) until the player arrives there on the floor.
func _walk_to(target: Vector3) -> bool:
	for frame: int in range(LEG_FRAMES):
		var offset: Vector3 = target - _player.global_position
		offset.y = 0.0
		_release_moves()
		if offset.length() < ARRIVE_DISTANCE and _player.is_on_floor():
			return check(absf(_player.global_position.y - _rest_height - target.y) < ARRIVE_HEIGHT, "the player should reach %s at floor height %.1f (at %s)" % [target, target.y, _player.global_position])
		var direction: Vector3 = offset.normalized()
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			direction = direction.rotated(Vector3.UP, -camera.global_rotation.y)
		Input.action_press(&"move_right" if direction.x > 0.0 else &"move_left", absf(direction.x))
		Input.action_press(&"move_back" if direction.z > 0.0 else &"move_forward", absf(direction.z))
		await get_tree().physics_frame
	_release_moves()
	return fail("the player should walk to %s but got stuck at %s" % [target, _player.global_position])


func _release_moves() -> void:
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)
