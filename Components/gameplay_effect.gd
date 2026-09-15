## Data-only description of one temporary or permanent stat modification (the
## project's GameplayEffect foundation). Effects never execute themselves;
## AttributeComponent.apply_effect() translates them into modifier entries and
## remove_effect() (or expiry) takes them back out.
## Effects target stats (max_health, attack, speed, ...), never pools: buff
## max_health rather than health so expiry re-clamps instead of deleting earned
## health. Instant pool deltas (damage, heal, mana spend) stay direct
## damage_pool()/restore_pool() calls, not effects.
class_name GameplayEffect
extends Resource

## Human-readable effect name, used as the modifier instance id prefix.
@export var effect_name: String = ""
## Stat on AttributeComponent receiving the modifier (e.g. &"attack").
@export var target_attribute: StringName = &"attack"
## Stacking operation as an Attribute.Op index (0 = ADD, 1 = MULT_ADD, 2 = MULT_COMP).
@export_enum("ADD", "MULT_ADD", "MULT_COMP") var operation: int = 1
## Modifier magnitude: flat amount for ADD, fraction for percentages (0.5 = +50%).
@export var magnitude: float = 0.0
## Lifetime in seconds. Values <= 0.0 mean permanent until explicitly removed.
@export var duration: float = 0.0
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
