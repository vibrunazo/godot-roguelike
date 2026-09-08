## Base projectile fired by enemies.
class_name EnemyProjectile
extends ShapeCast3D

const FIREBALL_HIT: PackedScene = preload("res://Enemy/fireball_hit.tscn")

## Movement speed of the projectile.
@export var speed: float = 8.0
## Damage dealt to entities hit by this projectile.
@export var damage: float = 5.0
## Knockback impulse applied to entities hit by this projectile.
@export var knockback: float = 15.0

@onready var attack_component: AttackComponent = $AttackComponent


func _physics_process(delta: float) -> void:
	global_position += global_basis.z * delta * speed
	attack_component.deal_damage(damage, global_basis.z * knockback)
	if is_colliding():
		hit_effect()
		queue_free()


func hit_effect() -> void:
	var fireball: Node3D = FIREBALL_HIT.instantiate() as Node3D
	get_parent().add_child(fireball)
	fireball.global_position = global_position


func _on_timer_timeout() -> void:
	queue_free()

