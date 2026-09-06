## Base projectile fired by enemies.
class_name EnemyProjectile
extends ShapeCast3D


func _physics_process(delta: float) -> void:
	global_position += global_basis.z * delta * 8.0
