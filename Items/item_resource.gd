## Base data resource defining an item's metadata, economy, gameplay effects, and visual scene.
## Standard items are 100% data-driven; custom scripts are rarely needed.
class_name ItemResource
extends Resource

@export_group("Metadata")
## Unique identifier for this item archetype.
@export var id: StringName = &""
## Display title of the item, e.g. "[wave]Warrior's Whetstone[/wave]".
@export var title: String = ""
## BBCode text template for the item description. Supports format specifiers (e.g. "%d%% -> %d%%").
@export_multiline var description_template: String = ""
## Optional icon texture displayed in UI cards/inventory.
@export var icon: Texture2D

@export_group("Shop & Economy")
## Purchase cost in gold.
@export var cost: int = 0
## Maximum times this item can be purchased/stacked per run.
## 1 = buy once (unique), >1 = limited stack count, <=0 = infinite purchases.
@export var max_purchases: int = 1

@export_group("Gameplay Effects")
## Gameplay effects applied to the character's AttributeComponent.
@export var gameplay_effects: Array[GameplayEffect] = []
## Instant flat health restored to the character's health pool on apply.
@export var instant_heal: float = 0.0
## Instant percentage of max health restored to the character's health pool (e.g. 50.0 for 50%).
@export var heal_percent: float = 0.0
## Instant flat damage dealt to the character's health pool on apply.
@export var instant_damage: float = 0.0

@export_group("Visuals")
## Optional 3D visual scene (extending ItemVisual) mounted to character bone slots when equipped.
@export var visual_scene: PackedScene


## Returns true if the character is currently eligible to receive this item.
func can_apply(character: Character) -> bool:
	if character == null or not is_instance_valid(character):
		return false
	return true


## Applies base effects (instant healing and damage) to the character.
## Subclasses (GearItemResource, ConsumableItemResource) extend this.
func apply(character: Character) -> bool:
	if not can_apply(character):
		return false

	var attrs: AttributeComponent = character.attribute_component
	if attrs != null:
		if instant_heal > 0.0:
			attrs.restore_pool(AttributeComponent.POOL_HEALTH, instant_heal)
		if heal_percent > 0.0:
			var ratio: float = heal_percent / 100.0 if heal_percent > 1.0 else heal_percent
			var heal_amount: float = attrs.get_current(AttributeComponent.STAT_MAX_HEALTH) * ratio
			attrs.restore_pool(AttributeComponent.POOL_HEALTH, heal_amount)
		if instant_damage > 0.0:
			attrs.damage_pool(AttributeComponent.POOL_HEALTH, instant_damage)

	_custom_apply(character)
	return true


## Optional virtual hook for bespoke item behavior. Standard items leave this empty.
func _custom_apply(_character: Character) -> void:
	pass


## Returns the character's current value for this item's primary attribute.
func get_current_value(character: Character) -> float:
	if character == null or character.attribute_component == null:
		return 0.0
	var attrs: AttributeComponent = character.attribute_component
	if not gameplay_effects.is_empty() and gameplay_effects[0] != null:
		var target_stat: StringName = gameplay_effects[0].target_attribute
		if AttributeComponent.STAT_NAMES.has(target_stat) or AttributeComponent.POOL_NAMES.has(target_stat):
			return attrs.get_current(target_stat)
	if heal_percent > 0.0 or instant_heal > 0.0:
		return attrs.get_current(AttributeComponent.POOL_HEALTH)
	return 0.0


## Returns the projected value of the primary attribute after applying this item.
func get_upgraded_value(character: Character) -> float:
	if character == null or character.attribute_component == null:
		return 0.0
	var attrs: AttributeComponent = character.attribute_component
	if not gameplay_effects.is_empty() and gameplay_effects[0] != null:
		var eff: GameplayEffect = gameplay_effects[0]
		var current_val: float = get_current_value(character)
		return current_val + eff.magnitude
	if heal_percent > 0.0:
		var ratio: float = heal_percent / 100.0 if heal_percent > 1.0 else heal_percent
		var max_hp: float = attrs.get_current(AttributeComponent.STAT_MAX_HEALTH)
		var heal_amount: float = max_hp * ratio
		return minf(max_hp, attrs.get_current(AttributeComponent.POOL_HEALTH) + heal_amount)
	if instant_heal > 0.0:
		var max_hp_flat: float = attrs.get_current(AttributeComponent.STAT_MAX_HEALTH)
		return minf(max_hp_flat, attrs.get_current(AttributeComponent.POOL_HEALTH) + instant_heal)
	return get_current_value(character)


## Formats description_template with current and projected values for UI cards.
func format_description(character: Character) -> String:
	if description_template.is_empty():
		return ""
	if character == null or description_template.find("%") == -1:
		return description_template
	var cur: float = get_current_value(character)
	var next_val: float = get_upgraded_value(character)
	return description_template % [cur, next_val]
