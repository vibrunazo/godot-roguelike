extends Node
class_name AttackComponent

## Whether landing a hit with this attack component triggers a camera screen shake.
@export var shake_on_damage: bool = false

## Minimum interval (in seconds) before the same target can be damaged again by this attack.
## If <= 0.0, the target is only hit once per attack cycle until reset_exceptions() is called.
@export var rehit_interval: float = 0.0

var temporary_exceptions: Array[CollisionObject3D] = []
var hit_timestamps: Dictionary = {}
var current_time: float = 0.0

@onready var attack_shapecast: ShapeCast3D = get_parent()


func _physics_process(delta: float) -> void:
	current_time += delta


func deal_damage(damage: float, knockback: Vector3, custom_rehit_interval: float = -1.0) -> void:
	if attack_shapecast.enabled == false: return
	
	var interval: float = custom_rehit_interval if custom_rehit_interval >= 0.0 else rehit_interval
	if interval > 0.0:
		_refresh_cooldowns(interval)
		
	attack_shapecast.force_shapecast_update()
	var has_hit: bool = false
	for index: int in attack_shapecast.get_collision_count():
		var collider: CollisionObject3D = attack_shapecast.get_collider(index) as CollisionObject3D
		if collider and is_instance_valid(collider) and collider.has_node("HealthComponent"):
			var health_component: HealthComponent = collider.get_node("HealthComponent") as HealthComponent
			health_component.take_damage(damage)
			attack_shapecast.add_exception(collider)
			if not temporary_exceptions.has(collider):
				temporary_exceptions.append(collider)
			if interval > 0.0:
				hit_timestamps[collider] = current_time
			has_hit = true
		if collider and is_instance_valid(collider) and collider.has_node("KnockbackComponent"):
			var knockback_component: KnockbackComponent = collider.get_node("KnockbackComponent") as KnockbackComponent
			knockback_component.add_knockback(knockback)
	if shake_on_damage and has_hit:
		var camera := get_viewport().get_camera_3d() as ShakeCamera3D
		if camera != null:
			camera.quick_shake(0.75)


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
			if attack_shapecast != null:
				attack_shapecast.remove_exception(col)
			temporary_exceptions.erase(col)
	for target: CollisionObject3D in to_remove:
		hit_timestamps.erase(target)


func reset_exceptions() -> void:
	if attack_shapecast != null:
		for exception: CollisionObject3D in temporary_exceptions:
			if is_instance_valid(exception):
				attack_shapecast.remove_exception(exception)
		attack_shapecast.clear_exceptions()
	temporary_exceptions.clear()
	hit_timestamps.clear()
