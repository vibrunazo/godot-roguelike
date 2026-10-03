## Passive applying GameplayEffects to whatever its owner's matching abilities
## hit: the HIT lifecycle point carries the struck Hurtbox, and each effect
## goes to its AttributeComponent (a slow on melee hits, a burn on spell hits,
## ...). Trigger tags pick which abilities count (&"ability.attack" for melee
## attacks). Dead targets are ignored, so corpses never show status visuals.
class_name HitEffectPassive
extends AbilityLifecyclePassive

## Effects applied to each live target a matching hit struck.
@export var effects_to_apply: Array[GameplayEffect] = []


func _init() -> void:
	trigger_phase = AbilityEvent.Phase.HIT


func _activate(event: AbilityEvent) -> void:
	var hurtbox: Hurtbox = event.data.get("target") as Hurtbox
	if hurtbox == null or not is_instance_valid(hurtbox) or not hurtbox.is_alive():
		return
	var attributes: AttributeComponent = hurtbox.attribute_component
	if attributes == null:
		return
	for effect: GameplayEffect in effects_to_apply:
		if effect != null:
			attributes.apply_effect(effect)
