## Equippable gear item resource (weapons, boots, amulets, armor, stat upgrades).
## Automatically tracks and applies GameplayEffects on equip, and removes them on unequip.
## Tool-enabled to match ItemResource so editor previews get real instances.
@tool
class_name GearItemResource
extends ItemResource

@export_group("Gear Configuration")
## Optional slot category or equipment tag (e.g. &"weapon", &"feet", &"chest", &"relic").
@export var slot_tag: StringName = &"gear"
@export_group("Passive Abilities")
## Passive scenes (PassiveAbility root nodes) granted while this gear is
## equipped: the reusable "upgrade one ability's behavior" mechanism. Each
## scene is instanced onto the character's PassiveAbilityComponent on equip
## and revoked again on unequip (e.g. a passive detonating at dash end).
@export var granted_passives: Array[PackedScene] = []


func _init() -> void:
	max_purchases = 3


## Equips this gear onto the character. Returns a Dictionary containing:
## - "effect_ids": Array[StringName] of active modifier instance IDs on AttributeComponent
## - "visual": Node3D (or null) of the instanced visual scene mounted to the rig
func equip(character: Character) -> Dictionary:
	var result: Dictionary = {
		"effect_ids": [] as Array[StringName],
		"visual": null,
		"passives": [] as Array[PassiveAbility]
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

	# Grant passive ability scenes to the character's passive component
	var passive_nodes: Array[PassiveAbility] = []
	if character.passive_ability_component != null:
		for passive_scene: PackedScene in granted_passives:
			if passive_scene == null:
				continue
			var granted: PassiveAbility = character.passive_ability_component.add_passive(passive_scene)
			if granted != null:
				passive_nodes.append(granted)
	result["passives"] = passive_nodes

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


## Unequips this gear: removes all active GameplayEffects from AttributeComponent,
## revokes every passive this gear granted, and frees the visual node.
func unequip(character: Character, active_effect_ids: Array[StringName], visual_node: Node3D, active_passives: Array[PassiveAbility]) -> void:
	if character != null and is_instance_valid(character) and character.attribute_component != null:
		var attrs: AttributeComponent = character.attribute_component
		for eff_id: StringName in active_effect_ids:
			attrs.remove_effect(eff_id)

	if character != null and is_instance_valid(character) and character.passive_ability_component != null:
		for passive: PassiveAbility in active_passives:
			character.passive_ability_component.remove_passive(passive)

	if visual_node != null and is_instance_valid(visual_node):
		visual_node.queue_free()

	_on_unequipped(character)


## Extends the base stat summary with the passives this gear grants, so shop
## cards and the inventory list behavior upgrades without hand-written text.
func get_stat_summary(character: Character) -> String:
	var base: String = super.get_stat_summary(character)
	var lines: Array[String] = []
	for passive_scene: PackedScene in granted_passives:
		if passive_scene == null:
			continue
		lines.append("Grants: [color='c9a6ff']%s[/color]" % _passive_display_name(passive_scene))
	if lines.is_empty():
		return base
	if base.is_empty():
		return "\n".join(lines)
	return base + "\n" + "\n".join(lines)


## Best-effort UI label for a granted passive scene: the root PassiveAbility's
## display_name when set, otherwise the scene filename made readable.
func _passive_display_name(scene: PackedScene) -> String:
	var instance: Node = scene.instantiate()
	if instance == null:
		return scene.resource_path.get_file().get_basename().replace("_", " ").capitalize()
	var label: String = ""
	if instance is PassiveAbility:
		label = (instance as PassiveAbility).display_name
	instance.free()
	if label.is_empty():
		label = scene.resource_path.get_file().get_basename().replace("_", " ").capitalize()
	return label


## Optional virtual hook called when gear is equipped.
func _on_equipped(_character: Character) -> void:
	pass


## Optional virtual hook called when gear is unequipped.
func _on_unequipped(_character: Character) -> void:
	pass
