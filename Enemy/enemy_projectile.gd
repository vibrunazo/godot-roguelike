## Base projectile fired by enemies.
class_name EnemyProjectile
extends ShapeCast3D

## Movement speed of the projectile.
@export var speed: float = 8.0
## Damage dealt to entities hit by this projectile.
@export var damage: float = 5.0

@onready var attack_component: AttackComponent = $AttackComponent


func _physics_process(delta: float) -> void:
	global_position += global_basis.z * delta * speed
	attack_component.deal_damage(damage, Vector3.ZERO)
	if is_colliding():
		queue_free()


func _on_timer_timeout() -> void:
	queue_free()

