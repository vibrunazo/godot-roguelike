## Ability System Component (ASC, as in UE5's Gameplay Ability System): owns
## every ability one character has, and only the bookkeeping of granting and
## revoking them, never gameplay of its own.
## - Active abilities live in fixed slots: the AbilityCastState nodes wired in
##   slots (the slot count is their number). Granting puts an AbilityResource
##   in a slot; each grant remembers its source, as in GAS: null for an
##   ability learned for good (a book, starting_abilities), the item for one
##   granted while that gear is equipped.
## - Passive abilities (item behavior upgrades) are PassiveAbility scenes
##   instanced as children; ability lifecycle events fan out to them. Each
##   remembers its source too: null when learned for good (a book), the item
##   for one granted while that gear is equipped.
## Passives are plain Nodes: world payloads they spawn go through
## PayloadSpawner so they never inherit this component's lack of transform (a
## Node3D under a plain Node renders in world space).
class_name AbilitySystemComponent
extends Node

## Emitted when an ability is put in a slot (source: null when learned for
## good, else the granting item).
signal ability_granted(slot: int, ability: AbilityResource, source: Object)
## Emitted when an ability leaves its slot.
signal ability_revoked(slot: int, ability: AbilityResource)
## Emitted when the ability in a slot releases its payload.
signal ability_cast(slot: int, ability: AbilityResource)
## Emitted when a passive is granted (source: null when learned for good,
## else the granting item).
signal passive_granted(passive: PassiveAbility, source: Object)
## Emitted when a passive is revoked.
signal passive_revoked(passive: PassiveAbility)

## The character's active ability slots, in order (slot 0 is the first key).
@export var slots: Array[AbilityCastState] = []
## Abilities learned from the start, by slot (null leaves a slot empty).
@export var starting_abilities: Array[AbilityResource] = []

## Character owning these abilities. Resolved from the parent when unset.
var character: Character = null

## Currently granted passive instances (children of this component).
var passives: Array[PassiveAbility] = []

## Grant source of each slot's ability (null: learned for good or empty).
var _sources: Array[Object] = []
## Grant source of each passive (null: learned for good).
var _passive_sources: Dictionary[PassiveAbility, Object] = {}
## The scene each passive was instanced from (passives built in code have none).
var _passive_scenes: Dictionary[PassiveAbility, PackedScene] = {}


func _ready() -> void:
	if character == null:
		character = get_parent() as Character
	_sources.resize(slots.size())
	for index: int in slots.size():
		if slots[index] == null:
			push_error("AbilitySystemComponent: slot %d is not set." % index)
			continue
		slots[index].released.connect(_on_slot_released.bind(index))
	for index: int in mini(starting_abilities.size(), slots.size()):
		if starting_abilities[index] != null:
			grant_ability(starting_abilities[index], null, index)


## Number of active ability slots.
func get_slot_count() -> int:
	return slots.size()


## Puts ability in slot (the first free one when slot is -1). source is null
## for an ability learned for good, else the item granting it while equipped.
## Learning (source null) an ability that gear grants makes it learned for
## good where it is: it stays when the gear comes off. Returns the slot used,
## or -1 when the ability is already held (otherwise), the slot is taken or no
## slot is free.
func grant_ability(ability: AbilityResource, source: Object = null, slot: int = -1) -> int:
	if ability == null:
		return -1
	var held: int = find_slot(ability)
	if held >= 0:
		if source != null or _sources[held] == null:
			return -1
		_sources[held] = null
		ability_granted.emit(held, ability, null)
		return held
	if slot < 0:
		slot = _first_free_slot()
	if slot < 0 or slot >= slots.size() or slots[slot] == null or slots[slot].ability != null:
		return -1
	_check_cast_animation(ability)
	slots[slot].set_ability(ability)
	_sources[slot] = source
	ability_granted.emit(slot, ability, source)
	return slot


## Empties slot. A slot casting right now sends the body on to its next state
## first. Returns the ability that left, or null when the slot was empty.
func revoke_ability(slot: int) -> AbilityResource:
	var ability: AbilityResource = get_ability(slot)
	if ability == null:
		return null
	var state: AbilityCastState = slots[slot]
	if character != null and character.state_machine != null and character.state_machine.state == state:
		state.finish_action("")
	state.set_ability(null)
	_sources[slot] = null
	ability_revoked.emit(slot, ability)
	return ability


## Revokes every ability granted by source (e.g. gear being unequipped).
func revoke_abilities_from(source: Object) -> void:
	for index: int in slots.size():
		if _sources[index] == source and get_ability(index) != null:
			revoke_ability(index)


## The ability in slot, or null.
func get_ability(slot: int) -> AbilityResource:
	if slot < 0 or slot >= slots.size() or slots[slot] == null:
		return null
	return slots[slot].ability


## The source that granted slot's ability (null: learned for good or empty).
func get_source(slot: int) -> Object:
	return _sources[slot] if slot >= 0 and slot < _sources.size() else null


## Whether any slot holds ability.
func has_ability(ability: AbilityResource) -> bool:
	return find_slot(ability) >= 0


## The slot holding ability, or -1.
func find_slot(ability: AbilityResource) -> int:
	if ability == null:
		return -1
	for index: int in slots.size():
		if get_ability(index) == ability:
			return index
	return -1


## Whether at least one slot is empty.
func has_free_slot() -> bool:
	return _first_free_slot() >= 0


## The abilities learned for good, by slot (null for empty slots and for
## abilities granted by gear): what the run remembers between levels.
func get_learned_abilities() -> Array[AbilityResource]:
	var learned: Array[AbilityResource] = []
	learned.resize(slots.size())
	for index: int in slots.size():
		if get_source(index) == null:
			learned[index] = get_ability(index)
	return learned


## Replaces every ability learned for good with learned (by slot). Abilities
## granted by gear stay; a learned one whose slot they hold goes to a free slot.
func set_learned_abilities(learned: Array[AbilityResource]) -> void:
	for index: int in slots.size():
		if get_source(index) == null:
			revoke_ability(index)
	for index: int in learned.size():
		if learned[index] == null:
			continue
		if grant_ability(learned[index], null, index) < 0:
			grant_ability(learned[index], null)


## Whether slot's ability could be cast right now by its own rules
## (cooldown, tags, cost), ignoring what the body is doing.
func is_ready(slot: int) -> bool:
	return get_ability(slot) != null and slots[slot].can_activate()


## Fraction of slot's cooldown still to run (1.0 just cast, 0.0 ready).
func get_cooldown_fraction(slot: int) -> float:
	if get_ability(slot) == null:
		return 0.0
	return slots[slot].get_cooldown_fraction()


## Casts slot's ability now when it is ready: the body enters the slot's
## state. Callers decide first whether the body may cast at all (see
## CharacterState.check_ability()). Returns whether the cast started.
func cast(slot: int) -> bool:
	if not is_ready(slot) or character == null or character.state_machine == null:
		return false
	return character.state_machine.request_state(slots[slot].name)


## Instances a passive scene and arms it. source is null for a passive learned
## for good, else the item granting it while equipped. Returns the instance,
## or null when the scene is missing or its root does not extend
## PassiveAbility.
func add_passive(scene: PackedScene, source: Object = null) -> PassiveAbility:
	if scene == null:
		push_warning("AbilitySystemComponent: cannot add a null passive scene.")
		return null
	var instance: Node = scene.instantiate()
	if instance == null:
		push_warning("AbilitySystemComponent: passive scene failed to instantiate.")
		return null
	if not (instance is PassiveAbility):
		push_warning("AbilitySystemComponent: passive scene root must extend PassiveAbility, got '%s'." % instance.get_class())
		instance.free()
		return null
	var passive: PassiveAbility = instance as PassiveAbility
	_passive_scenes[passive] = scene
	return add_passive_instance(passive, source)


## Arms an already-built passive node (the shared grant path used by add_passive
## and by tests constructing configured passives directly). Returns the passive.
func add_passive_instance(passive: PassiveAbility, source: Object = null) -> PassiveAbility:
	if passive == null:
		return null
	passives.append(passive)
	_passive_sources[passive] = source
	add_child(passive)
	passive.setup(_resolve_character())
	passive_granted.emit(passive, source)
	return passive


## Learns the passive scene for good (source null), unless the character
## already holds a passive from that scene. Returns the new passive, or null.
func learn_passive(scene: PackedScene) -> PassiveAbility:
	if scene == null or has_passive_scene(scene):
		return null
	return add_passive(scene, null)


## Whether any granted passive (learned or from gear) was instanced from scene.
func has_passive_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false
	for passive: PassiveAbility in passives:
		var from: PackedScene = _passive_scenes.get(passive) as PackedScene
		if from != null and (from == scene or (not scene.resource_path.is_empty() and from.resource_path == scene.resource_path)):
			return true
	return false


## The scenes of the passives learned for good (source null), in grant order:
## what the run remembers between levels. Passives built in code are skipped.
func get_learned_passives() -> Array[PackedScene]:
	var learned: Array[PackedScene] = []
	for passive: PassiveAbility in passives:
		var from: PackedScene = _passive_scenes.get(passive) as PackedScene
		if from != null and _passive_sources.get(passive) == null:
			learned.append(from)
	return learned


## The scenes of the passives granted by gear right now.
func get_gear_passives() -> Array[PackedScene]:
	var granted: Array[PackedScene] = []
	for passive: PassiveAbility in passives:
		var from: PackedScene = _passive_scenes.get(passive) as PackedScene
		if from != null and _passive_sources.get(passive) != null:
			granted.append(from)
	return granted


## Replaces every passive learned for good with learned. Gear passives stay.
func set_learned_passives(learned: Array[PackedScene]) -> void:
	for index: int in range(passives.size() - 1, -1, -1):
		if _passive_sources.get(passives[index]) == null:
			remove_passive(passives[index])
	for scene: PackedScene in learned:
		learn_passive(scene)


## Revokes one granted passive instance. Returns true when it was found.
func remove_passive(passive: PassiveAbility) -> bool:
	if passive == null or not passives.has(passive):
		return false
	passives.erase(passive)
	_passive_sources.erase(passive)
	_passive_scenes.erase(passive)
	passive.teardown()
	passive.queue_free()
	passive_revoked.emit(passive)
	return true


## Revokes every granted passive with the given identity.
func remove_passives(id: StringName) -> void:
	for i: int in range(passives.size() - 1, -1, -1):
		if passives[i].id == id:
			remove_passive(passives[i])


## Returns true when at least one passive with the given identity is granted.
func has_passive(id: StringName) -> bool:
	return count_passives(id) > 0


## Returns how many passives with the given identity are granted (stacking).
func count_passives(id: StringName) -> int:
	var count: int = 0
	for passive: PassiveAbility in passives:
		if passive.id == id:
			count += 1
	return count


## Fans one ability lifecycle event out to every granted passive. Iterates a
## snapshot so a passive may revoke itself (or others) mid-dispatch safely.
func notify_ability_event(event: AbilityEvent) -> void:
	if event == null:
		return
	var snapshot: Array[PassiveAbility] = []
	snapshot.assign(passives)
	for passive: PassiveAbility in snapshot:
		if is_instance_valid(passive):
			passive.handle_ability_event(event)


func _first_free_slot() -> int:
	for index: int in slots.size():
		if slots[index] != null and slots[index].ability == null:
			return index
	return -1


## Reports an ability whose cast animation the character's AnimationTree lacks.
func _check_cast_animation(ability: AbilityResource) -> void:
	if character == null or character.animation_tree == null:
		return
	var machine: AnimationNodeStateMachine = character.animation_tree.tree_root as AnimationNodeStateMachine
	if machine != null and not machine.has_node(ability.cast_animation):
		push_error("AbilitySystemComponent: '%s' has no AnimationTree state '%s' for ability '%s'." % [character.name, ability.cast_animation, ability.id])


func _resolve_character() -> Character:
	if character == null:
		character = get_parent() as Character
	return character


func _on_slot_released(ability: AbilityResource, slot: int) -> void:
	ability_cast.emit(slot, ability)
