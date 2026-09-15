extends Area3D

func _ready() -> void:
	body_entered.connect(on_body_entered)

## Applies fatal damage to any entering body that possesses a HealthComponent
## and an AttributeComponent, dealing its full max health as lethal damage.
func on_body_entered(body: Node3D) -> void:
	if body.has_node("HealthComponent") and body.has_node("AttributeComponent"):
		var health_component: HealthComponent = body.get_node("HealthComponent") as HealthComponent
		var attributes: AttributeComponent = body.get_node("AttributeComponent") as AttributeComponent
		health_component.take_damage(attributes.get_current(AttributeComponent.STAT_MAX_HEALTH))
		body.visible = false
