## A spell book: gear whose whole point is what it teaches (its
## granted_abilities and granted_passives). It is equipped like any gear: the
## inventory lists it, unequipping takes its abilities and passives away, and
## the run re-equips it on each level's player, so replacing an ability means
## replacing a book. Unlike plain gear, a book equips only when it teaches
## something new and every new ability fits a free slot; one a character
## cannot use stays on the floor.
## Tool-enabled to match ItemResource so editor previews get real instances.
@tool
class_name BookItemResource
extends GearItemResource


func _init() -> void:
	slot_tag = &"book"
	max_purchases = 1


## True when the book teaches the character something new (an ability or a
## passive it does not hold) and every new ability fits a free slot.
func can_apply(character: Character) -> bool:
	if not super.can_apply(character) or character.ability_system_component == null:
		return false
	var asc: AbilitySystemComponent = character.ability_system_component
	var new_abilities: int = _count_new_abilities(asc)
	return new_abilities + _count_new_passives(asc) > 0 and new_abilities <= asc.get_free_slot_count()


## "Learned: Fireball".
func get_pickup_message() -> String:
	return "Learned: %s" % ", ".join(get_granted_names())


## Why character cannot take the book: no room for its abilities, or it
## already knows everything the book teaches.
func get_refusal_message(character: Character) -> String:
	var asc: AbilitySystemComponent = character.ability_system_component if character != null else null
	if asc != null and _count_new_abilities(asc) > asc.get_free_slot_count():
		return "No free ability slot"
	return "Already learned"


func _grant_verb() -> String:
	return "Teaches"


func _count_new_abilities(asc: AbilitySystemComponent) -> int:
	var count: int = 0
	for ability: AbilityResource in granted_abilities:
		if ability != null and not asc.has_ability(ability):
			count += 1
	return count


func _count_new_passives(asc: AbilitySystemComponent) -> int:
	var count: int = 0
	for scene: PackedScene in granted_passives:
		if scene != null and not asc.has_passive_scene(scene):
			count += 1
	return count
