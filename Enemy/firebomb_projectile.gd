## Lobbed projectile fired in a ballistic arc that falls with gravity and detonates into a FireTrap upon hitting the ground.
class_name FirebombProjectile
extends EnemyProjectile

## Standard Earth gravity acceleration in m/s^2.
const EARTH_GRAVITY: float = 9.8

## Downward gravity acceleration scale in relation to full Earth gravity (9.8 m/s^2).
## A value of 1.0 means it falls at full Earth gravity (9.8 m/s^2), while 0.5 means half Earth gravity (4.9 m/s^2).
@export var fall_gravity: float = 0.5:
	set(value):
		fall_gravity = value
		gravity = get_effective_gravity()
## Explicit target ground position. Set before launch to override auto-targeting.
@export var target_position: Vector3 = Vector3.ZERO
## Fire trap hazard scene spawned on ground impact.
@export var fire_trap_scene: PackedScene
## Duration in seconds of the spawned fire trap before extinguishing.
@export var trap_duration: float = 10.0
## Size in meters (X = width, Y = depth) of the spawned fire trap.
@export var trap_size: Vector2 = Vector2(2.0, 2.0)

## Current 3D velocity vector.
var velocity: Vector3 = Vector3.ZERO

var _initialized: bool = false
var _detonated: bool = false
var _has_explicit_target: bool = false


## Returns the effective downward gravity acceleration in m/s^2 (fall_gravity * EARTH_GRAVITY).
func get_effective_gravity() -> float:
	return fall_gravity * EARTH_GRAVITY


func _init() -> void:
	fall_gravity = 0.5
	gravity = get_effective_gravity()


func _ready() -> void:
	if not is_equal_approx(gravity, get_effective_gravity()) and not is_equal_approx(gravity, EARTH_GRAVITY):
		fall_gravity = gravity / EARTH_GRAVITY
	gravity = get_effective_gravity()

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if attack_component != null:
		attack_component.damage = damage
	if fire_trap_scene == null:
		fire_trap_scene = load("res://Hazards/fire_trap.tscn") as PackedScene


func _physics_process(delta: float) -> void:
	if not _initialized:
		if velocity.is_zero_approx():
			initialize_trajectory()
		else:
			_initialized = true

	velocity.y -= get_effective_gravity() * delta
	global_position += velocity * delta

	# Orient along velocity vector using model-front convention (+Z forward)
	var dir: Vector3 = velocity.normalized()
	if not dir.is_zero_approx():
		var up: Vector3 = Vector3.UP
		if absf(dir.dot(Vector3.UP)) > 0.99:
			up = Vector3.FORWARD
		look_at(global_position + dir, up, true)

	# Check if descending projectile has reached or passed ground target level
	var col_radius: float = _get_collision_radius()
	if velocity.y <= 0.0 and global_position.y <= (target_position.y + col_radius):
		_detonate_on_ground(Vector3(target_position.x, target_position.y, target_position.z))


## Helper to query the radius of the sphere collision shape.
func _get_collision_radius() -> float:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is SphereShape3D:
		return (col.shape as SphereShape3D).radius
	return 0.3


## Sets an explicit target ground position and marks it so auto-targeting won't override it.
func set_target_position(pos: Vector3) -> void:
	target_position = pos
	_has_explicit_target = true


## Initializes trajectory calculation toward target ground position.
func initialize_trajectory(target_override: Vector3 = Vector3(INF, INF, INF)) -> void:
	_initialized = true

	var target_ground: Vector3 = Vector3.ZERO
	if target_override != Vector3(INF, INF, INF):
		target_ground = target_override
	elif _has_explicit_target:
		target_ground = target_position
	else:
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
			target_ground = Vector3(target_node.global_position.x, ground_y, target_node.global_position.z)
		elif _has_explicit_target or target_position != Vector3.ZERO:
			target_ground = target_position
		else:
			var forward: Vector3 = global_basis.z
			if forward.is_zero_approx():
				forward = Vector3.FORWARD
			target_ground = global_position + forward * 4.0
			target_ground.y = 0.0

	target_position = target_ground
	_calculate_velocity(target_ground)


## Finds the ground elevation beneath a given position using raycasting or feet heuristic.
func _find_ground_y(pos: Vector3) -> float:
	if is_inside_tree():
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		if space_state != null:
			var query := PhysicsRayQueryParameters3D.create(
				pos + Vector3(0.0, 0.5, 0.0),
				pos + Vector3(0.0, -10.0, 0.0),
				1 # Layer 1 = Environment / Ground
			)
			var result: Dictionary = space_state.intersect_ray(query)
			if not result.is_empty():
				return (result.position as Vector3).y
	# Fallback if no collider hit: characters typically have origin at center y=1, feet at y-1
	if pos.y >= 0.5:
		return pos.y - 1.0
	return 0.0


## Calculates initial velocity vector required to hit target_ground with gravity and speed.
## Flight duration varies based on distance and speed: total_time = distance_xz / speed.
## Accounts for the collision shape radius so physical floor contact occurs at target_ground.
func _calculate_velocity(target_ground: Vector3) -> void:
	var start_pos: Vector3 = global_position
	var to_target_xz: Vector3 = Vector3(target_ground.x - start_pos.x, 0.0, target_ground.z - start_pos.z)
	var distance_xz: float = to_target_xz.length()

	var col_radius: float = _get_collision_radius()
	var arrival_y: float = target_ground.y + col_radius
	var delta_y: float = arrival_y - start_pos.y

	var proj_speed: float = maxf(speed, 0.1)
	var eff_gravity: float = maxf(get_effective_gravity(), 0.01)

	# Flight time is determined by fixed projectile speed and horizontal distance
	var total_time: float = distance_xz / proj_speed
	if total_time <= 0.001:
		total_time = 0.1

	var v_xz: Vector3 = to_target_xz / total_time
	var vy0: float = (delta_y / total_time) + 0.5 * eff_gravity * total_time

	velocity = Vector3(v_xz.x, vy0, v_xz.z)

	# Orient immediately along initial velocity vector
	var dir: Vector3 = velocity.normalized()
	if not dir.is_zero_approx() and is_inside_tree():
		var up: Vector3 = Vector3.UP
		if absf(dir.dot(Vector3.UP)) > 0.99:
			up = Vector3.FORWARD
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
	if not hurtbox.is_alive():
		return
	_detonated = true
	_is_hit = true
	if attack_component != null:
		var knock_dir: Vector3 = velocity.normalized()
		if knock_dir.is_zero_approx():
			knock_dir = global_basis.z
		attack_component.deal_damage_to(hurtbox, damage, knock_dir * knockback)
	hit_effect()
	queue_free()


func _detonate_on_ground(impact_pos: Vector3) -> void:
	if _detonated or is_queued_for_deletion():
		return
	_detonated = true
	_is_hit = true
	var ground_y: float = _find_ground_y(impact_pos)
	var spawn_pos: Vector3 = Vector3(impact_pos.x, ground_y, impact_pos.z)
	var xz_offset: Vector2 = Vector2(impact_pos.x - target_position.x, impact_pos.z - target_position.z)
	if xz_offset.length_squared() < 0.25:
		spawn_pos.x = target_position.x
		spawn_pos.z = target_position.z
	_spawn_fire_trap(spawn_pos)
	hit_effect()
	queue_free()


func _spawn_fire_trap(pos: Vector3) -> void:
	var scene: PackedScene = fire_trap_scene
	if scene == null:
		scene = load("res://Hazards/fire_trap.tscn") as PackedScene
	if scene == null:
		return
	var trap: FireTrap = scene.instantiate() as FireTrap
	if trap == null:
		return
	trap.trap_size = trap_size
	trap.show_ground_mesh = false
	trap.duration = trap_duration
	trap.position = pos
	VfxManager.spawn_world_entity(trap)


func is_detonated() -> bool:
	return _detonated

