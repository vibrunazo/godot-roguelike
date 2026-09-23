## Passive triggered by ability lifecycle events. Matching is a sequence of
## cheap gates: trigger tags on the event (exact or hierarchy prefix), trigger
## phase, the optional completion filter, optional character tag gates, and a
## cooldown. Matched events call _activate(event), which subclasses override with
## the actual behavior (see PayloadPassiveAbility for the data-driven one).
class_name AbilityLifecyclePassive
extends PassiveAbility

## Ability event tags this passive answers (e.g. &"ability.dash"). Matches
## exactly or by hierarchy prefix: trigger &"ability" answers every ability.
@export var trigger_tags: Array[StringName] = []
## Ability lifecycle point this passive fires on (AbilityEvent.Phase index).
@export_enum("STARTED", "ACTIVE", "ENDED") var trigger_phase: int = AbilityEvent.Phase.ENDED
## When true, only events reporting data {"completed": true} trigger this
## passive, so interrupted abilities (a stun-cancelled dash) stay silent. Events
## that do not report completion at all count as completed, so only states that
## explicitly flag interruptions can suppress the trigger.
@export var require_completion: bool = false
## Character tags required on the owner for triggering (e.g. only while airborne).
@export var required_tags: Array[StringName] = []
## Character tags that suppress triggering while present on the owner.
@export var blocked_tags: Array[StringName] = []
## Minimum seconds between activations (<= 0.0 = every matching event).
@export var cooldown: float = 0.0

## Seconds left before the next activation is allowed.
var _cooldown_remaining: float = 0.0


func _physics_process(delta: float) -> void:
	tick_cooldown(delta)


## Progresses cooldown decay by delta. Public so tests can simulate elapsed time
## deterministically (e.g. tick_cooldown(passive.cooldown)) without waiting.
func tick_cooldown(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)


## Returns true while activations are suppressed by the cooldown gate.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0


func handle_ability_event(event: AbilityEvent) -> void:
	if not enabled or event == null:
		return
	if event.phase != trigger_phase:
		return
	if not _matches_any_trigger_tag(event):
		return
	if require_completion and not bool(event.data.get("completed", true)):
		return
	if character != null and is_instance_valid(character):
		if not required_tags.is_empty() and not character.has_all_tags(required_tags):
			return
		if not blocked_tags.is_empty() and character.has_any_tag(blocked_tags):
			return
	if is_on_cooldown():
		return
	if cooldown > 0.0:
		_cooldown_remaining = cooldown
	_activate(event)


## True when the event answers one of this passive's trigger tags.
func _matches_any_trigger_tag(event: AbilityEvent) -> bool:
	for trigger: StringName in trigger_tags:
		if event.matches_tag(trigger):
			return true
	return false


## Virtual: the behavior executed once matching and cooldown gates passed.
func _activate(_event: AbilityEvent) -> void:
	pass