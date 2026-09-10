## Base projectile fired by enemies.
class_name EnemyProjectile
extends Area3D

## Movement speed of the projectile.
@export var speed: float = 8.0
## Damage dealt to entities hit by this projectile.
@export var damage: float = 5.0
## Knockback impulse applied to entities hit by this projectile.
@export var knockback: float = 15.0
## Character that fired this projectile. Used to ignore self-collision now that
## projectiles parent to the world instead of their shooter.
var shooter: Character

@onready var attack_component: AttackComponent = $AttackComponent

var _is_hit: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if attack_component:
		attack_component.damage = damage


func _physics_process(delta: float) -> void:
	global_position += global_basis.z * delta * speed


func _on_body_entered(body: Node3D) -> void:
	if _is_hit or is_queued_for_deletion():
		return
	if body == self or body is Character:
		return
	_is_hit = true
	hit_effect()
	queue_free()


func _on_area_entered(area: Area3D) -> void:
	if _is_hit or is_queued_for_deletion():
		return
	if area == self or not (area is Hurtbox) or area.get_parent() == shooter:
		return
	_is_hit = true
	if attack_component:
		attack_component.deal_damage_to(area as Hurtbox, damage, global_basis.z * knockback)
	hit_effect()
	queue_free()


func is_colliding() -> bool:
	return has_overlapping_bodies() or has_overlapping_areas()


func hit_effect() -> void:
	var fireball: Node3D = (GlobalVars.fireball_hit_scene as PackedScene).instantiate() as Node3D
	VfxManager.spawn_world_entity(fireball)
	fireball.global_position = global_position


func _on_timer_timeout() -> void:
	queue_free()
