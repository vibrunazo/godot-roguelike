## Player-only: shows the game-over screen shortly after the player's defeat,
## letting the death animation and corpse read before the menu takes over. The
## run itself resets only when restart is chosen from the menu.
class_name PlayerDefeatHandler
extends Node

## The player whose defeat ends the run.
@export var character: Character
## Seconds between the player's defeat and the game-over screen.
@export var menu_delay: float = 2.0


func _ready() -> void:
	if character == null:
		push_error("%s: character is not set." % name)
		return
	character.defeat.connect(_on_defeat)


func _on_defeat() -> void:
	# Menu timing is presentation, so it may run on the render clock.
	await get_tree().create_timer(menu_delay).timeout
	if is_inside_tree():
		UI.show_game_over()
