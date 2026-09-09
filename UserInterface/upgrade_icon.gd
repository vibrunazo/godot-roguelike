extends PanelContainer
class_name UpgradeIcon

signal upgrade_taken(this: UpgradeIcon)

@export_multiline() var text_template: String = "%.1f -> [color='7fffd4']%.1f[/color] m/s"
@export var stat_name: String
@export var stat_bonus: float = 0.0

@onready var texture_button: TextureButton = $TextureButton
@onready var title: RichTextLabel = $VBoxContainer/Title
@onready var description: RichTextLabel = $VBoxContainer/Control/Description
@onready var player: Character = get_tree().get_first_node_in_group("player") as Character

func _ready() -> void:
	texture_button.pressed.connect(take_upgrade)
	setup_label()

func take_upgrade() -> void:
	if texture_button != null and texture_button.disabled:
		return
	get_tree().call_group("upgrade_button", "set_disabled", true)
	if stat_bonus:
		player.set(stat_name, player.get(stat_name) + stat_bonus)
	upgrade_taken.emit(self)

func setup_label() -> void:
	if stat_bonus and player != null:
		description.text = text_template % [player.get(stat_name), player.get(stat_name) + stat_bonus]
