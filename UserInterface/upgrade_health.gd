extends UpgradeIcon
class_name UpgradeHealth

@export var health_bonus: float = 20.0

func setup_label() -> void:
	if player != null and player.health_component != null:
		description.text = text_template % [player.health_component.max_health, player.health_component.max_health + health_bonus]

func take_upgrade() -> void:
	if texture_button != null and texture_button.disabled:
		return
	super.take_upgrade()
	if player != null and player.health_component != null:
		player.health_component.max_health += health_bonus
		player.health_component.current_health += health_bonus

