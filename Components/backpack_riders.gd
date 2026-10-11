## The riders a backpack boss carries: one big character with enemies riding
## in backpacks on its back (each a BackpackRider scene seated in a backpack).
## While they are aboard it drives them every physics tick: each turns toward
## the carrier's nearest foe and attacks it within its own range band on its
## own cooldown. Whether they are aboard is the carrier's rider_tag, granted
## by rider_effect, which the carrier starts with
## (AttributeComponent.initial_effects): ThrowRidersAttack sends them off
## (unboard_riders()), SummonRidersAttack brings them back (board_riders()),
## and both gate on the tag. A new backpack boss picks its riders by the
## rider scenes in its backpacks; what each rider does is that scene's data.
class_name BackpackRiders
extends Node

## The character carrying the riders.
@export var character: Character
## The riders in the character's backpacks.
@export var riders: Array[BackpackRider] = []
## Effect that puts the riders aboard by granting rider_tag.
@export var rider_effect: GameplayEffect
## Gameplay tag meaning the riders are aboard (granted by rider_effect; the
## throw and summon attacks gate on it).
@export var rider_tag: StringName = &"has_riders"


func _ready() -> void:
	if character == null:
		push_error("%s: character is not set." % name)
		return
	if rider_effect == null:
		push_error("%s: rider_effect is not set." % name)
	if riders.is_empty():
		push_error("%s: riders is empty." % name)
	for rider: BackpackRider in riders:
		if rider == null:
			push_error("%s: a rider is not set." % name)
			continue
		rider.carrier = character
	character.attribute_component.tag_added.connect(_on_tag_changed.bind(true))
	character.attribute_component.tag_removed.connect(_on_tag_changed.bind(false))
	_show_riders(has_riders())


func _physics_process(delta: float) -> void:
	if not has_riders() or not character.is_inside_tree() or not character.is_alive():
		return
	var foe: Character = character.get_nearest_target()
	for rider: BackpackRider in riders:
		if rider != null:
			rider.engage(foe, delta)


## Whether the riders are aboard (the carrier has rider_tag).
func has_riders() -> bool:
	return character != null and character.has_tag(rider_tag)


## Puts the riders aboard: applies rider_effect, which grants rider_tag.
func board_riders() -> void:
	character.attribute_component.apply_effect(rider_effect)


## Sends the riders off: removes rider_effect, and with it rider_tag.
func unboard_riders() -> void:
	character.attribute_component.remove_effect(StringName(rider_effect.effect_name))


## The point on the navigation mesh closest to point, where a rider leaving
## the backpack lands so the enemy it becomes can walk (point itself when the
## level has no navigation mesh, or the map has not synced yet).
func landing_point(point: Vector3) -> Vector3:
	var nav_map: RID = character.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return point
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, point)
	return point if closest.is_zero_approx() else closest


func _on_tag_changed(tag: StringName, aboard: bool) -> void:
	if tag == rider_tag:
		_show_riders(aboard)


func _show_riders(aboard: bool) -> void:
	for rider: BackpackRider in riders:
		if rider != null:
			rider.set_aboard(aboard)
