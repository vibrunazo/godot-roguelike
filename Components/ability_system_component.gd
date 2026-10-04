## Ability System Component (ASC, as in UE5's Gameplay Ability System): owns
## every ability one character has, and only the bookkeeping of granting and
## revoking them, never gameplay of its own.
## - Active abilities live in fixed slots: the AbilityCastState nodes wired in
##   slots (the slot count is their number). Granting puts an AbilityResource
##   in a slot; each grant remembers its source, as in GAS: null for the
##   character's own (starting_abilities), the item for one granted while
##   that gear (a spell book, a helm) is equipped. Each ability remembers the
##   slot it last held, so one granted again (gear re-equipped, a level's
##   fresh player given the run's slot layout) returns there when it is free.
## - Passive abilities (item behavior upgrades) are PassiveAbility scenes
##   instanced as children; ability lifecycle events fan out to them. Gear
##   tracks the passives it grants itself (EquipmentComponent).
## Passives are plain Nodes: world payloads they spawn go through
## PayloadSpawner so they never inherit this component's lack of transform (a
## Node3D under a plain Node renders in world space).
class_name AbilitySystemComponent
extends Node

## Emitted when an ability is put in a slot (source: null for the
## character's own, else the granting item).
signal ability_granted(slot: int, ability: AbilityResource, source: Object)
## Emitted when an ability leaves its slot.
signal ability_revoked(slot: int, ability: AbilityResource)
## Emitted when the ability in a slot releases its payload.
signal ability_cast(slot: int, ability: AbilityResource)
## Emitted when a passive is granted.
signal passive_granted(passive: PassiveAbility)
## Emitted when a passive is revoked.
signal passive_revoked(passive: PassiveAbility)

## The character's active ability slots, in order (slot 0 is the first key).
@export var slots: Array[AbilityCastState] = []
## The character's own abilities from the start, by slot (null leaves a slot
## empty).
@export var starting_abilities: Array[AbilityResource] = []

## Character owning these abilities. Resolved from the parent when unset.
var character: Character = null

## Currently granted passive instances (children of this component).
var passives: Array[PassiveAbility] = []

## Grant source of each slot's ability (null: the character's own, or empty).
var _sources: Array[Object] = []
## The slot each ability last held (or was assigned by set_slot_layout()).
var _preferred_slots: Dictionary[AbilityResource, int] = {}
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


## Puts ability in slot. With slot -1 it goes to the slot it last held (see
## set_slot_layout()) when that one is free, else the first free slot. source
## is null for the character's own ability, else the item granting it while
## equipped. Returns the slot used, or -1 when the ability is already held,
## the slot is taken or no slot is free.
func grant_ability(ability: AbilityResource, source: Object = null, slot: int = -1) -> int:
	if ability == null or has_ability(ability):
		return -1
	if slot < 0:
		slot = _preferred_slots.get(ability, -1)
		if not _is_free(slot):
			slot = _first_free_slot()
	if not _is_free(slot):
		return -1
	_check_cast_animation(ability)
	slots[slot].set_ability(ability)
	_sources[slot] = source
	_preferred_slots[ability] = slot
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


## The source that granted slot's ability (null: the character's own, or
## empty).
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


## Number of empty slots.
func get_free_slot_count() -> int:
	var count: int = 0
	for index: int in slots.size():
		if _is_free(index):
			count += 1
	return count


## What each slot holds, by slot (null for an empty slot): the layout the run
## remembers between levels.
func get_slot_layout() -> Array[AbilityResource]:
	var layout: Array[AbilityResource] = []
	layout.resize(slots.size())
	for index: int in slots.size():
		layout[index] = get_ability(index)
	return layout


## Makes each ability in layout (by slot) prefer its slot there: granted
## later with no slot given (its gear equipped), it goes there when free.
## Abilities already held do not move.
func set_slot_layout(layout: Array[AbilityResource]) -> void:
	for index: int in mini(layout.size(), slots.size()):
		if layout[index] != null:
			_preferred_slots[layout[index]] = index


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


## Instances a passive scene and arms it. Returns the instance, or null when
## the scene is missing or its root does not extend PassiveAbility.
func add_passive(scene: PackedScene) -> PassiveAbility:
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
	return add_passive_instance(passive)


## Arms an already-built passive node (the shared grant path used by add_passive
## and by tests constructing configured passives directly). Returns the passive.
func add_passive_instance(passive: PassiveAbility) -> PassiveAbility:
	if passive == null:
		return null
	passives.append(passive)
	add_child(passive)
	passive.setup(_resolve_character())
	passive_granted.emit(passive)
	return passive


## Whether any granted passive was instanced from scene.
func has_passive_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false
	for from: PackedScene in get_passive_scenes():
		if from == scene or (not scene.resource_path.is_empty() and from.resource_path == scene.resource_path):
			return true
	return false


## The scenes of the granted passives, in grant order (passives built in code
## have none and are left out).
func get_passive_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	for passive: PassiveAbility in passives:
		var from: PackedScene = _passive_scenes.get(passive) as PackedScene
		if from != null:
			scenes.append(from)
	return scenes


## Revokes one granted passive instance. Returns true when it was found.
func remove_passive(passive: PassiveAbility) -> bool:
	if passive == null or not passives.has(passive):
		return false
	passives.erase(passive)
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
		if _is_free(index):
			return index
	return -1


## Whether slot exists and is empty.
func _is_free(slot: int) -> bool:
	return slot >= 0 and slot < slots.size() and slots[slot] != null and slots[slot].ability == null


## Reports an ability whose cast animation the character's AnimationTree lacks.
func _check_cast_animation(ability: AbilityResource) -> void:
	if character == null or character.animation_tree == null:
		return
	var machine: AnimationNodeStateMachine = character.animation_tree.tree_root as AnimationNodeStateMachine
	if machine != null and not machine.has_node(ability.cast_animation):
		push_error("AbilitySystemComponent: '%s' has no AnimationTree state '%s' for ability '%s'." % [character.name, ability.cast_animation, ability.id])
	elif not is_equal_approx(ability.cast_speed, 1.0) and not (character.animation_tree.get("parameters/%s/TimeScale/scale" % ability.cast_animation) is float):
		push_error("AbilitySystemComponent: '%s' state '%s' has no TimeScale node, so ability '%s' cannot play at cast_speed %s." % [character.name, ability.cast_animation, ability.id, ability.cast_speed])


func _resolve_character() -> Character:
	if character == null:
		character = get_parent() as Character
	return character


func _on_slot_released(ability: AbilityResource, slot: int) -> void:
	ability_cast.emit(slot, ability)
