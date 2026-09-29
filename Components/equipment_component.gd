## Actor component managing equipped gear items, consumables and their active
## effects. Purchases are run state (ProgressionState), not the character's.
class_name EquipmentComponent
extends Node

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

## Maps GearItemResource -> Array[PassiveAbility] granted by that gear.
var _gear_passives: Dictionary = {}



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


## Equips a gear item onto the character: its instant effects (healing, ...)
## once, then its lasting part (see restore_gear()).
func equip_gear(gear: GearItemResource) -> bool:
	if gear == null or character == null:
		return false
	gear.apply(character)
	return restore_gear(gear)


## Attaches a gear's lasting part (effects, passives, visual) without its
## instant effects: how a respawned player gets back gear it already had.
func restore_gear(gear: GearItemResource) -> bool:
	if gear == null or character == null:
		return false

	var equip_data: Dictionary = gear.attach(character)
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

	# Track granted passive instances per gear for revoke on unequip.
	var new_passives: Array[PassiveAbility] = equip_data.get("passives", []) as Array[PassiveAbility]
	if _gear_passives.has(gear):
		var existing_passives: Array[PassiveAbility] = _gear_passives[gear] as Array[PassiveAbility]
		existing_passives.append_array(new_passives)
	else:
		_gear_passives[gear] = new_passives

	gear_equipped.emit(gear)
	item_applied.emit(gear)
	return true


## Unequips a gear item, removing all associated GameplayEffects and freeing its visual node.
func unequip_gear(gear: GearItemResource) -> bool:
	if gear == null or character == null or not is_equipped(gear):
		return false

	var effect_ids: Array[StringName] = _gear_effect_ids.get(gear, []) as Array[StringName]
	var visual_node: Node3D = _gear_visuals.get(gear, null) as Node3D
	var passive_nodes: Array[PassiveAbility] = _gear_passives.get(gear, []) as Array[PassiveAbility]

	gear.unequip(character, effect_ids, visual_node, passive_nodes)

	_gear_effect_ids.erase(gear)
	_gear_visuals.erase(gear)
	_gear_passives.erase(gear)
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
