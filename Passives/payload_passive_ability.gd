## Spawns a packaged scene whenever its trigger fires: the generic, data-driven
## upgrade engine behind "upgrade one ability's behavior" shop items. Configure
## trigger + payload + optional property overrides in one passive scene and
## grant it from an item - zero scripting for "spawn X when Y happens" upgrades
## (dash detonations, slam shockwaves, attack novas, trail hazards...). Damage
## payloads (DamageArea) additionally get wielder attribution and damage
## scaling through the same formula melee attacks use.
##
## Payload authoring note: payloads can be spawned from inside physics signal
## dispatch (a passive reacting to a body_entered callback, e.g. the exit
## portal's during a scene transition), where Area3D monitoring/monitorable
## setters are locked. A payload's _ready must arm hitboxes through
## DamageArea.set_hitbox_active() (or set_deferred / the
## Engine.is_in_physics_frame() guard WeaponSlot uses), never with direct writes.
class_name PayloadPassiveAbility
extends AbilityLifecyclePassive

## Scene spawned on activation (explosion, hazard zone, projectile, VFX, ...).
@export var payload_scene: PackedScene
## Where to spawn the payload: at the event position or at the caster's feet.
@export_enum("EVENT_POSITION", "CASTER") var spawn_at: int = 0
## Multiplier applied to a DamageArea payload's damage before attack scaling.
@export var damage_multiplier: float = 1.0
## Scale a DamageArea payload's damage by the owner's attack modifier
## (Character.get_damage_modifier), matching the exact formula melee attacks
## apply to their AttackComponent. Off leaves the payload's own damage intact.
@export var scale_with_attack: bool = true
## Property patches applied to the payload before it enters the tree, so one
## shared payload scene can be tuned differently per granted passive.
@export var payload_overrides: Array[PayloadPropertyOverride] = []


## Instantiates, configures, and spawns the payload for one triggered event.
func _activate(event: AbilityEvent) -> void:
	if payload_scene == null:
		push_warning("PayloadPassiveAbility '%s' has no payload_scene; nothing spawned." % name)
		return
	var payload: Node = payload_scene.instantiate()
	if payload == null:
		push_warning("PayloadPassiveAbility '%s' failed to instantiate its payload scene." % name)
		return
	var payload_3d: Node3D = payload as Node3D
	if payload_3d == null:
		push_warning("PayloadPassiveAbility '%s' payload root must extend Node3D, got '%s'." % [name, payload.get_class()])
		payload.free()
		return

	for override: PayloadPropertyOverride in payload_overrides:
		if override != null:
			override.apply_to(payload)
	if payload is DamageArea:
		_configure_damage_area(payload as DamageArea)

	if spawn_at == 1 and character != null and is_instance_valid(character):
		payload_3d.position = character.global_position
	else:
		payload_3d.position = event.position
	VfxManager.spawn_world_entity(payload_3d)


## Wires a DamageArea payload to the passive's owner and applies damage tuning:
## scene damage -> damage_multiplier -> owner attack scaling (optional), the
## same `damage * character.get_damage_modifier()` formula CharacterAttack uses.
func _configure_damage_area(area: DamageArea) -> void:
	if character != null and is_instance_valid(character):
		area.set_wielder(character)
	area.damage *= damage_multiplier
	if scale_with_attack and character != null and is_instance_valid(character):
		area.damage *= character.get_damage_modifier()