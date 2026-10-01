## The one way gameplay code sends a payload scene into the world: a
## projectile, a damage area (explosion, hazard), or a plain visual. Used by
## ProjectileSpawnerComponent (enemy ranged attacks), PayloadPassiveAbility
## (item upgrades) and AbilityCastState (active abilities), so every payload
## gets the same setup whoever spawns it.
class_name PayloadSpawner
extends RefCounted

## landing_point value meaning "none": a lobbed payload picks its own target.
const NO_LANDING_POINT: Vector3 = Vector3(INF, INF, INF)


## Instantiates scene, applies overrides, credits instigator (a projectile's
## shooter, a damage area's wielder), scales its damage by damage_multiplier
## and, when scale_with_attack is set, by the instigator's attack modifier
## (Character.get_damage_modifier(), the formula melee attacks use), places
## it at position facing direction and adds it to the world. A straight
## projectile faces direction fully, so it flies up or down along it; any
## other payload only turns on the ground plane. Zero keeps the scene's
## rotation. A lobbed projectile (BallisticProjectile) lands on landing_point,
## or picks its own target when it is NO_LANDING_POINT. Returns the payload,
## or null when the scene is missing or its root is not a Node3D.
static func spawn(scene: PackedScene, instigator: Character, position: Vector3, direction: Vector3 = Vector3.ZERO, overrides: Array[PayloadPropertyOverride] = [], damage_multiplier: float = 1.0, scale_with_attack: bool = false, landing_point: Vector3 = NO_LANDING_POINT) -> Node3D:
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
	_place(payload, position, direction)
	if payload is BallisticProjectile:
		(payload as BallisticProjectile).initialize_trajectory(landing_point)
	return payload


## Puts payload at position facing direction and adds it to the world: placed
## before entering the tree (so _ready sees it), and again in world space once
## in it, in case the host is transformed. A straight projectile also pitches
## along direction; other payloads only turn on the ground plane.
static func _place(payload: Node3D, position: Vector3, direction: Vector3) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	var yaw: float = atan2(flat.x, flat.z) if not flat.is_zero_approx() else payload.rotation.y
	var pitch: float = payload.rotation.x
	if payload is Projectile and not (payload is BallisticProjectile) and not flat.is_zero_approx():
		# Pitch toward direction: model front is +Z, so a rise is a negative X turn.
		pitch = -atan2(direction.y, flat.length())
	payload.position = position
	payload.rotation = Vector3(pitch, yaw, payload.rotation.z)
	VfxManager.spawn_world_entity(payload)
	payload.global_position = position
	payload.global_rotation = Vector3(pitch, yaw, payload.global_rotation.z)
