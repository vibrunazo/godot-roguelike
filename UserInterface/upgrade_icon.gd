## UI card component displaying an item or upgrade option in the UpgradeShop.
## Dynamically populated from an assigned ItemResource.
## Runs as a tool script so editor previews render live from their assigned
## ItemResource whenever it is switched in the inspector.
@tool
class_name UpgradeIcon
extends PanelContainer

## Emitted when this upgrade/item card is selected and taken by the player.
signal upgrade_taken(card: UpgradeIcon)

## Item resource defining this card's title, formatting, cost, and gameplay effect.
## Assigning a new resource refreshes the card immediately, including in the
## editor inspector for live preview purposes.
@export var item_resource: ItemResource:
	set(value):
		_disconnect_resource_signal()
		item_resource = value
		_connect_resource_signal()
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

## Unique-name references so the card survives scene reparenting.
@onready var texture_button: TextureButton = %TextureButton
@onready var title: RichTextLabel = %Title
@onready var description: RichTextLabel = %Description
## Footer label pinning cost/stock to the bottom of the card so long
## descriptions scroll in the middle instead of pushing the cost off-panel.
@onready var cost_label: RichTextLabel = get_node_or_null("%CostLabel") as RichTextLabel
@onready var player: Character = get_tree().get_first_node_in_group("player") as Character

var _already_taken: bool = false


func _ready() -> void:
	_connect_resource_signal()
	if Engine.is_editor_hint():
		# Editor preview only: render from the assigned ItemResource.
		# Input and currency wiring stay runtime-only.
		setup_label()
		return
	texture_button.pressed.connect(take_upgrade)
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Character
	if ProgressionState != null and not ProgressionState.currency_gold_changed.is_connected(_on_currency_gold_changed):
		ProgressionState.currency_gold_changed.connect(_on_currency_gold_changed)
	setup_label()


func _exit_tree() -> void:
	_disconnect_resource_signal()
	if Engine.is_editor_hint():
		return
	if ProgressionState != null and ProgressionState.currency_gold_changed.is_connected(_on_currency_gold_changed):
		ProgressionState.currency_gold_changed.disconnect(_on_currency_gold_changed)


func _on_currency_gold_changed(_new_amount: int) -> void:
	setup_label()


## Refreshes the card when the assigned resource reports an in-place edit,
## e.g. tweaking the .tres in the inspector while previewing in the editor.
func _on_item_resource_changed() -> void:
	setup_label()


## Tracks the assigned resource's changed signal for live preview updates.
func _connect_resource_signal() -> void:
	if item_resource != null and is_instance_valid(item_resource) and not item_resource.changed.is_connected(_on_item_resource_changed):
		item_resource.changed.connect(_on_item_resource_changed)


## Stops tracking the previous resource before it is replaced or freed.
func _disconnect_resource_signal() -> void:
	if item_resource != null and is_instance_valid(item_resource) and item_resource.changed.is_connected(_on_item_resource_changed):
		item_resource.changed.disconnect(_on_item_resource_changed)


## Assigns an ItemResource and refreshes the card's visual elements.
func set_item_resource(resource: ItemResource) -> void:
	item_resource = resource


## Compatibility alias for set_item_resource.
func set_upgrade_resource(resource: ItemResource) -> void:
	set_item_resource(resource)


## Applies the item effect to the player, deducts cost, and signals completion.
## Never runs in the editor: preview cards are not purchasable.
func take_upgrade() -> void:
	if Engine.is_editor_hint():
		return
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
		description.text = desc_text

		# Cost and stock live in the pinned footer so they stay readable no
		# matter how long the description above grows.
		var footer_text: String = ""
		if item_resource.cost > 0:
			footer_text += "[color=gold]Cost: %d Gold[/color]" % item_resource.cost

		if player != null and player.equipment_component != null and item_resource.max_purchases > 0:
			var owned: int = player.equipment_component.get_purchase_count(item_resource)
			if not footer_text.is_empty():
				footer_text += "  "
			footer_text += "[color=gray](%d/%d owned)[/color]" % [owned, item_resource.max_purchases]

		_set_cost_footer(footer_text)

		# Update button interactability based on affordability and stock.
		# The currency check is runtime-only; editor previews stay enabled.
		if texture_button != null and not _already_taken:
			var can_buy: bool = true
			if player != null and player.equipment_component != null:
				can_buy = player.equipment_component.can_purchase(item_resource)
			elif not Engine.is_editor_hint() and ProgressionState != null and item_resource.cost > 0:
				can_buy = ProgressionState.has_gold(item_resource.cost)

			texture_button.disabled = not can_buy

	elif stat_bonus != 0.0 and player != null and player.attribute_component != null and not stat_name.is_empty():
		var label_attrs: AttributeComponent = player.attribute_component
		description.text = text_template % [label_attrs.get_current(StringName(stat_name)), label_attrs.get_current(StringName(stat_name)) + stat_bonus]
		_set_cost_footer("")


## Writes the pinned cost/stock footer. Falls back to appending onto the
## description when the footer node is missing (e.g. an outdated card scene).
func _set_cost_footer(footer_text: String) -> void:
	if cost_label == null:
		if not footer_text.is_empty():
			description.text += "\n\n" + footer_text
		return
	cost_label.visible = not footer_text.is_empty()
	cost_label.text = footer_text
