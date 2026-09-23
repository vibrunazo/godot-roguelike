## One broadcast point in an ability's lifecycle ("what happened"), carried with
## enough context for passives to act without knowing the source state.
## Ability states (CharacterState.broadcast_ability_event) mint these and route
## them through Character.broadcast_ability_event to the PassiveAbilityComponent,
## which fans them out to granted PassiveAbility nodes. Tags identify the
## ability (&"ability.dash", &"ability.attack"); Phase narrows the lifecycle
## point; position/direction/data give payloads their spawn context.
class_name AbilityEvent
extends RefCounted

## Lifecycle point of the broadcasting ability.
enum Phase {
	STARTED, ## The ability just began (state enter).
	ACTIVE, ## The ability's meaningful active window opened (e.g. weapon hit window).
	ENDED, ## The ability finished for any reason (state exit, including interruptions).
}

## Ability identity tags of the source (e.g. &"ability.dash", &"ability.attack").
var tags: Array[StringName] = []
## Lifecycle point this event reports (AbilityEvent.Phase index).
var phase: int = Phase.ENDED
## Character that owns the ability; the target of granted passives.
var instigator: Character
## State (or node) that broadcast the event. Escape hatch for advanced passives.
var source: Node
## World position at broadcast time (dash end point, attack origin, ...).
var position: Vector3 = Vector3.ZERO
## Facing/motion direction at broadcast time.
var direction: Vector3 = Vector3.ZERO
## Free-form payload. The standard key is "completed" (bool): states that can be
## interrupted report whether they ran to completion; events without the key
## count as completed (see AbilityLifecyclePassive.require_completion).
var data: Dictionary = {}


## Returns true when this event answers a passive's trigger tag. Matches exactly
## or by hierarchy prefix: trigger &"ability" answers event tags &"ability" and
## &"ability.dash", while trigger &"ability.dash" only answers itself.
func matches_tag(trigger: StringName) -> bool:
	if trigger.is_empty():
		return false
	for tag: StringName in tags:
		if tag == trigger:
			return true
		if String(tag).begins_with(String(trigger) + "."):
			return true
	return false