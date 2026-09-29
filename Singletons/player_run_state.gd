## The player's run progress that outlives any one player node, held by
## ProgressionState.player_state. Every level spawns its own fresh Player, so
## nothing from the last scene (timers, tweens, ready-time snapshots such as
## the camera's floor, status visuals, a half-finished dash) can leak into the
## next one; instead SceneTransition captures this state from the outgoing
## player and the next level applies it to its own player on spawn.
class_name PlayerRunState
extends RefCounted

## Every gear equip of the run, in order (gear bought twice appears twice).
var gear: Array[GearItemResource] = []
## Pool values (health, mana) when the last player left its scene. Empty until
## then, so the first player keeps its full pools.
var pools: Dictionary[StringName, float] = {}
## Items bought while no player existed (the shop between levels), applied in
## order to the next player on spawn.
var pending_items: Array[ItemResource] = []


## Records the outgoing player's gear and pools.
func capture(player: Character) -> void:
	gear.assign(player.equipment_component.gear_history)
	pools.clear()
	for pool: StringName in AttributeComponent.POOL_NAMES:
		pools[pool] = player.attribute_component.get_current(pool)


## Gives a freshly spawned player the run's gear (its lasting part only: the
## instant effects happened when it was first equipped), then its pools, then
## the pending items.
func apply_to(player: Character) -> void:
	for piece: GearItemResource in gear:
		player.equipment_component.restore_gear(piece)
	for pool: StringName in pools:
		player.attribute_component.set_pool_current(pool, pools[pool])
	for item: ItemResource in pending_items:
		player.equipment_component.apply_item(item)
	pending_items.clear()
