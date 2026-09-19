## Equippable gear item resource (weapons, boots, amulets, armor, stat upgrades).
## Automatically tracks and applies GameplayEffects on equip, and removes them on unequip.
class_name GearItemResource
extends ItemResource

@export_group("Gear Configuration")
## Optional slot category or equipment tag (e.g. &"weapon", &"feet", &"chest", &"relic").
@export var slot_tag: StringName = &"gear"


func _init() -> void:
	max_purchases = 3


## Equips this gear onto the character. Returns a Dictionary containing:
## - "effect_ids": Array[StringName] of active modifier instance IDs on AttributeComponent
## - "visual": Node3D (or null) of the instanced visual scene mounted to the rig
func equip(character: Character) -> Dictionary:
	var result: Dictionary = {
		"effect_ids": [] as Array[StringName],
		"visual": null
	}
	if character == null or not is_instance_valid(character):
		return result

	# Apply base instant effects (healing, instant damage)
	apply(character)

	# Apply persistent GameplayEffects to AttributeComponent
	var attrs: AttributeComponent = character.attribute_component
	if attrs != null:
		var ids: Array[StringName] = []
		for eff: GameplayEffect in gameplay_effects:
			if eff != null:
				var inst_id: StringName = attrs.apply_effect(eff)
				if not inst_id.is_empty():
					ids.append(inst_id)
		result["effect_ids"] = ids

	# Instantiate and mount 3D visual if present
	if visual_scene != null:
		var visual_inst: Node = visual_scene.instantiate()
		if visual_inst is ItemVisual:
			(visual_inst as ItemVisual).attach_to_character(character)
			result["visual"] = visual_inst
		elif visual_inst is Node3D:
			if character.mesh_mount != null:
				character.mesh_mount.add_child(visual_inst)
			else:
				character.add_child(visual_inst)
			result["visual"] = visual_inst

	_on_equipped(character)
	return result


## Unequips this gear: removes all active GameplayEffects from AttributeComponent and frees the visual node.
func unequip(character: Character, active_effect_ids: Array[StringName], visual_node: Node3D) -> void:
	if character != null and is_instance_valid(character) and character.attribute_component != null:
		var attrs: AttributeComponent = character.attribute_component
		for eff_id: StringName in active_effect_ids:
			attrs.remove_effect(eff_id)

	if visual_node != null and is_instance_valid(visual_node):
		visual_node.queue_free()

	_on_unequipped(character)


## Optional virtual hook called when gear is equipped.
func _on_equipped(_character: Character) -> void:
	pass


## Optional virtual hook called when gear is unequipped.
func _on_unequipped(_character: Character) -> void:
	pass
