## The one way gameplay code sends a payload scene into the world: a
## projectile, a damage area (explosion, hazard), or a plain visual. Used by
## ProjectileSpawnerComponent (enemy ranged attacks), PayloadPassiveAbility
## (item upgrades) and AbilityCastState (active abilities), so every payload
## gets the same setup whoever spawns it.
class_name PayloadSpawner
extends RefCounted


## Instantiates scene, applies overrides, credits instigator (a projectile's
## shooter, a damage area's wielder), scales its damage by damage_multiplier
## and, when scale_with_attack is set, by the instigator's attack modifier
## (Character.get_damage_modifier(), the formula melee attacks use), places
## it at position facing direction (on the ground plane; zero keeps the
## scene's rotation), and adds it to the world. Returns the payload, or null
## when the scene is missing or its root is not a Node3D.
static func spawn(scene: PackedScene, instigator: Character, position: Vector3, direction: Vector3 = Vector3.ZERO, overrides: Array[PayloadPropertyOverride] = [], damage_multiplier: float = 1.0, scale_with_attack: bool = false) -> Node3D:
	if scene == null:
		push_error("PayloadSpawner: no payload scene to spawn.")
		return null
	var instance: Node = scene.instantiate()
	var payload: Node3D = instance as Node3D
	if payload == null:
		push_error("PayloadSpawner: payload root must extend Node3D, got '%s' (%s)." % [instance.get_class(), scene.resource_path])
		instance.free()
		return null
	for override: PayloadPropertyOverride in overrides:
		if override != null:
			override.apply_to(payload)
	var scale: float = damage_multiplier
	if scale_with_attack and instigator != null and is_instance_valid(instigator):
		scale *= instigator.get_damage_modifier()
	if payload is Projectile:
		var projectile: Projectile = payload as Projectile
		projectile.shooter = instigator
		projectile.damage *= scale
	elif payload is DamageArea:
		var area: DamageArea = payload as DamageArea
		if instigator != null and is_instance_valid(instigator):
			area.set_wielder(instigator)
		area.damage *= scale
	# Placed before entering the tree (so _ready sees it), and again in world
	# space once in it, in case the host is transformed.
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	var yaw: float = atan2(flat.x, flat.z) if not flat.is_zero_approx() else payload.rotation.y
	payload.position = position
	payload.rotation.y = yaw
	VfxManager.spawn_world_entity(payload)
	payload.global_position = position
	payload.global_rotation.y = yaw
	if payload is BallisticProjectile:
		(payload as BallisticProjectile).initialize_trajectory()
	return payload
