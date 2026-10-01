## Navmesh rebuilds around destructible props (NavmeshRebuilder):
## - a rebuild carves out the props standing under the region; when one
##   breaks, the next rebuild opens its spot and keeps the others carved,
## - a prop placed after the level started is tracked like the placed ones,
##   and one that breaks once the interval is over is rebuilt out at once,
## - rebuilds never start closer together than min_rebuild_interval, and props
##   that break in between are folded into the next rebuild.
## The interval is test-owned; the arena stands in for a level.
extends "res://test/lib/test_suite.gd"

const BARREL_SCENE: PackedScene = preload("res://Levels/Decorators/explosive_barrel.tscn")
## Test-owned minimum time between rebuild starts, in seconds.
const TEST_INTERVAL: float = 3.0
## Barrel spots, far enough apart that one barrel's hole never covers another.
const SPOTS: Array[Vector3] = [Vector3(-4.0, 0.0, 0.0), Vector3(0.0, 0.0, 4.0), Vector3(4.0, 0.0, 0.0), Vector3(0.0, 0.0, -4.0)]
## How close the navmesh must come to a spot for it to count as walkable.
const WALKABLE_TOLERANCE: float = 0.1

var _arena: Node3D
var _region: NavigationRegion3D
var _floor_top: float


func before_each() -> void:
	_arena = load_arena()
	_region = _arena.get_node("NavigationRegion3D") as NavigationRegion3D
	_floor_top = arena_floor_top(_arena)
	await wait_for_navigation(_arena)


func test_a_broken_barrel_opens_its_spot_and_the_others_stay_carved() -> void:
	var broken: Destructible = _spawn_barrel(SPOTS[0])
	var standing: Destructible = _spawn_barrel(SPOTS[1])
	var rebuilder: NavmeshRebuilder = _add_rebuilder()
	rebuilder.request_rebuild.call_deferred()
	if not await wait_until_threaded(func() -> bool: return not _walkable(broken) and not _walkable(standing), "a rebuild should carve out the barrels under the region"):
		return
	var standing_position: Vector3 = standing.global_position
	_break(broken)
	await wait_until_threaded(func() -> bool: return _walkable_at(SPOTS[0]), "the next rebuild should open the broken barrel's spot")
	check(not _walkable_at(standing_position), "a standing barrel should stay carved out")
	check_no_engine_errors("rebuilding the navmesh should raise no engine errors")


func test_a_barrel_placed_after_the_level_started_is_tracked() -> void:
	var rebuilder: NavmeshRebuilder = _add_rebuilder()
	await wait_physics_frames(1)
	var barrel: Destructible = _spawn_barrel(SPOTS[2])
	await wait_physics_frames(1)
	var start_frame: Array[int] = [0]
	rebuilder.rebuild_started.connect(func() -> void: start_frame[0] = Engine.get_physics_frames(), CONNECT_ONE_SHOT)
	rebuilder.request_rebuild()
	if not await wait_until_threaded(func() -> bool: return not _walkable(barrel), "a rebuild should carve out a barrel placed at runtime"):
		return
	# Broken once the interval is over, the barrel starts a rebuild at once,
	# while it is still in the tree.
	var interval_frames: int = ceili(TEST_INTERVAL * Engine.physics_ticks_per_second)
	await wait_until(func() -> bool: return Engine.get_physics_frames() - start_frame[0] >= interval_frames, "the rebuild interval should pass", interval_frames * 2)
	_break(barrel)
	await wait_until_threaded(func() -> bool: return _walkable_at(SPOTS[2]), "breaking the runtime barrel should open its spot")


func test_rebuilds_are_spaced_by_the_interval_and_fold_breaks_together() -> void:
	var barrels: Array[Destructible] = []
	for spot: Vector3 in SPOTS.slice(0, 3):
		barrels.append(_spawn_barrel(spot))
	var rebuilder: NavmeshRebuilder = _add_rebuilder()
	var starts: Array[int] = []
	rebuilder.rebuild_started.connect(func() -> void: starts.append(Engine.get_physics_frames()))
	rebuilder.request_rebuild.call_deferred()
	if not await wait_until_threaded(func() -> bool: return not barrels.any(_walkable), "the first rebuild should carve out the barrels"):
		return
	# Every break lands inside the first rebuild's interval.
	for barrel: Destructible in barrels:
		_break(barrel)
		await wait_physics_frames(1)
	await wait_until_threaded(func() -> bool: return SPOTS.slice(0, 3).all(_walkable_at), "the rebuild after the interval should open every broken spot")
	check_eq(starts.size(), 2, "breaks inside one interval should fold into a single rebuild")
	var min_gap: int = floori(TEST_INTERVAL * Engine.physics_ticks_per_second)
	for i: int in range(1, starts.size()):
		check(starts[i] - starts[i - 1] >= min_gap, "rebuilds should start at least %d physics frames apart (got %d)" % [min_gap, starts[i] - starts[i - 1]])


func _add_rebuilder() -> NavmeshRebuilder:
	var rebuilder: NavmeshRebuilder = NavmeshRebuilder.new()
	rebuilder.region = _region
	rebuilder.min_rebuild_interval = TEST_INTERVAL
	_arena.add_child(rebuilder)
	return rebuilder


func _spawn_barrel(spot: Vector3) -> Destructible:
	var barrel: Destructible = spawn(BARREL_SCENE, _region, Vector3(spot.x, _floor_top, spot.z)) as Destructible
	barrel.break_payload = null
	barrel.fuse_time = 0.0
	return barrel


## Empties the barrel's health through its Hurtbox, which breaks it.
func _break(barrel: Destructible) -> void:
	var health: float = barrel.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	(barrel.get_node("Hurtbox") as Hurtbox).receive_hit(health, Vector3.ZERO)


func _walkable(barrel: Destructible) -> bool:
	return _walkable_at(barrel.global_position)


## Whether the navigation map has walkable ground right at spot (in x and z).
func _walkable_at(spot: Vector3) -> bool:
	var probe: Vector3 = Vector3(spot.x, _floor_top, spot.z)
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(_arena.get_world_3d().navigation_map, probe)
	return Vector2(closest.x - probe.x, closest.z - probe.z).length() <= WALKABLE_TOLERANCE
