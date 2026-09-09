extends Node
class_name AttackComponent

## Signal emitted when a hit is detected or damage is successfully dealt to a target.
signal hit_landed(target: Node)

## Current damage value dealt to hit targets upon collision.
@export var damage: float = 10.0

## Current knockback vector applied to hit targets upon collision.
@export var knockback: Vector3 = Vector3.ZERO

## Whether landing a hit with this attack component triggers a camera screen shake.
@export var shake_on_damage: bool = false

## Minimum interval (in seconds) before the same target can be damaged again by this attack.
## If <= 0.0, the target is only hit once per attack cycle until reset_exceptions() is called.
@export var rehit_interval: float = 0.0

var temporary_exceptions: Array[CollisionObject3D] = []
var hit_timestamps: Dictionary = {}
var current_time: float = 0.0

## Associated Area3D (if parent or assigned, for event-driven hit detection).
var attack_area: Area3D = null


func _ready() -> void:
	var parent: Node = get_parent()
	if parent is Area3D and not (parent is EnemyProjectile):
		set_attack_area(parent as Area3D)


func set_attack_area(area: Area3D) -> void:
	attack_area = area
	if not attack_area.body_entered.is_connected(_on_body_entered):
		attack_area.body_entered.connect(_on_body_entered)
	if not attack_area.area_entered.is_connected(_on_area_entered):
		attack_area.area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	current_time += delta
	# Only multi-hit attacks with rehit_interval > 0.0 re-evaluate persistent overlaps while active
	if rehit_interval > 0.0 and attack_area != null and attack_area.monitoring:
		_refresh_cooldowns(rehit_interval)
		for body: Node3D in attack_area.get_overlapping_bodies():
			if not temporary_exceptions.has(body as CollisionObject3D):
				deal_damage_to(body, damage, knockback, rehit_interval)


func _on_body_entered(body: Node3D) -> void:
	if body == self or body == get_parent():
		return
	deal_damage_to(body, damage, knockback, rehit_interval)


func _on_area_entered(area: Area3D) -> void:
	if area == self or area == get_parent():
		return
	deal_damage_to(area, damage, knockback, rehit_interval)


## Deals damage and knockback to a specific target collider if eligible (respecting rehit intervals and exceptions).
## Returns true if damage was successfully applied.
func deal_damage_to(target: Node, dmg: float = -1.0, kb: Vector3 = Vector3.ZERO, custom_rehit_interval: float = -1.0) -> bool:
	if not is_instance_valid(target):
		return false

	var d: float = dmg if dmg >= 0.0 else damage
	var k: Vector3 = kb if kb != Vector3.ZERO else knockback

	var col := target as CollisionObject3D
	var interval: float = custom_rehit_interval if custom_rehit_interval >= 0.0 else rehit_interval
	if interval > 0.0:
		_refresh_cooldowns(interval)

	if col != null and temporary_exceptions.has(col):
		return false

	var has_hit: bool = false
	if target.has_node("HealthComponent"):
		var health_component: HealthComponent = target.get_node("HealthComponent") as HealthComponent
		health_component.take_damage(d)
		if col != null:
			if not temporary_exceptions.has(col):
				temporary_exceptions.append(col)
			if interval > 0.0:
				hit_timestamps[col] = current_time
		has_hit = true
		hit_landed.emit(target)

	if target.has_node("KnockbackComponent"):
		var knockback_component: KnockbackComponent = target.get_node("KnockbackComponent") as KnockbackComponent
		knockback_component.add_knockback(k)

	if shake_on_damage and has_hit:
		var camera := get_viewport().get_camera_3d() as ShakeCamera3D
		if camera != null:
			camera.quick_shake(0.75)

	return has_hit


func deal_damage(dmg: float = -1.0, kb: Vector3 = Vector3.ZERO, custom_rehit_interval: float = -1.0) -> void:
	if attack_area == null or not attack_area.monitoring:
		return
	var d: float = dmg if dmg >= 0.0 else damage
	var k: Vector3 = kb if kb != Vector3.ZERO else knockback
	var interval: float = custom_rehit_interval if custom_rehit_interval >= 0.0 else rehit_interval
	if interval > 0.0:
		_refresh_cooldowns(interval)
	for body: Node3D in attack_area.get_overlapping_bodies():
		if not temporary_exceptions.has(body as CollisionObject3D):
			deal_damage_to(body, d, k, interval)
	for area: Area3D in attack_area.get_overlapping_areas():
		if not temporary_exceptions.has(area as CollisionObject3D):
			deal_damage_to(area, d, k, interval)


func add_exception(col: CollisionObject3D) -> void:
	if col != null and is_instance_valid(col) and not temporary_exceptions.has(col):
		temporary_exceptions.append(col)


func _refresh_cooldowns(interval: float) -> void:
	var to_remove: Array[CollisionObject3D] = []
	for target: Variant in hit_timestamps:
		var col := target as CollisionObject3D
		if not is_instance_valid(col):
			to_remove.append(col)
			continue
		var hit_time: float = hit_timestamps[col] as float
		if current_time - hit_time >= interval:
			to_remove.append(col)
			temporary_exceptions.erase(col)
	for target: CollisionObject3D in to_remove:
		hit_timestamps.erase(target)


func reset_exceptions() -> void:
	temporary_exceptions.clear()
	hit_timestamps.clear()
