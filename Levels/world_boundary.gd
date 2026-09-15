extends Area3D

func _ready() -> void:
	body_entered.connect(on_body_entered)

## Applies fatal damage to any entering body that possesses an
## AttributeComponent, dealing its full max health as lethal damage.
func on_body_entered(body: Node3D) -> void:
	if body.has_node("AttributeComponent"):
		var attributes: AttributeComponent = body.get_node("AttributeComponent") as AttributeComponent
		attributes.damage_pool(AttributeComponent.POOL_HEALTH, attributes.get_current(AttributeComponent.STAT_MAX_HEALTH))
		body.visible = false
