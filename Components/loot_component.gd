## Enemy-only: awards the run gold for this enemy when it is defeated, from its
## EnemyResource (Character.enemy_resource, which waves set; an enemy spawned
## any other way is looked up in GlobalVars.enemies by its scene). An enemy
## with no registered archetype awards nothing.
class_name LootComponent
extends Node

## The enemy whose defeat awards the gold.
@export var character: Character


func _ready() -> void:
	if character == null:
		push_error("%s: character is not set." % name)
		return
	character.defeat.connect(_on_defeat)


## The gold this enemy is worth (0 without a registered archetype).
func gold_drop() -> int:
	var resource: EnemyResource = character.enemy_resource
	if resource == null:
		resource = GlobalVars.get_enemy_resource_for_path(character.scene_file_path)
	return resource.gold_drop if resource != null else 0


func _on_defeat() -> void:
	ProgressionState.add_gold(gold_drop())
