## Data-only description of one stat modification or pool effect (the project's
## GameplayEffect foundation). Effects never execute themselves;
## AttributeComponent.apply_effect() translates them and remove_effect() (or
## expiry) takes them back out.
## Effects targeting stats (max_health, attack, speed, ...) become modifier
## entries: buff max_health rather than health so expiry re-clamps instead of
## deleting earned health. Effects targeting pools (health, mana) deal their
## total_damage instead: spread over time while duration > 0.0 (damage over
## time, heal over time for negative totals) or all at once when instant.
class_name GameplayEffect
extends Resource

## Re-application policies for GameplayEffect.stacking (stored as int).
enum Stacking {
	REFRESH, ## Restart the duration on the single entry (slows, stuns).
	STACK, ## Add an independent entry per application (poison, burn).
}

## Unique effect identity. Doubles as the modifier instance id, so re-applying
## an effect refreshes its duration instead of stacking a second copy.
@export var effect_name: String = ""
## What happens when the same effect is applied while already active.
## REFRESH restarts the duration on the single entry; STACK adds an
## independent entry per application (returned ids remove one stack each).
@export_enum("REFRESH", "STACK") var stacking: int = 0
## Stat on AttributeComponent receiving the modifier (e.g. &"attack").
@export var target_attribute: StringName = &"attack"
## Stacking operation as an Attribute.Op index (0 = ADD, 1 = MULT_ADD, 2 = MULT_COMP).
@export_enum("ADD", "MULT_ADD", "MULT_COMP") var operation: int = 1
## Modifier magnitude: flat amount for ADD, fraction for percentages (0.5 = +50%).
## Only meaningful for stat targets; ignored (with a warning) on pool targets.
@export var magnitude: float = 0.0
## Total pool damage dealt when targeting a pool (positive harms, negative
## heals over time). Spread evenly across duration; all at once when instant.
## Only meaningful for pool targets; ignored (with a warning) on stat targets.
@export var total_damage: float = 0.0
## Damage type tag for pool damage (e.g. &"physical", &"fire"). Resistance
## stats scale typed damage; fully-resisted targets ignore the effect.
@export var damage_type: StringName = &"physical"
## Lifetime in seconds. On stats, values <= 0.0 mean permanent until removed.
## On pools, values > 0.0 spread total_damage over time, values <= 0.0 apply
## it instantly.
@export var duration: float = 0.0
## Optional status visual: a scene instanced on the target while a timed
## instance of this effect is active (burning flames, frost mist, a shield
## bubble) and freed automatically on expiry or removal. Instant pool effects
## never show it since they have no duration. Null means no visual.
@export var vfx_scene: PackedScene
## Local offset applied to the instanced visual, relative to the target's
## body origin (the feet). E.g. raise flames toward the torso with
## Vector3(0, 0.6, 0).
@export var vfx_offset: Vector3 = Vector3.ZERO
## Optional designer note describing the effect's intent.
@export var description: String = ""


## Applies this effect to the target component. Returns the unique instance id
## for later removal, or &"" when the target attribute is invalid.
func apply_to(target: AttributeComponent) -> StringName:
	if target == null or not is_instance_valid(target):
		push_error("GameplayEffect: cannot apply '%s' to a null target." % effect_name)
		return &""
	return target.apply_effect(self)


## Removes a previously applied instance from the target. Returns true when found.
func remove_from(target: AttributeComponent, instance_id: StringName) -> bool:
	if target == null or not is_instance_valid(target):
		push_error("GameplayEffect: cannot remove '%s' from a null target." % effect_name)
		return false
	return target.remove_effect(instance_id)
