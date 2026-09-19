## Actor component managing equipped gear items, consumables, active effect tracking, and item purchases.
class_name EquipmentComponent
extends Node

const ItemResource = preload("res://Items/item_resource.gd")
const GearItemResource = preload("res://Items/gear_item_resource.gd")
const ConsumableItemResource = preload("res://Items/consumable_item_resource.gd")

## Emitted when a gear item is equipped.
signal gear_equipped(gear: GearItemResource)
## Emitted when a gear item is unequipped.
signal gear_unequipped(gear: GearItemResource)
## Emitted when a consumable item is used.
signal item_consumed(consumable: ConsumableItemResource)
## Emitted when any item is applied.
signal item_applied(item: ItemResource)

## Reference to the character owning this equipment component.
var character: Character = null

## Array of currently equipped gear resources.
var equipped_gear: Array[GearItemResource] = []

## Maps GearItemResource -> Array[StringName] of active GameplayEffect IDs on AttributeComponent.
var _gear_effect_ids: Dictionary = {}

## Maps GearItemResource -> Node3D visual instance mounted to the character.
var _gear_visuals: Dictionary = {}

## Maps item identifier -> int count of times purchased this run.
var _purchase_counts: Dictionary = {}


func _ready() -> void:
	if character == null:
		character = get_parent() as Character


## Applies an item to the character, routing to equip or consume depending on item type.
func apply_item(item: ItemResource) -> bool:
	if item == null or character == null:
		return false

	if item is GearItemResource:
		return equip_gear(item as GearItemResource)
	elif item is ConsumableItemResource:
		return use_consumable(item as ConsumableItemResource)

	var success: bool = item.apply(character)
	if success:
		item_applied.emit(item)
	return success


## Equips a gear item onto the character, tracking its effects and mounting visuals.
func equip_gear(gear: GearItemResource) -> bool:
	if gear == null or character == null:
		return false

	var equip_data: Dictionary = gear.equip(character)
	var new_effect_ids: Array[StringName] = equip_data.get("effect_ids", []) as Array[StringName]
	var visual_node: Node3D = equip_data.get("visual", null) as Node3D

	if _gear_effect_ids.has(gear):
		var existing_ids: Array[StringName] = _gear_effect_ids[gear] as Array[StringName]
		existing_ids.append_array(new_effect_ids)
	else:
		_gear_effect_ids[gear] = new_effect_ids
		if visual_node != null:
			_gear_visuals[gear] = visual_node
		equipped_gear.append(gear)

	gear_equipped.emit(gear)
	item_applied.emit(gear)
	return true


## Unequips a gear item, removing all associated GameplayEffects and freeing its visual node.
func unequip_gear(gear: GearItemResource) -> bool:
	if gear == null or character == null or not is_equipped(gear):
		return false

	var effect_ids: Array[StringName] = _gear_effect_ids.get(gear, []) as Array[StringName]
	var visual_node: Node3D = _gear_visuals.get(gear, null) as Node3D

	gear.unequip(character, effect_ids, visual_node)

	_gear_effect_ids.erase(gear)
	_gear_visuals.erase(gear)
	equipped_gear.erase(gear)

	gear_unequipped.emit(gear)
	return true


## Returns true if the specified item is currently equipped gear.
func is_equipped(item: ItemResource) -> bool:
	if item is GearItemResource:
		return equipped_gear.has(item as GearItemResource)
	return false


## Uses a consumable item on the character.
func use_consumable(consumable: ConsumableItemResource) -> bool:
	if consumable == null or character == null:
		return false

	var success: bool = consumable.consume(character)
	if success:
		item_consumed.emit(consumable)
		item_applied.emit(consumable)
	return success


## Returns true if the item can be purchased given current gold balance and stock limits.
func can_purchase(item: ItemResource) -> bool:
	if item == null:
		return false

	if item.max_purchases > 0 and get_purchase_count(item) >= item.max_purchases:
		return false

	if ProgressionState != null and not ProgressionState.has_gold(item.cost):
		return false

	return true


## Returns the number of times this item has been purchased during the current run.
func get_purchase_count(item: ItemResource) -> int:
	if item == null:
		return 0
	var key: StringName = _get_item_key(item)
	return _purchase_counts.get(key, 0)


## Records a purchase of the specified item, incrementing its run purchase count.
func record_purchase(item: ItemResource) -> void:
	if item == null:
		return
	var key: StringName = _get_item_key(item)
	_purchase_counts[key] = _purchase_counts.get(key, 0) + 1


func _get_item_key(item: ItemResource) -> StringName:
	if not item.id.is_empty():
		return item.id
	if not item.resource_path.is_empty():
		return StringName(item.resource_path)
	return StringName(item.title)
