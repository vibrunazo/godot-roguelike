## Enemy-only: when the enemy is defeated, awards the run gold and rolls its
## item drops, both from its EnemyResource (Character.enemy_resource, which
## waves set; an enemy spawned any other way is looked up in
## GlobalVars.enemies by its scene). An enemy with no registered archetype
## awards and drops nothing.
## A drop lands as an ItemPickup on the navmesh point closest to where the
## enemy fell (so one that died over a pit still drops within reach), parented
## to the level. Each LootDrop rolls its chance on its own, and its item drops
## only when the run may offer it to the player (ProgressionState.can_drop():
## the player holds none of what it teaches) and no pickup of it already lies
## in the level.
class_name LootComponent
extends Node

## Emitted for each item this enemy dropped.
signal item_dropped(pickup: ItemPickup)

## The enemy whose defeat awards the gold and drops the items.
@export var character: Character
## Collision mask of the level floor dropped items rest on.
@export_flags_3d_physics var floor_mask: int = 1


func _ready() -> void:
	if character == null:
		push_error("%s: character is not set." % name)
		return
	character.defeat.connect(_on_defeat)


## The enemy's archetype: its own enemy_resource, else the registered one for
## its scene, else null.
func get_enemy_resource() -> EnemyResource:
	if character.enemy_resource != null:
		return character.enemy_resource
	return GlobalVars.get_enemy_resource_for_path(character.scene_file_path)


## The gold this enemy is worth (0 without a registered archetype).
func gold_drop() -> int:
	var resource: EnemyResource = get_enemy_resource()
	return resource.gold_drop if resource != null else 0


## Rolls every item drop of the enemy's archetype and drops the winners that
## may drop now. Returns the pickups placed.
func drop_items() -> Array[ItemPickup]:
	var dropped: Array[ItemPickup] = []
	var resource: EnemyResource = get_enemy_resource()
	if resource == null or not character.is_inside_tree():
		return dropped
	for drop: LootDrop in resource.item_drops:
		if drop == null or drop.item == null or randf() >= drop.chance:
			continue
		if not can_drop(drop.item):
			continue
		var pickup: ItemPickup = _drop(drop.item)
		if pickup != null:
			dropped.append(pickup)
			item_dropped.emit(pickup)
	return dropped


## Whether item may drop now: it can lie in a level, the run may offer it to
## the player (ProgressionState.can_drop()) and no pickup of it lies in the
## level yet.
func can_drop(item: ItemResource) -> bool:
	return item.world_visual != null and ProgressionState.can_drop(item) and not ItemPickup.is_lying_in(get_tree(), item)


func _on_defeat() -> void:
	ProgressionState.add_gold(gold_drop())
	drop_items()


## Places a pickup of item where the enemy fell, in the level.
func _drop(item: ItemResource) -> ItemPickup:
	var pickup: ItemPickup = (GlobalVars.item_pickup_scene as PackedScene).instantiate() as ItemPickup
	if pickup == null:
		push_error("LootComponent: GlobalVars.item_pickup_scene must have an ItemPickup root.")
		return null
	pickup.item = item
	var at: Vector3 = _drop_position()
	VfxManager.spawn_world_entity(pickup)
	pickup.global_position = at
	return pickup


## The floor under the navmesh point closest to the enemy (under the enemy
## itself when its navigation map has no navmesh).
func _drop_position() -> Vector3:
	var at: Vector3 = character.global_position
	var nav_map: RID = character.navigation_agent_3d.get_navigation_map() if character.navigation_agent_3d != null else character.get_world_3d().navigation_map
	if NavigationServer3D.map_get_closest_point_owner(nav_map, at).is_valid():
		at = NavigationServer3D.map_get_closest_point(nav_map, at)
	return ItemPickup.floor_below(character.get_world_3d(), at, floor_mask)
