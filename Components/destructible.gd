## A world prop with a health pool that breaks when it runs out: a barrel, a
## crate, a vase. Reusable root for every destructible; what makes one
## different is data, not code:
## - the health pool (its AttributeComponent's base_max_health),
## - the break_payload, a scene released where the prop stood (an explosion,
##   a pickup drop, debris; none means it just disappears),
## - the fuse_time between being destroyed and breaking.
## Anything that damages a Hurtbox breaks it (weapons, projectiles, abilities,
## hazards, explosions, burns), so a blast chains into its neighbours with no
## special casing. Scenes put the prop's Hurtbox on both team hurtbox layers
## (192), so player and enemy attacks alike can hit it, and wire it to the
## same AttributeComponent this node watches.
class_name Destructible
extends Node3D

## Emitted once when the health pool reaches zero, at the start of the fuse.
signal destroyed
## Emitted when the fuse ends, as the payload is released and the prop frees.
signal broke

## Health pool of the prop. The scene's Hurtbox damages this same component.
@export var attribute_component: AttributeComponent
## Scene spawned at the prop's position when it breaks, through
## PayloadSpawner (an explosion DamageArea, for instance). Null: the prop
## just disappears.
@export var break_payload: PackedScene
## Seconds between running out of health and breaking, on the physics clock.
## A short fuse lets the prop read as hit, and staggers chain reactions so a
## row of explosive props goes off one after the other.
@export var fuse_time: float = 0.0


func _ready() -> void:
	if attribute_component == null:
		push_error("%s: attribute_component is not set." % name)
		return
	attribute_component.defeat.connect(_on_defeat)


## Starts the fuse. The Hurtbox has already switched itself off on the same
## defeat, so nothing can hit the prop again while it burns down.
func _on_defeat() -> void:
	destroyed.emit()
	get_tree().create_timer(fuse_time, true, true).timeout.connect(_break)


## Releases the payload where the prop stood and removes the prop.
func _break() -> void:
	if break_payload != null:
		PayloadSpawner.spawn(break_payload, null, global_position)
	broke.emit()
	queue_free()
