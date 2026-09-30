## Spawns a packaged scene whenever its trigger fires: the generic, data-driven
## upgrade engine behind "upgrade one ability's behavior" shop items. Configure
## trigger + payload + optional property overrides in one passive scene and
## grant it from an item - zero scripting for "spawn X when Y happens" upgrades
## (dash detonations, slam shockwaves, attack novas, trail hazards...). Damage
## payloads get owner attribution and damage scaling from PayloadSpawner.
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
## Multiplier applied to a damage payload's damage (projectile or DamageArea)
## before attack scaling.
@export var damage_multiplier: float = 1.0
## Scale a damage payload's damage by the owner's attack modifier
## (Character.get_damage_modifier), matching the exact formula melee attacks
## apply to their AttackComponent. Off leaves the payload's own damage intact.
@export var scale_with_attack: bool = true
## Property patches applied to the payload before it enters the tree, so one
## shared payload scene can be tuned differently per granted passive.
@export var payload_overrides: Array[PayloadPropertyOverride] = []


## Spawns the payload for one triggered event through PayloadSpawner (the
## shared path that applies the overrides, credits the owner and scales a
## damage payload's damage).
func _activate(event: AbilityEvent) -> void:
	if payload_scene == null:
		push_warning("PayloadPassiveAbility '%s' has no payload_scene; nothing spawned." % name)
		return
	var owner_character: Character = character if character != null and is_instance_valid(character) else null
	var position: Vector3 = event.position
	if spawn_at == 1 and owner_character != null:
		position = owner_character.global_position
	PayloadSpawner.spawn(payload_scene, owner_character, position, Vector3.ZERO, payload_overrides, damage_multiplier, scale_with_attack)
