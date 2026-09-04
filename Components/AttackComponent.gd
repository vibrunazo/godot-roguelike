extends Node
class_name AttackComponent

var temporary_exceptions := []

@onready var attack_shapecast: ShapeCast3D = get_parent()

func deal_damage(damage: float, knockback: Vector3) -> void:
	if attack_shapecast.enabled == false: return
	attack_shapecast.force_shapecast_update()
	for index in attack_shapecast.get_collision_count():
		var collider = attack_shapecast.get_collider(index)
		if collider.has_node("HealthComponent"):
			var health_component = collider.get_node("HealthComponent") as HealthComponent
			health_component.take_damage(damage)
			attack_shapecast.add_exception(collider)
			temporary_exceptions.append(collider)
			
func reset_exceptions() -> void:
	for exception in temporary_exceptions:
		attack_shapecast.remove_exception(exception)
	temporary_exceptions = []
