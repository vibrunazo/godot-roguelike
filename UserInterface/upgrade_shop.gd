## Shop screen presenting dynamic data-driven upgrade choices to the player.
extends Control

## Scene used to instantiate upgrade cards. Falls back to GlobalVars.upgrade_icon_scene if unset.
@export var upgrade_card_scene: PackedScene

## Upgrade resources offered by this shop. Falls back to GlobalVars.upgrades if empty.
@export var available_upgrades: Array[UpgradeResource] = []

@onready var upgrade_container: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer

var exiting_shop: bool = false


func _ready() -> void:
	var card_scene: PackedScene = upgrade_card_scene
	if card_scene == null:
		card_scene = GlobalVars.upgrade_icon_scene

	var pool: Array[UpgradeResource] = available_upgrades
	if pool.is_empty():
		pool = GlobalVars.upgrades

	var upgrade_options: Array[UpgradeResource] = pool.duplicate()
	upgrade_options.shuffle()
	for resource: UpgradeResource in upgrade_options.slice(0, 2):
		var current_upgrade: UpgradeIcon = card_scene.instantiate() as UpgradeIcon
		upgrade_container.add_child(current_upgrade)
		current_upgrade.set_upgrade_resource(resource)
		current_upgrade.upgrade_taken.connect(exit_shop)


func exit_shop(upgrade_in: UpgradeIcon) -> void:
	if exiting_shop:
		return
	exiting_shop = true
	SceneTransition.load_next_level()
