## Base node for passive abilities: behavior add-ons granted by items that react
## automatically to gameplay (a detonation at the end of every dash, a nova on
## hit, a ticking thorns aura). This base owns identity and grant lifecycle only;
## ability-event trigger matching lives on AbilityLifecyclePassive and payload
## spawning on PayloadPassiveAbility. Passive scenes root at one of these
## subclasses and are instanced as children of PassiveAbilityComponent.
class_name PassiveAbility
extends Node

## Unique identity used for grant tracking and removal (e.g. &"dash_explosion").
@export var id: StringName = &""
## Short UI label shown on item cards ("Grants: ...").
@export var display_name: String = ""
## Master switch. Disabled passives never react until re-enabled.
@export var enabled: bool = true

## Character this passive is granted to. Set by PassiveAbilityComponent.setup().
var character: Character = null


## Arms this passive on grant. Subclasses override _on_setup instead of this.
func setup(p_character: Character) -> void:
	character = p_character
	_on_setup()


## Disarms this passive on removal. Subclasses override _on_teardown instead.
func teardown() -> void:
	_on_teardown()
	character = null


## Event entry point called by PassiveAbilityComponent for every ability
## lifecycle event. Base passives ignore events; event-driven subclasses
## (AbilityLifecyclePassive) override this with trigger matching.
func handle_ability_event(_event: AbilityEvent) -> void:
	pass


## Virtual hook called once when granted to a character.
func _on_setup() -> void:
	pass


## Virtual hook called once when removed from a character.
func _on_teardown() -> void:
	pass