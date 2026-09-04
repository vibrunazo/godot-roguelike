extends Node
class_name AttackComponent

var temporary_exceptions: Array[CollisionObject3D] = []

@onready var attack_shapecast: ShapeCast3D = get_parent()

func deal_damage(damage: float, knockback: Vector3) -> void:
	if attack_shapecast.enabled == false: return
	attack_shapecast.force_shapecast_update()
	for index: int in attack_shapecast.get_collision_count():
		var collider: CollisionObject3D = attack_shapecast.get_collider(index) as CollisionObject3D
		if collider and collider.has_node("HealthComponent"):
			var health_component: HealthComponent = collider.get_node("HealthComponent") as HealthComponent
			health_component.take_damage(damage)
			attack_shapecast.add_exception(collider)
			temporary_exceptions.append(collider)
			
func reset_exceptions() -> void:
	for exception: CollisionObject3D in temporary_exceptions:
		attack_shapecast.remove_exception(exception)
	temporary_exceptions = []
