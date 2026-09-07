extends PanelContainer
class_name UpgradeIcon

@export var text_template: String = "A description."

@onready var texture_button: TextureButton = $TextureButton
@onready var title: RichTextLabel = $VBoxContainer/Title
@onready var description: RichTextLabel = $VBoxContainer/Control/Description
@onready var player: Player = get_tree().get_first_node_in_group("player") as Player
