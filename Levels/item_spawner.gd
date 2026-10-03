## Drops items for the player to find when a level starts: count random
## picks from GlobalVars.level_items that the run may still offer
## (ProgressionState.is_item_available(), the rule the shop deals by) and that
## have a world visual. Each lies offset_distance ahead of where the player
## spawned (trying other bearings around it when that spot is off the navmesh
## or unreachable), snapped onto the navmesh once the navigation map is ready,
## so no level needs a hand-placed spot.
class_name ItemSpawner
extends Node3D

## Emitted once the level's items are placed (possibly none).
signal items_spawned(pickups: Array[ItemPickup])

## The level's player; items are placed around where it spawned.
@export var player: Character
## The level's navigation region. Items wait until the navigation map serves
## this region's navmesh (the map outlives levels, so an older level's region
## may still be in it for a frame).
@export var navigation_region: NavigationRegion3D
## How many items to drop.
@export var count: int = 1
## Distance from the player's spawn to an item, in meters.
@export var offset_distance: float = 3.0
## How far a candidate spot may move when snapped onto the navmesh, in meters,
## before another bearing is tried (a spot inside a wall or over a pit).
@export var max_snap_distance: float = 0.75
## Bearings tried around the player, starting ahead of it.
@export var bearing_count: int = 8
## Physics frames to wait for the navigation map before giving up.
@export var navigation_wait_frames: int = 120
## Collision mask of the level floor items rest on.
@export_flags_3d_physics var floor_mask: int = 1

## The pickups this spawner placed.
var pickups: Array[ItemPickup] = []


func _ready() -> void:
	if player == null or navigation_region == null:
		push_error("ItemSpawner: player and navigation_region must be set.")
		return
	_spawn_items.call_deferred()


func _spawn_items() -> void:
	var items: Array[ItemResource] = _pick_items()
	if items.is_empty():
		items_spawned.emit(pickups)
		return
	var nav_map: RID = navigation_region.get_navigation_map()
	var origin: Vector3 = player.global_position
	var frames: int = 0
	# Ready once the map's closest point to the player lies on this level's
	# region: the map then serves this region's navmesh.
	while NavigationServer3D.map_get_closest_point_owner(nav_map, origin) != navigation_region.get_rid():
		frames += 1
		if frames > navigation_wait_frames:
			push_error("ItemSpawner: the navigation map never served this level's navmesh; no items placed.")
			return
		await get_tree().physics_frame
	if not is_inside_tree() or not is_instance_valid(player):
		return
	var start: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, origin)
	var spots: Array[Vector3] = _find_spots(nav_map, start, items.size())
	for index: int in spots.size():
		var pickup: ItemPickup = (GlobalVars.item_pickup_scene as PackedScene).instantiate() as ItemPickup
		pickup.item = items[index]
		# Under the spawner, so the pickups leave with their level.
		add_child(pickup)
		pickup.global_position = ItemPickup.floor_below(get_world_3d(), spots[index], floor_mask)
		pickups.append(pickup)
	items_spawned.emit(pickups)


## Up to count distinct random items the run may still offer.
func _pick_items() -> Array[ItemResource]:
	var options: Array[ItemResource] = []
	for item: ItemResource in GlobalVars.level_items:
		if item != null and item.world_visual != null and ProgressionState.is_item_available(item) and item.can_apply(player):
			options.append(item)
	options.shuffle()
	return options.slice(0, maxi(count, 0))


## Reachable navmesh spots around start, one per needed item, starting ahead
## of the player's facing.
func _find_spots(nav_map: RID, start: Vector3, needed: int) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var forward: Vector3 = player.mesh_mount.global_basis.z if player.mesh_mount != null else Vector3.BACK
	forward.y = 0.0
	forward = forward.normalized() if not forward.is_zero_approx() else Vector3.BACK
	for bearing: int in maxi(bearing_count, 1):
		if spots.size() >= needed:
			break
		var direction: Vector3 = forward.rotated(Vector3.UP, TAU * float(bearing) / float(maxi(bearing_count, 1)))
		var wanted: Vector3 = start + direction * offset_distance
		var snapped_point: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, wanted)
		if Vector2(snapped_point.x - wanted.x, snapped_point.z - wanted.z).length() > max_snap_distance:
			continue
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start, snapped_point, true)
		if path.is_empty() or path[path.size() - 1].distance_to(snapped_point) > max_snap_distance:
			continue
		spots.append(snapped_point)
	if spots.size() < needed:
		push_warning("ItemSpawner: found %d of %d reachable spots around the player." % [spots.size(), needed])
	return spots
