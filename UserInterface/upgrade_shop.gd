extends Control

@onready var upgrade_container: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer

var exiting_shop: bool = false

func _ready() -> void:
	var upgrade_options: Array[PackedScene] = GlobalVars.upgrades.duplicate()
	upgrade_options.shuffle()
	for child: PackedScene in upgrade_options.slice(0, 2):
		var current_upgrade: UpgradeIcon = child.instantiate() as UpgradeIcon
		upgrade_container.add_child(current_upgrade)
		current_upgrade.upgrade_taken.connect(exit_shop)

func exit_shop(upgrade_in: UpgradeIcon) -> void:
	if exiting_shop:
		return
	exiting_shop = true
	SceneTransition.load_next_level()
