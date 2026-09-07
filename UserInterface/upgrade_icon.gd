extends PanelContainer
class_name UpgradeIcon

@export var text_template: String = "A description."
@export var stat_name: String
@export var stat_bonus: float = 0.0

@onready var texture_button: TextureButton = $TextureButton
@onready var title: RichTextLabel = $VBoxContainer/Title
@onready var description: RichTextLabel = $VBoxContainer/Control/Description
@onready var player: Player = get_tree().get_first_node_in_group("player") as Player

func _ready() -> void:
	texture_button.pressed.connect(take_upgrade)

func take_upgrade() -> void:
	if texture_button != null and texture_button.disabled:
		return
	if texture_button != null:
		texture_button.disabled = true
	if stat_bonus:
		player.set(stat_name, player.get(stat_name) + stat_bonus)
