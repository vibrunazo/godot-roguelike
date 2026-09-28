## Lobbed projectile fired in a ballistic arc (see BallisticProjectile) that
## spawns an enemy entity upon landing, with optional landing area damage. A
## hurtbox hit in flight lands it right there.
class_name LobbedSpawnProjectile
extends BallisticProjectile

## Enemy scene instantiated on ground impact.
@export var enemy_scene: PackedScene
## Area damage dealt to player entities on landing.
@export var area_damage: float = 15.0
## Radius in meters of the landing area damage.
@export var area_radius: float = 3.0
## Knockback impulse applied to entities caught in the landing area damage.
@export var area_knockback: float = 15.0
## Whether an enemy should be spawned upon landing.
@export var spawn_enemy_on_land: bool = true
## Whether area damage should be dealt upon landing.
@export var deal_area_damage: bool = true
## Optional callback invoked when the projectile reaches its destination.
@export var landing_callback: Callable = Callable()


func _ready() -> void:
	super._ready()
	if attack_component != null:
		attack_component.damage = area_damage
	if enemy_scene == null:
		push_error("%s: enemy_scene is not set." % name)


## Tumbles the carried visual while in flight.
func _on_flight(delta: float) -> void:
	var visual: Node3D = get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.rotate_x(delta * 8.0)
		visual.rotate_z(delta * 6.0)


## Deals the landing area damage, spawns the carried enemy and reports the
## landing to landing_callback.
func _on_landed(ground_position: Vector3) -> void:
	if deal_area_damage:
		_apply_landing_area_damage(ground_position)
	if spawn_enemy_on_land and enemy_scene != null:
		_spawn_enemy(ground_position)
	if landing_callback.is_valid():
		landing_callback.call(ground_position)


func _apply_landing_area_damage(center: Vector3) -> void:
	if not is_inside_tree():
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return
	var shape := SphereShape3D.new()
	shape.radius = area_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = 192 # Layer 7 (64) = Player Hurtbox, Layer 8 (128) = Enemy Hurtbox
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 16)
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider")
		if collider is Hurtbox:
			var hurtbox: Hurtbox = collider as Hurtbox
			if hurtbox.is_alive() and (shooter == null or hurtbox.get_parent() != shooter):
				var knock_dir: Vector3 = (hurtbox.global_position - center).normalized()
				if knock_dir.is_zero_approx():
					knock_dir = Vector3.UP
				if attack_component != null:
					attack_component.deal_damage_to(hurtbox, area_damage, knock_dir * area_knockback)


func _spawn_enemy(pos: Vector3) -> void:
	if enemy_scene == null:
		return
	var enemy: Character = enemy_scene.instantiate() as Character
	if enemy == null:
		return
	var half_height: float = 1.0
	if enemy.collision_shape_3d != null and enemy.collision_shape_3d.shape is CapsuleShape3D:
		half_height = (enemy.collision_shape_3d.shape as CapsuleShape3D).height * 0.5
	enemy.position = pos + Vector3(0.0, half_height, 0.0)
	if Engine.is_in_physics_frame():
		VfxManager.call_deferred("spawn_world_entity", enemy)
	else:
		VfxManager.spawn_world_entity(enemy)

