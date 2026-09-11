## UI card component displaying an upgrade option in the UpgradeShop.
## Dynamically populated from an assigned UpgradeResource.
class_name UpgradeIcon
extends PanelContainer

## Emitted when this upgrade card is selected and taken by the player.
signal upgrade_taken(this: UpgradeIcon)

## Upgrade resource defining this card's title, formatting, and gameplay effect.
@export var upgrade_resource: UpgradeResource:
	set(value):
		upgrade_resource = value
		setup_label()

## Fallback text template used if upgrade_resource is not set.
@export_multiline() var text_template: String = "%.1f -> [color='7fffd4']%.1f[/color] m/s"
## Fallback stat name used if upgrade_resource is not set.
@export var stat_name: String = ""
## Fallback stat bonus used if upgrade_resource is not set.
@export var stat_bonus: float = 0.0

@onready var texture_button: TextureButton = $TextureButton
@onready var title: RichTextLabel = $VBoxContainer/Title
@onready var description: RichTextLabel = $VBoxContainer/Control/Description
@onready var player: Character = get_tree().get_first_node_in_group("player") as Character


func _ready() -> void:
	texture_button.pressed.connect(take_upgrade)
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Character
	setup_label()


## Assigns an UpgradeResource and refreshes the card's visual elements.
func set_upgrade_resource(resource: UpgradeResource) -> void:
	upgrade_resource = resource
	setup_label()


## Applies the upgrade effect to the player and signals completion.
func take_upgrade() -> void:
	if texture_button != null and texture_button.disabled:
		return
	get_tree().call_group("upgrade_button", "set_disabled", true)
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Character

	if upgrade_resource != null:
		upgrade_resource.apply(player)
	elif stat_bonus != 0.0 and player != null:
		player.set(stat_name, player.get(stat_name) + stat_bonus)

	upgrade_taken.emit(self)


## Populates the title and description labels from upgrade_resource or fallback properties.
func setup_label() -> void:
	if not is_inside_tree() or title == null or description == null:
		return
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Character

	if upgrade_resource != null:
		if not upgrade_resource.title.is_empty():
			title.text = upgrade_resource.title
		description.text = upgrade_resource.format_description(player)
	elif stat_bonus != 0.0 and player != null:
		description.text = text_template % [player.get(stat_name), player.get(stat_name) + stat_bonus]
