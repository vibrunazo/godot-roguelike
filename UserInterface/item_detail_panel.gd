## Reusable item detail column for the pause menu concept layout.
## Wraps an INSPECT-mode UpgradeIcon card under an "ITEM DETAILS" header.
## Used by PauseMenu (column 2); card_mode stays configurable so shops can
## reuse this panel for purchasable cards in the future.
class_name ItemDetailPanel
extends VBoxContainer

## Usage context forwarded to the inner card. INSPECT hides cost and disables
## purchasing (pause/inventory); SHOP enables it.
@export var card_mode: UpgradeIcon.CardMode = UpgradeIcon.CardMode.INSPECT:
	set(value):
		card_mode = value
		_apply_card_mode()

## Inspect card showing the selected gear.
@onready var details_card: UpgradeIcon = %DetailsCard


func _ready() -> void:
	_apply_card_mode()


## Shows a gear resource in the details card. A null resource hides the card
## (e.g. empty inventory placeholder rows).
func set_item(gear: GearItemResource) -> void:
	if details_card == null:
		return
	if gear == null:
		details_card.visible = false
		return
	details_card.visible = true
	details_card.set_item_resource(gear)


## Returns the gear currently shown in the card, or null when hidden/empty.
func get_shown_item() -> GearItemResource:
	if details_card == null or not details_card.visible:
		return null
	return details_card.item_resource as GearItemResource


func _apply_card_mode() -> void:
	if details_card == null or not is_node_ready():
		return
	details_card.card_mode = card_mode
