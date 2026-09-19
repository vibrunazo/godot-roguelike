## Consumable item resource (potions, scrolls, temporary buffs, bandages).
## Applied once on consumption, not persisted as equipped gear. Defaults to infinite shop availability.
class_name ConsumableItemResource
extends ItemResource


func _init() -> void:
	max_purchases = -1


## Consumes this item: applies instant healing/damage and any timed GameplayEffects to the character.
func consume(character: Character) -> bool:
	if not can_apply(character):
		return false

	# Apply base instant pools (heal/damage)
	apply(character)

	# Apply any timed or instant GameplayEffects (e.g. temporary buffs or damage over time)
	if character.attribute_component != null:
		var attrs: AttributeComponent = character.attribute_component
		for eff: GameplayEffect in gameplay_effects:
			if eff != null:
				attrs.apply_effect(eff)

	_on_consumed(character)
	return true


## Optional virtual hook called when consumable is consumed.
func _on_consumed(_character: Character) -> void:
	pass
