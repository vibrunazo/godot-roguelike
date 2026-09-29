## AttackComponent rehit behavior, built from plain nodes (a hitbox Area3D
## with an AttackComponent, and bare targets made of an AttributeComponent
## plus a Hurtbox) so no character tuning is involved:
## - with rehit_interval > 0, a target that stays inside the hitbox is hit
##   again once the interval has elapsed,
## - freeing a target that was hit must not break rehits for the others
##   (regression: a freed entry in the rehit bookkeeping used to raise a
##   script error every tick and stop every cooldown from expiring).
extends "res://test/lib/test_suite.gd"

## Test-owned attack values.
const REHIT_INTERVAL: float = 0.1
const DAMAGE: float = 1.0
## Hurtbox layer the test targets sit on (the player hurtbox layer).
const TARGET_LAYER: int = 64
## Frames allowed for several rehit intervals to pass.
const REHIT_FRAMES: int = 120


func test_rehit_interval_hits_a_target_that_stays_inside_again() -> void:
	var target: Hurtbox = _spawn_target(Vector3(0.5, 0.0, 0.0))
	var hits: Array[int] = _count_hits(target)
	_spawn_hitbox()
	await wait_until(func() -> bool: return hits[0] >= 2, "a target inside a rehit_interval hitbox should be hit again", REHIT_FRAMES)


func test_rehits_keep_working_after_a_hit_target_is_freed() -> void:
	var doomed: Hurtbox = _spawn_target(Vector3(0.5, 0.0, 0.0))
	var survivor: Hurtbox = _spawn_target(Vector3(-0.5, 0.0, 0.0))
	var doomed_hits: Array[int] = _count_hits(doomed)
	var survivor_hits: Array[int] = _count_hits(survivor)
	_spawn_hitbox()
	if not await wait_until(func() -> bool: return doomed_hits[0] >= 1 and survivor_hits[0] >= 1, "both targets should be hit", REHIT_FRAMES):
		return
	doomed.get_parent().free()
	var hits_after_free: int = survivor_hits[0]
	await wait_until(func() -> bool: return survivor_hits[0] > hits_after_free, "the surviving target should still be rehit after another target was freed", REHIT_FRAMES)


## A bare damageable target: Node3D with an AttributeComponent and a Hurtbox.
func _spawn_target(at: Vector3) -> Hurtbox:
	var root: Node3D = Node3D.new()
	root.position = at
	var attributes: AttributeComponent = AttributeComponent.new()
	attributes.name = "AttributeComponent"
	root.add_child(attributes)
	var hurtbox: Hurtbox = Hurtbox.new()
	hurtbox.attribute_component = attributes
	hurtbox.collision_layer = TARGET_LAYER
	hurtbox.collision_mask = 0
	hurtbox.add_child(_sphere(0.5))
	root.add_child(hurtbox)
	autofree(root)
	add_child(root)
	return hurtbox


## A monitoring hitbox at the origin overlapping both target positions.
func _spawn_hitbox() -> AttackComponent:
	var hitbox: Area3D = Area3D.new()
	hitbox.collision_layer = 0
	hitbox.collision_mask = TARGET_LAYER
	hitbox.add_child(_sphere(2.0))
	var attack: AttackComponent = AttackComponent.new()
	attack.damage = DAMAGE
	attack.rehit_interval = REHIT_INTERVAL
	hitbox.add_child(attack)
	autofree(hitbox)
	add_child(hitbox)
	return attack


func _count_hits(hurtbox: Hurtbox) -> Array[int]:
	var hits: Array[int] = [0]
	hurtbox.struck.connect(func(_damage: float) -> void: hits[0] += 1)
	return hits


func _sphere(radius: float) -> CollisionShape3D:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	return shape
