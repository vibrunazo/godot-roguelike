## UI card component displaying an item or upgrade option in the UpgradeShop.
## Dynamically populated from an assigned ItemResource.
class_name UpgradeIcon
extends PanelContainer

## Emitted when this upgrade/item card is selected and taken by the player.
signal upgrade_taken(card: UpgradeIcon)

## Item resource defining this card's title, formatting, cost, and gameplay effect.
@export var item_resource: ItemResource:
	set(value):
		item_resource = value
		setup_label()

## Compatibility alias for item_resource.
var upgrade_resource: ItemResource:
	get:
		return item_resource
	set(value):
		item_resource = value

## Fallback text template used if item_resource is not set.
@export_multiline var text_template: String = "%.1f -> [color='7fffd4']%.1f[/color] m/s"
## Fallback attribute name on AttributeComponent used if item_resource is not set.
@export var stat_name: String = ""
## Fallback stat bonus used if item_resource is not set.
@export var stat_bonus: float = 0.0

@onready var texture_button: TextureButton = $TextureButton
@onready var title: RichTextLabel = $VBoxContainer/Title
@onready var description: RichTextLabel = $VBoxContainer/Control/Description
@onready var player: Character = get_tree().get_first_node_in_group("player") as Character

var _already_taken: bool = false


func _ready() -> void:
	texture_button.pressed.connect(take_upgrade)
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Character
	if ProgressionState != null and not ProgressionState.currency_gold_changed.is_connected(_on_currency_gold_changed):
		ProgressionState.currency_gold_changed.connect(_on_currency_gold_changed)
	setup_label()


func _exit_tree() -> void:
	if ProgressionState != null and ProgressionState.currency_gold_changed.is_connected(_on_currency_gold_changed):
		ProgressionState.currency_gold_changed.disconnect(_on_currency_gold_changed)


func _on_currency_gold_changed(_new_amount: int) -> void:
	setup_label()


## Assigns an ItemResource and refreshes the card's visual elements.
func set_item_resource(resource: ItemResource) -> void:
	item_resource = resource


## Compatibility alias for set_item_resource.
func set_upgrade_resource(resource: ItemResource) -> void:
	set_item_resource(resource)


## Applies the item effect to the player, deducts cost, and signals completion.
func take_upgrade() -> void:
	if _already_taken or (texture_button != null and texture_button.disabled):
		return

	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Character

	if item_resource != null:
		# Check affordability and stock
		if player != null and player.equipment_component != null:
			if not player.equipment_component.can_purchase(item_resource):
				return
		elif ProgressionState != null and not ProgressionState.has_gold(item_resource.cost):
			return

		# Deduct gold
		if ProgressionState != null and item_resource.cost > 0:
			var spent: bool = ProgressionState.spend_gold(item_resource.cost)
			if not spent:
				return

		# Apply item to character
		if player != null:
			if player.equipment_component != null:
				player.equipment_component.apply_item(item_resource)
				player.equipment_component.record_purchase(item_resource)
			else:
				item_resource.apply(player)

	elif stat_bonus != 0.0 and player != null and player.attribute_component != null and not stat_name.is_empty():
		var fallback_attrs: AttributeComponent = player.attribute_component
		fallback_attrs.set_base(StringName(stat_name), fallback_attrs.get_base(StringName(stat_name)) + stat_bonus)

	_already_taken = true
	if texture_button != null:
		texture_button.disabled = true
	get_tree().call_group("upgrade_button", "set_disabled", true)
	upgrade_taken.emit(self)


## Populates the title and description labels from item_resource or fallback properties.
func setup_label() -> void:
	if not is_inside_tree() or title == null or description == null:
		return
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Character

	if item_resource != null:
		if not item_resource.title.is_empty():
			title.text = item_resource.title

		# Flavor text first, then the stat changes auto-calculated from the
		# item's actual effects (descriptions carry no stat numbers).
		var desc_text: String = item_resource.description
		var stat_text: String = item_resource.get_stat_summary(player)
		if not stat_text.is_empty():
			desc_text += "\n\n" + stat_text
		var extra_info: String = ""

		if item_resource.cost > 0:
			extra_info += "\n\n[color=gold]Cost: %d Gold[/color]" % item_resource.cost

		if player != null and player.equipment_component != null and item_resource.max_purchases > 0:
			var owned: int = player.equipment_component.get_purchase_count(item_resource)
			extra_info += "  [color=gray](%d/%d owned)[/color]" % [owned, item_resource.max_purchases]

		description.text = desc_text + extra_info

		# Update button interactability based on affordability and stock
		if texture_button != null and not _already_taken:
			var can_buy: bool = true
			if player != null and player.equipment_component != null:
				can_buy = player.equipment_component.can_purchase(item_resource)
			elif ProgressionState != null and item_resource.cost > 0:
				can_buy = ProgressionState.has_gold(item_resource.cost)

			texture_button.disabled = not can_buy

	elif stat_bonus != 0.0 and player != null and player.attribute_component != null and not stat_name.is_empty():
		var label_attrs: AttributeComponent = player.attribute_component
		description.text = text_template % [label_attrs.get_current(StringName(stat_name)), label_attrs.get_current(StringName(stat_name)) + stat_bonus]
