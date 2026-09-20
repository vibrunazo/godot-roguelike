extends Control

## Shop overlay shown between levels. The gold count is intentionally NOT
## rendered here: the HUD (owned by the UI autoload) persists across the
## level -> shop -> level transitions, so its gold label is the single,
## continuous gold display for the whole run.

## Scene used to instantiate item/upgrade cards. Falls back to GlobalVars.upgrade_icon_scene if unset.
@export var upgrade_card_scene: PackedScene

## Item resources offered by this shop. Falls back to GlobalVars.items if empty.
@export var available_items: Array[ItemResource] = []

## Unique-name references (%HBoxContainer, %LeaveButton) so these survive
## scene reparenting: only the node name matters, not its path.
@onready var upgrade_container: HBoxContainer = %HBoxContainer
@onready var leave_button: Button = get_node_or_null("%LeaveButton") as Button

var exiting_shop: bool = false


func _ready() -> void:
	if leave_button != null:
		leave_button.pressed.connect(leave_shop)

	# The scene holds editor-only mock preview cards (metadata "mock_preview")
	# for visual layout debugging. The game never shows them: drop every
	# pre-existing placeholder before dealing real item cards.
	for child: Node in upgrade_container.get_children():
		upgrade_container.remove_child(child)
		child.queue_free()

	var card_scene: PackedScene = upgrade_card_scene
	if card_scene == null and GlobalVars != null:
		card_scene = GlobalVars.upgrade_icon_scene
	if card_scene == null:
		return

	var pool: Array[ItemResource] = available_items
	if pool.is_empty() and GlobalVars != null:
		pool = GlobalVars.items

	var item_options: Array[ItemResource] = pool.duplicate()
	item_options.shuffle()
	for resource: ItemResource in item_options.slice(0, 2):
		var current_card: UpgradeIcon = card_scene.instantiate() as UpgradeIcon
		upgrade_container.add_child(current_card)
		current_card.set_item_resource(resource)
		current_card.upgrade_taken.connect(exit_shop)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		leave_shop()
		get_viewport().set_input_as_handled()


## Cancels out of shop without selecting an upgrade.
func leave_shop() -> void:
	exit_shop(null)


func exit_shop(_item_in: UpgradeIcon = null) -> void:
	if exiting_shop:
		return
	exiting_shop = true
	SceneTransition.load_next_level()
