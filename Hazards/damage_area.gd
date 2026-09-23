@tool
## Base class for spatial area hazards, ground AOEs, and persistent damage zones.
## Manages a DamageHitbox Area3D, CollisionShape3D, AttackComponent, and optional
## lifetime timer. Subclasses include FireTrap, SpikesHazard, and GroundDamageArea.
class_name DamageArea
extends Node3D

## Damage dealt per hit to entities in the area.
@export var damage: float = 10.0:
	set(value):
		damage = value
		_sync_attack_component()

## Linear knockback impulse force applied upon taking damage.
@export var knockback_force: float = 0.0:
	set(value):
		knockback_force = value
		_sync_attack_component()

## Directional knockback vector. If ZERO, uses knockback_force along normal/vertical.
@export var knockback_vector: Vector3 = Vector3.ZERO:
	set(value):
		knockback_vector = value
		_sync_attack_component()

## Damage type tag routed to Hurtbox.receive_hit (e.g. &"physical", &"fire").
@export var damage_type: StringName = &"physical":
	set(value):
		damage_type = value
		_sync_attack_component()

## Interval in seconds between consecutive damage ticks on lingering characters.
## If <= 0.0, targets are damaged once per entrance or until exceptions reset.
@export var damage_interval: float = 0.0:
	set(value):
		damage_interval = value
		_sync_attack_component()

## Lifetime in seconds before this damage area expires and frees itself.
## If <= 0.0, persists until manually removed or triggered.
@export var duration: float = 0.0:
	set(value):
		duration = value
		if is_inside_tree():
			_setup_duration_timer()

## Whether this damage area can hit players (collision layer 7, mask 64).
@export var can_hit_player: bool = true:
	set(value):
		can_hit_player = value
		if is_inside_tree():
			_update_collision_mask()

## Whether this damage area can hit enemies (collision layer 8, mask 128).
@export var can_hit_enemies: bool = false:
	set(value):
		can_hit_enemies = value
		if is_inside_tree():
			_update_collision_mask()

## If true, hits all characters (player and enemies, mask 192).
@export var hits_all: bool = false:
	set(value):
		hits_all = value
		if is_inside_tree():
			_update_collision_mask()

## Whether this damage area deals friendly fire to allies of the wielder.
## If true, enemies can hit other enemies, or players can hit other players.
@export var friendly_fire: bool = false:
	set(value):
		friendly_fire = value
		if is_inside_tree():
			_update_collision_mask()

## Status effects applied to each victim when damaged.
@export var effects_to_apply: Array[GameplayEffect] = []:
	set(value):
		effects_to_apply = value
		_sync_attack_component()

## Character that created or owns this damage area. Excluded from taking self-damage.
var wielder: Character = null:
	set(value):
		wielder = value
		_sync_attack_component()
		if is_inside_tree():
			_update_collision_mask()

var _is_expired: bool = false

@onready var damage_hitbox: Area3D = $DamageHitbox
@onready var collision_shape: CollisionShape3D = $DamageHitbox/CollisionShape3D
@onready var attack_component: AttackComponent = $DamageHitbox/AttackComponent
var life_timer: Timer = null


func _get_damage_hitbox() -> Area3D:
	if damage_hitbox == null and is_inside_tree():
		damage_hitbox = get_node_or_null("DamageHitbox") as Area3D
	return damage_hitbox


func _get_collision_shape() -> CollisionShape3D:
	if collision_shape == null and is_inside_tree():
		collision_shape = get_node_or_null("DamageHitbox/CollisionShape3D") as CollisionShape3D
	return collision_shape


func _get_attack_component() -> AttackComponent:
	if attack_component == null and is_inside_tree():
		attack_component = get_node_or_null("DamageHitbox/AttackComponent") as AttackComponent
	return attack_component


func _get_life_timer() -> Timer:
	if life_timer == null and is_inside_tree():
		life_timer = get_node_or_null("LifeTimer") as Timer
	return life_timer


func _ready() -> void:
	var col: CollisionShape3D = _get_collision_shape()
	if col != null and col.shape != null:
		col.shape = col.shape.duplicate()

	var att: AttackComponent = _get_attack_component()
	if att != null and effects_to_apply.is_empty() and not att.effects_to_apply.is_empty():
		effects_to_apply = att.effects_to_apply

	_update_collision_mask()
	_sync_attack_component()

	if Engine.is_editor_hint():
		return

	if duration > 0.0:
		_setup_duration_timer()


## Updates collision masks to match target settings.
func _update_collision_mask() -> void:
	var hitbox: Area3D = _get_damage_hitbox()
	if hitbox == null:
		return
	hitbox.collision_layer = 0
	var mask: int = 0
	if hits_all:
		mask = 64 | 128
	else:
		if can_hit_player:
			mask |= 64
		if can_hit_enemies:
			mask |= 128
		if friendly_fire:
			if wielder != null:
				if wielder.is_in_group("enemy") or (wielder.has_method("is_enemy") and wielder.is_enemy()):
					mask |= 128
				elif wielder.is_in_group("player") or (wielder.has_method("is_player") and wielder.is_player()):
					mask |= 64
				else:
					mask |= 64 | 128
			else:
				if can_hit_player and not can_hit_enemies:
					mask |= 128
				elif can_hit_enemies and not can_hit_player:
					mask |= 64
				else:
					mask |= 64 | 128
	hitbox.collision_mask = mask


## Synchronizes exported damage properties to the underlying AttackComponent.
func _sync_attack_component() -> void:
	var att: AttackComponent = _get_attack_component()
	if att == null:
		return
	att.damage = damage
	att.damage_type = damage_type
	att.rehit_interval = damage_interval
	att.effects_to_apply = effects_to_apply
	if wielder != null:
		att.wielder = wielder

	if knockback_vector != Vector3.ZERO:
		att.knockback = knockback_vector
	elif knockback_force > 0.0:
		att.knockback = Vector3(0.0, knockback_force, 0.0)
	else:
		att.knockback = Vector3.ZERO


## Arms the duration timer if duration > 0.0.
func _setup_duration_timer() -> void:
	if Engine.is_editor_hint() or duration <= 0.0:
		return
	var timer: Timer = _get_life_timer()
	if timer == null:
		timer = Timer.new()
		timer.name = "LifeTimer"
		add_child(timer)
		life_timer = timer
	if not timer.timeout.is_connected(expire):
		timer.timeout.connect(expire)
	timer.wait_time = duration
	timer.one_shot = true
	timer.start()


## Assigns the character that cast or wielded this area damage.
func set_wielder(character: Character) -> void:
	wielder = character
	var att: AttackComponent = _get_attack_component()
	if att != null:
		att.wielder = character
	if is_inside_tree():
		_update_collision_mask()


## Immediately deals damage to any hurtboxes currently overlapping the hitbox Area3D.
func deal_damage() -> void:
	var att: AttackComponent = _get_attack_component()
	if att != null:
		att.deal_damage()


## Toggles the damage hitbox's monitoring/monitorable flags safely in every
## context. Area3D monitoring setters are locked while physics queries flush
## (the "Function blocked during in/out signal" engine error), which happens
## whenever this runs from a physics callback - a body_entered trigger, or a
## passive spawning this payload because another ability ended mid signal
## (e.g. the exit portal cancelling a dash during a scene transition). Writes
## are deferred there (the same guard WeaponSlot uses for its animated hit
## windows), so pre-existing overlaps are picked up by area_entered on the next
## physics step instead of a spawn-frame sweep.
func set_hitbox_active(monitoring_on: bool, monitorable_on: bool) -> void:
	var hitbox: Area3D = _get_damage_hitbox()
	if hitbox == null:
		return
	if Engine.is_in_physics_frame():
		hitbox.set_deferred("monitoring", monitoring_on)
		hitbox.set_deferred("monitorable", monitorable_on)
	else:
		hitbox.monitoring = monitoring_on
		hitbox.monitorable = monitorable_on


## Expires this damage area, disabling hits and cleaning up.
## Subclasses can override to add visual/audio fadeouts before freeing.
func expire() -> void:
	if _is_expired:
		return
	_is_expired = true

	var hitbox: Area3D = _get_damage_hitbox()
	if hitbox != null:
		hitbox.set_deferred("monitoring", false)
		hitbox.set_deferred("monitorable", false)

	queue_free()


## Returns whether this damage area has already expired.
func is_expired() -> bool:
	return _is_expired
