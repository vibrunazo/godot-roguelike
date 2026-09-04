extends Area3D

func _ready() -> void:
	body_entered.connect(on_body_entered)

## Applies fatal damage to any entering body that possesses a HealthComponent
func on_body_entered(body: Node3D) -> void:
	if body.has_node("HealthComponent"):
		var health_component: HealthComponent = body.get_node("HealthComponent") as HealthComponent
		health_component.take_damage(health_component.max_health)
