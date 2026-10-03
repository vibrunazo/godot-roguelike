## One entry of an enemy's loot table (EnemyResource.item_drops): an item and
## the chance it drops when the enemy is defeated. LootComponent rolls every
## entry on its own and drops the item only when the run may offer it (see
## ProgressionState.can_drop()) and it does not already lie in the level.
class_name LootDrop
extends Resource

## The item dropped (a spell book, ...). Needs a world_visual to lie in levels.
@export var item: ItemResource
## Chance per defeat that the item drops (0.2 = 20%).
@export_range(0.0, 1.0, 0.01) var chance: float = 0.2
