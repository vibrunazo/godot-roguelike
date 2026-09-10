## Deals damage and knockback through weapon hitboxes.
## Listens to its hitbox Area3D for Hurtbox overlaps and routes hits through
## Hurtbox.receive_hit(), so attackers never inspect target internals.
## Manages per-attack exceptions and multi-hit rehit intervals.
extends Node
class_name AttackComponent

## Signal emitted when damage is successfully dealt to a hurtbox.
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

## Associated Area3D hitbox (if parent or assigned, for event-driven hit detection).
## Hitboxes must mask the Hurtboxes layer; movement bodies are never hit directly.
var attack_area: Area3D = null

## Character wielding this weapon, resolved from the hitbox ancestry.
## Its own hurtbox is always excluded from hits.
var wielder: Character = null


func _ready() -> void:
	var parent: Node = get_parent()
	if parent is Area3D and not (parent is EnemyProjectile):
		set_attack_area(parent as Area3D)


func set_attack_area(area: Area3D) -> void:
	attack_area = area
	wielder = null
	var node: Node = attack_area
	while node != null:
		if node is Character:
			wielder = node as Character
			break
		node = node.get_parent()
	if not attack_area.area_entered.is_connected(_on_area_entered):
		attack_area.area_entered.connect(_on_area_entered)


## Returns true when the hurtbox is a legal target: not our own signals, and
## never the wielder's own hurtbox (hitbox and hurtbox overlap on the same body).
func _is_valid_target(area: Area3D) -> bool:
	if area == self or area == get_parent():
		return false
	if not (area is Hurtbox):
		return false
	if wielder != null and area.get_parent() == wielder:
		return false
	return true


func _physics_process(delta: float) -> void:
	current_time += delta
	# Only multi-hit attacks with rehit_interval > 0.0 re-evaluate persistent overlaps while active
	if rehit_interval > 0.0 and attack_area != null and attack_area.monitoring:
		_refresh_cooldowns(rehit_interval)
		for area: Area3D in attack_area.get_overlapping_areas():
			if _is_valid_target(area) and not temporary_exceptions.has(area as CollisionObject3D):
				deal_damage_to(area as Hurtbox, damage, knockback, rehit_interval)


func _on_area_entered(area: Area3D) -> void:
	if _is_valid_target(area):
		deal_damage_to(area as Hurtbox, damage, knockback, rehit_interval)


## Deals damage and knockback to a hurtbox if eligible (respecting rehit intervals and exceptions).
## Returns true if damage was successfully applied.
func deal_damage_to(hurtbox: Hurtbox, dmg: float = -1.0, kb: Vector3 = Vector3.ZERO, custom_rehit_interval: float = -1.0) -> bool:
	if not is_instance_valid(hurtbox):
		return false

	var d: float = dmg if dmg >= 0.0 else damage
	var k: Vector3 = kb if kb != Vector3.ZERO else knockback

	var interval: float = custom_rehit_interval if custom_rehit_interval >= 0.0 else rehit_interval
	if interval > 0.0:
		_refresh_cooldowns(interval)

	if temporary_exceptions.has(hurtbox as CollisionObject3D):
		return false

	var has_hit: bool = hurtbox.receive_hit(d, k)
	if has_hit:
		temporary_exceptions.append(hurtbox as CollisionObject3D)
		if interval > 0.0:
			hit_timestamps[hurtbox as CollisionObject3D] = current_time
		hit_landed.emit(hurtbox)

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
	for area: Area3D in attack_area.get_overlapping_areas():
		if _is_valid_target(area) and not temporary_exceptions.has(area as CollisionObject3D):
			deal_damage_to(area as Hurtbox, d, k, interval)


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
