extends Control

@onready var upgrade_container: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer

var exiting_shop: bool = false

func _ready() -> void:
	for child in upgrade_container.get_children():
		child.upgrade_taken.connect(exit_shop)

func exit_shop(upgrade_in: UpgradeIcon) -> void:
	if exiting_shop:
		return
	exiting_shop = true
	SceneTransition.load_next_level()
