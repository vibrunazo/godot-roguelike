## Base data resource defining an item's metadata, economy, gameplay effects, and visual scene.
## Standard items are 100% data-driven; custom scripts are rarely needed.
## Tool-enabled so editor previews (e.g. UpgradeIcon) can call summary
## helpers like get_stat_summary() on loaded .tres files instead of hitting
## placeholder instances. Pure data and logic only; safe in the editor.
@tool
class_name ItemResource
extends Resource

@export_group("Metadata")
## Unique identifier for this item archetype.
@export var id: StringName = &""
## Display title of the item, e.g. "[wave]Warrior's Whetstone[/wave]".
@export var title: String = ""
## Pure flavor text explaining what the item does. No stat numbers here:
## stat changes are auto-calculated from the item's effects by
## get_stat_summary() and shown separately in UI cards.
@export_multiline var description: String = ""
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


## Builds the stat change summary for UI cards, auto-calculated from this
## item's actual effects (gameplay_effects, instant_heal, heal_percent,
## instant_damage). Never hand-write stat numbers in descriptions; this is
## the single source of truth for what an item changes. When a character is
## supplied, ADD operations show the character's current -> projected value.
func get_stat_summary(character: Character) -> String:
	var lines: Array[String] = []
	for eff: GameplayEffect in gameplay_effects:
		if eff == null:
			continue
		var line: String = _format_effect_summary(eff, character)
		if not line.is_empty():
			lines.append(line)
	if instant_heal > 0.0 or heal_percent > 0.0 or instant_damage > 0.0:
		var attrs: AttributeComponent = character.attribute_component if character != null and is_instance_valid(character) else null
		if attrs != null:
			# Show the explicit current -> projected health for this use,
			# exactly as taking the item would change it right now.
			var current_hp: float = attrs.get_current(AttributeComponent.POOL_HEALTH)
			var max_hp: float = attrs.get_current(AttributeComponent.STAT_MAX_HEALTH)
			var heal_amount: float = instant_heal
			if heal_percent > 0.0:
				var ratio: float = heal_percent / 100.0 if heal_percent > 1.0 else heal_percent
				heal_amount += max_hp * ratio
			if heal_amount > 0.0:
				lines.append("HP: %s -> [color='7fffd4']%s[/color]" % [_format_amount(current_hp), _format_amount(minf(max_hp, current_hp + heal_amount))])
			if instant_damage > 0.0:
				lines.append("HP: %s -> [color='ff8888']%s[/color]" % [_format_amount(current_hp), _format_amount(maxf(0.0, current_hp - instant_damage))])
		else:
			# No character to preview against; fall back to generic amounts.
			if instant_heal > 0.0:
				lines.append("HP: [color='7fffd4']+%s[/color]" % _format_amount(instant_heal))
			if heal_percent > 0.0:
				lines.append("HP: [color='7fffd4']Heals %s%%[/color] Max HP" % _format_amount(heal_percent))
			if instant_damage > 0.0:
				lines.append("HP: [color='ff8888']-%s[/color]" % _format_amount(instant_damage))
	return "\n".join(lines)


## Formats one GameplayEffect as a human-readable stat change line in the
## form "Label: current -> projected" (stat targets) or "Label: amount"
## (pool targets). Percent operations show deltas relative to the label.
func _format_effect_summary(eff: GameplayEffect, character: Character) -> String:
	if AttributeComponent.POOL_NAMES.has(eff.target_attribute):
		if is_equal_approx(eff.total_damage, 0.0):
			return ""
		var pool_label: String = _stat_display_name(eff.target_attribute)
		var amount: float = absf(eff.total_damage)
		var sign_prefix: String = "+" if eff.total_damage < 0.0 else "-"
		if eff.duration > 0.0:
			return "%s: %s[color='7fffd4']%s[/color] over %ss" % [pool_label, sign_prefix, _format_amount(amount), _format_amount(eff.duration)]
		return "%s: %s[color='7fffd4']%s[/color]" % [pool_label, sign_prefix, _format_amount(amount)]
	if not AttributeComponent.STAT_NAMES.has(eff.target_attribute):
		return ""
	var label: String = _stat_display_name(eff.target_attribute)
	var timed_suffix: String = ""
	if eff.duration > 0.0:
		timed_suffix = " (for %ss)" % _format_amount(eff.duration)
	match eff.operation:
		0: # ADD
			var attrs: AttributeComponent = character.attribute_component if character != null and is_instance_valid(character) else null
			if attrs != null:
				var current: float = attrs.get_current(eff.target_attribute)
				var projected: float = current + eff.magnitude
				return "%s: %s -> [color='7fffd4']%s[/color]%s" % [label, _format_amount(current), _format_amount(projected), timed_suffix]
			return "%s: [color='7fffd4']+%s[/color]%s" % [label, _format_amount(eff.magnitude), timed_suffix]
		1: # MULT_ADD
			return "%s: [color='7fffd4']+%s%%[/color]%s" % [label, _format_amount(eff.magnitude * 100.0), timed_suffix]
		2: # MULT_COMP
			return "%s: [color='7fffd4']x%s[/color]%s" % [label, _format_amount(eff.magnitude), timed_suffix]
	return ""


## Returns a human-readable display label for an AttributeComponent stat or pool name.
func _stat_display_name(stat: StringName) -> String:
	match stat:
		AttributeComponent.POOL_HEALTH:
			return "HP"
		AttributeComponent.POOL_MANA:
			return "MP"
		AttributeComponent.STAT_MAX_HEALTH:
			return "Max HP"
		AttributeComponent.STAT_MAX_MANA:
			return "Max MP"
		AttributeComponent.STAT_ATTACK:
			return "Attack"
		AttributeComponent.STAT_DEFENSE:
			return "Defense"
		AttributeComponent.STAT_SPEED:
			return "Speed"
		AttributeComponent.STAT_ATTACK_SPEED:
			return "Attack Speed"
		AttributeComponent.STAT_FIRE_RESISTANCE:
			return "Fire Resistance"
		AttributeComponent.STAT_ROTATION_SPEED:
			return "Rotation Speed"
	return String(stat).capitalize()


## Formats a number for UI display: whole values as integers, others with one decimal.
func _format_amount(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value
