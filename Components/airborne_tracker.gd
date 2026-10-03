## Tracks a character's grounded <-> airborne edge and broadcasts it as
## movement lifecycle events through the character's passive bus, whichever
## body state is active when the edge happens (jump, jump kick, knockback
## launch). Leaving the floor adds TAG_AIRBORNE and emits (TAG_AIRBORNE) /
## STARTED; touching down removes it and emits (TAG_AIRBORNE + TAG_LANDED) /
## ENDED with {"airborne_time": seconds, "fall_height": meters}, where
## fall_height is how far the character dropped from the episode's highest
## point to where it landed (a 1 cm bump reports about 0.01). A landing blast
## passive therefore fires exactly once per airborne episode, even when a jump
## turns into a jump kick mid-flight, and can ignore tiny drops by gating on
## fall_height. Defeated characters stay silent (no corpse detonations).
class_name AirborneTracker
extends Node

## Gameplay tag carried while the character is airborne (left the floor and
## not grounded again). Passive required/blocked gates can use it ("only while
## airborne").
const TAG_AIRBORNE: StringName = &"movement.airborne"
## Extra tag on an airborne episode's ENDED event: the character just landed.
const TAG_LANDED: StringName = &"movement.landed"

## The character whose floor contact is tracked.
@export var character: Character

## True while an airborne episode is in progress.
var _airborne: bool = false
## Elapsed seconds of the current/last airborne episode.
var _airborne_time: float = 0.0
## Highest global Y the character reached during the current episode.
var _apex_y: float = 0.0


func _ready() -> void:
	# Read the floor state before this frame's body state moves the character,
	# like the controllers do.
	process_physics_priority = -1
	if character == null:
		push_error("%s: character is not set." % name)
		return
	character.defeat.connect(_clear)


func _physics_process(delta: float) -> void:
	if character == null or not character.is_alive():
		_clear()
		return
	# is_on_floor() is false before the first move_and_slide and would fake an
	# airborne episode (and a landing) at spawn.
	if not character.has_moved():
		return
	var y: float = character.global_position.y
	if not character.is_on_floor():
		if not _airborne:
			_airborne = true
			_airborne_time = 0.0
			_apex_y = y
			character.add_tag(TAG_AIRBORNE)
			var started_tags: Array[StringName] = [TAG_AIRBORNE]
			_broadcast(AbilityEvent.Phase.STARTED, started_tags)
		_airborne_time += delta
		_apex_y = maxf(_apex_y, y)
	elif _airborne:
		_airborne = false
		character.remove_tag(TAG_AIRBORNE)
		var landed_tags: Array[StringName] = [TAG_AIRBORNE, TAG_LANDED]
		var fall_height: float = maxf(0.0, _apex_y - y)
		_broadcast(AbilityEvent.Phase.ENDED, landed_tags, {"airborne_time": _airborne_time, "fall_height": fall_height})


## Ends the episode silently (defeat), dropping TAG_AIRBORNE without
## broadcasting a landing.
func _clear() -> void:
	if _airborne:
		_airborne = false
		character.remove_tag(TAG_AIRBORNE)


## Broadcasts one movement lifecycle event (source is the character; direction
## is its horizontal velocity, else its facing).
func _broadcast(phase: int, tags: Array[StringName], extra_data: Dictionary = {}) -> void:
	var event: AbilityEvent = AbilityEvent.new()
	event.tags = tags
	event.phase = phase
	event.instigator = character
	event.source = character
	event.position = character.global_position
	event.direction = Vector3(character.velocity.x, 0.0, character.velocity.z)
	if event.direction.is_zero_approx() and character.mesh_mount != null:
		event.direction = character.mesh_mount.global_basis.z.normalized()
	event.data = extra_data
	character.broadcast_ability_event(event)
