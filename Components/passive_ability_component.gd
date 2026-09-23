## Hosts one character's granted passive abilities and fans ability lifecycle
## events out to them (the project's passive-ability runtime). Passive scenes
## granted by items are instanced as children of this component; the component
## owns grant/revoke bookkeeping only and never holds gameplay of its own.
## Passives are plain Nodes: world payloads they spawn go through
## VfxManager.spawn_world_entity so they never inherit this component's lack of
## transform (a Node3D under a plain Node renders in world space).
class_name PassiveAbilityComponent
extends Node

## Character owning these passives. Resolved from the parent when unset.
var character: Character = null

## Currently granted passive instances (children of this component).
var passives: Array[PassiveAbility] = []


func _ready() -> void:
	if character == null:
		character = get_parent() as Character


## Instances a passive scene and arms it. Returns the instance, or null when the
## scene is missing or its root does not extend PassiveAbility.
func add_passive(scene: PackedScene) -> PassiveAbility:
	if scene == null:
		push_warning("PassiveAbilityComponent: cannot add a null passive scene.")
		return null
	var instance: Node = scene.instantiate()
	if instance == null:
		push_warning("PassiveAbilityComponent: passive scene failed to instantiate.")
		return null
	if not (instance is PassiveAbility):
		push_warning("PassiveAbilityComponent: passive scene root must extend PassiveAbility, got '%s'." % instance.get_class())
		instance.free()
		return null
	return add_passive_instance(instance as PassiveAbility)


## Arms an already-built passive node (the shared grant path used by add_passive
## and by tests constructing configured passives directly). Returns the passive.
func add_passive_instance(passive: PassiveAbility) -> PassiveAbility:
	if passive == null:
		return null
	passives.append(passive)
	add_child(passive)
	passive.setup(_resolve_character())
	return passive


## Revokes one granted passive instance. Returns true when it was found.
func remove_passive(passive: PassiveAbility) -> bool:
	if passive == null or not passives.has(passive):
		return false
	passives.erase(passive)
	passive.teardown()
	passive.queue_free()
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


func _resolve_character() -> Character:
	if character == null:
		character = get_parent() as Character
	return character