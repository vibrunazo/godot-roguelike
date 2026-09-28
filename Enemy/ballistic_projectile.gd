## Enemy projectile lobbed in a ballistic arc onto a ground target: it solves
## the launch velocity for its horizontal speed and fall_gravity, flies under
## that gravity facing along its velocity, and lands when it comes back down
## to the target's height (or touches level geometry). Subclasses decide what
## landing does (_on_landed()) and what hitting a hurtbox in flight does
## (_on_direct_hit()).
class_name BallisticProjectile
extends EnemyProjectile

## Standard Earth gravity acceleration in m/s^2.
const EARTH_GRAVITY: float = 9.8

## Downward gravity acceleration scale in relation to full Earth gravity (9.8 m/s^2).
## A value of 1.0 means it falls at full Earth gravity (9.8 m/s^2), while 0.5 means half Earth gravity (4.9 m/s^2).
@export var fall_gravity: float = 0.5
## Explicit target ground position. Set before launch to override auto-targeting.
@export var target_position: Vector3 = Vector3.ZERO

## Current 3D velocity vector.
var velocity: Vector3 = Vector3.ZERO

var _initialized: bool = false
var _detonated: bool = false
var _has_explicit_target: bool = false


## Returns the effective downward gravity acceleration in m/s^2 (fall_gravity * EARTH_GRAVITY).
func get_effective_gravity() -> float:
	return fall_gravity * EARTH_GRAVITY


func _physics_process(delta: float) -> void:
	if not _initialized:
		if velocity.is_zero_approx():
			initialize_trajectory()
		else:
			_initialized = true
	velocity.y -= get_effective_gravity() * delta
	global_position += velocity * delta
	_on_flight(delta)
	_face_velocity()
	# Landed once descending to (or below) the target's height.
	if velocity.y <= 0.0 and global_position.y <= target_position.y + _get_collision_radius():
		_detonate_on_ground(target_position)


## Sets an explicit target ground position and marks it so auto-targeting won't override it.
func set_target_position(pos: Vector3) -> void:
	target_position = pos
	_has_explicit_target = true


## Initializes the trajectory toward target_override, else the explicit
## target, else the ground under the shooter's current (or nearest) target,
## else 4 m ahead.
func initialize_trajectory(target_override: Vector3 = Vector3(INF, INF, INF)) -> void:
	_initialized = true
	var target_ground: Vector3 = target_position
	if target_override != Vector3(INF, INF, INF):
		target_ground = target_override
	elif not _has_explicit_target:
		target_ground = _auto_target_ground()
	target_position = target_ground
	_calculate_velocity(target_ground)


## Whether the projectile has landed or hit something (and is on its way out).
func is_detonated() -> bool:
	return _detonated


## Called every flight step after moving (e.g. to animate a visual).
func _on_flight(_delta: float) -> void:
	pass


## Called once where the projectile lands (on the ground).
func _on_landed(_ground_position: Vector3) -> void:
	pass


## Called when the projectile hits a living hurtbox in flight. The default
## lands right there.
func _on_direct_hit(_hurtbox: Hurtbox) -> void:
	_detonate_on_ground(global_position)


## The ground under the shooter's current target (else the nearest player),
## else target_position when set, else 4 m ahead on the ground.
func _auto_target_ground() -> Vector3:
	var target_node: Node3D = null
	if shooter != null:
		if shooter.current_target != null and is_instance_valid(shooter.current_target):
			target_node = shooter.current_target
		elif shooter.is_inside_tree():
			target_node = shooter.get_nearest_target("player")
	if target_node == null and is_inside_tree():
		target_node = get_tree().get_first_node_in_group("player") as Node3D
	if target_node != null and is_instance_valid(target_node):
		var ground_y: float = _find_ground_y(target_node.global_position)
		return Vector3(target_node.global_position.x, ground_y, target_node.global_position.z)
	if target_position != Vector3.ZERO:
		return target_position
	var forward: Vector3 = global_basis.z
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var ahead: Vector3 = global_position + forward * 4.0
	ahead.y = 0.0
	return ahead


## The radius of the projectile's sphere collision shape (0.0 without one).
func _get_collision_radius() -> float:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is SphereShape3D:
		return (col.shape as SphereShape3D).radius
	return 0.0


## Finds the ground elevation beneath a given position using raycasting or feet heuristic.
func _find_ground_y(pos: Vector3) -> float:
	if is_inside_tree():
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			pos + Vector3(0.0, 0.5, 0.0),
			pos + Vector3(0.0, -10.0, 0.0),
			1 # Layer 1 = Environment / Ground
		)
		var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty():
			return (result.position as Vector3).y
	# Fallback if no collider hit: characters typically have origin at center y=1, feet at y-1
	if pos.y >= 0.5:
		return pos.y - 1.0
	return 0.0


## Solves the launch velocity that reaches target_ground: the horizontal
## velocity is speed toward it (so flight time = distance / speed) and the
## vertical one rises and falls under the effective gravity in that time,
## arriving with the collision sphere resting on the target.
func _calculate_velocity(target_ground: Vector3) -> void:
	var to_target_xz: Vector3 = Vector3(target_ground.x - global_position.x, 0.0, target_ground.z - global_position.z)
	var delta_y: float = target_ground.y + _get_collision_radius() - global_position.y
	var eff_gravity: float = maxf(get_effective_gravity(), 0.01)
	var total_time: float = to_target_xz.length() / maxf(speed, 0.1)
	if total_time <= 0.001:
		total_time = 0.1
	var v_xz: Vector3 = to_target_xz / total_time
	velocity = Vector3(v_xz.x, (delta_y / total_time) + 0.5 * eff_gravity * total_time, v_xz.z)
	if is_inside_tree():
		_face_velocity()


## Faces along the velocity (model-front convention, +Z forward).
func _face_velocity() -> void:
	var dir: Vector3 = velocity.normalized()
	if dir.is_zero_approx():
		return
	var up: Vector3 = Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	look_at(global_position + dir, up, true)


func _on_body_entered(body: Node3D) -> void:
	if _detonated or is_queued_for_deletion():
		return
	if body == self or body is Character:
		return
	_detonate_on_ground(global_position)


func _on_area_entered(area: Area3D) -> void:
	if _detonated or is_queued_for_deletion():
		return
	if area == self or not (area is Hurtbox) or (shooter != null and area.get_parent() == shooter):
		return
	var hurtbox: Hurtbox = area as Hurtbox
	if hurtbox.is_alive():
		_on_direct_hit(hurtbox)


## Lands at impact_pos: snaps to the target when within half a meter of it,
## drops to the ground, runs _on_landed() and frees the projectile.
func _detonate_on_ground(impact_pos: Vector3) -> void:
	if _detonated or is_queued_for_deletion():
		return
	_detonated = true
	_is_hit = true
	var ground: Vector3 = Vector3(impact_pos.x, _find_ground_y(impact_pos), impact_pos.z)
	if Vector2(impact_pos.x - target_position.x, impact_pos.z - target_position.z).length_squared() < 0.25:
		ground.x = target_position.x
		ground.z = target_position.z
	_on_landed(ground)
	hit_effect()
	queue_free()
