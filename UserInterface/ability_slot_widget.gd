## One HUD ability slot: the ability's icon, a radial cooldown sweep, the key
## that casts it, and a dimmed look while it cannot be cast. Driven by
## AbilityBar; purely visual.
class_name AbilitySlotWidget
extends Control

## Shows the ability's icon.
@export var icon_rect: TextureRect
## Dark radial overlay sweeping away as the cooldown runs out.
@export var cooldown_bar: TextureProgressBar
## Shows the key bound to the slot.
@export var key_label: Label
## Modulate applied to the icon while the ability cannot be cast (cooldown,
## missing cost, blocked tags).
@export var unready_modulate: Color = Color(0.55, 0.55, 0.55, 1.0)


func _ready() -> void:
	var required: Dictionary[String, Object] = {"icon_rect": icon_rect, "cooldown_bar": cooldown_bar, "key_label": key_label}
	for export_name: String in required:
		if required[export_name] == null:
			push_error("AbilitySlotWidget '%s': %s is not set." % [name, export_name])


## Shows the key text bound to this slot (empty hides the label).
func set_key_text(text: String) -> void:
	key_label.text = text
	key_label.visible = not text.is_empty()


## Shows ability in this slot (null: an empty slot).
func set_ability(ability: AbilityResource) -> void:
	icon_rect.texture = ability.icon if ability != null else null
	icon_rect.visible = ability != null
	tooltip_text = ability.display_name if ability != null else ""
	if ability == null:
		cooldown_bar.value = 0.0


## Updates the cooldown sweep (fraction left, 1.0 just cast) and readiness.
func set_cooldown(fraction_left: float, ready: bool) -> void:
	cooldown_bar.value = fraction_left
	icon_rect.modulate = Color.WHITE if ready else unready_modulate
