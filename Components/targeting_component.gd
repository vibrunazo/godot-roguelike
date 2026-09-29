## Auto-aim for a character (the player): acquires the nearest living opponent
## within auto_aim_range as the character's current_target, re-evaluates it at
## most every target_retarget_cooldown seconds so it does not flicker between
## candidates at similar distances, never switches it mid-attack, and drops it
## the moment it dies. Characters without this component never auto-aim.
class_name TargetingComponent
extends Node

## The character whose current_target this component maintains.
@export var character: Character
## Maximum distance in meters at which auto-aim acquires opposing characters.
## Values <= 0.0 disable acquisition.
@export var auto_aim_range: float = 10.0
## Minimum interval in seconds between auto-aim target re-evaluations, so the
## target does not flicker every tick when candidates sit at similar distances.
@export var target_retarget_cooldown: float = 0.3

## Time in seconds until the next allowed re-evaluation.
var _retarget_timer: float = 0.0
## The character whose defeat is watched (the current target, if a Character).
var _watched_target: Character = null


func _ready() -> void:
	# Aim before the body states act on it this frame, like the controllers.
	process_physics_priority = -1
	if character == null:
		push_error("%s: character is not set." % name)
		return
	character.target_changed.connect(_on_target_changed)


## Resets the retarget cooldown so the next physics tick re-evaluates the
## target immediately.
func force_retarget() -> void:
	_retarget_timer = 0.0


## Advances auto-aim: drops invalid targets. With no target held it checks for
## one every tick, for immediate acquisition; once a target is held it waits
## target_retarget_cooldown before switching. Never changes the target while
## an attack runs (combo chains stay inside attack states), except clearing a
## freed node so no dangling reference is held.
func _physics_process(delta: float) -> void:
	if character == null or auto_aim_range <= 0.0 or not character.is_inside_tree() or not character.is_alive():
		return
	var target: Node3D = character.current_target
	if character.is_attacking:
		if target != null and not is_instance_valid(target):
			character.set_current_target(null)
		return
	if not _is_valid(target):
		character.set_current_target(null)
	if character.current_target == null:
		_acquire_nearest()
		_retarget_timer = target_retarget_cooldown
		return
	_retarget_timer -= delta
	if _retarget_timer > 0.0:
		return
	_retarget_timer = target_retarget_cooldown
	_acquire_nearest()


## Targets the nearest living opponent when it is within auto_aim_range.
func _acquire_nearest() -> void:
	var nearest: Character = character.get_nearest_target()
	if nearest != null and character.global_position.distance_to(nearest.global_position) <= auto_aim_range:
		character.set_current_target(nearest)


## True when target is still a usable aim point: a live node within range
## (Characters must also be alive).
func _is_valid(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Character and not (target as Character).is_alive():
		return false
	return character.global_position.distance_to(target.global_position) <= auto_aim_range


## Watches the new target's death so a kill drops it at once instead of
## lingering until the next tick; a cleared target re-arms immediate
## re-evaluation.
func _on_target_changed(new_target: Node3D) -> void:
	if _watched_target != null and is_instance_valid(_watched_target) and _watched_target.defeat.is_connected(_on_target_defeat):
		_watched_target.defeat.disconnect(_on_target_defeat)
	_watched_target = new_target as Character
	if _watched_target != null:
		_watched_target.defeat.connect(_on_target_defeat)
	if new_target == null:
		_retarget_timer = 0.0


## Drops a killed target the frame it dies, so the next tick outside an attack
## acquires a living replacement without waiting out the cooldown.
func _on_target_defeat() -> void:
	character.set_current_target(null)
	_retarget_timer = 0.0
