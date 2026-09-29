## Damage type identifiers. Every damage source tags its damage with one
## (AttackComponent, DamageArea, GameplayEffect), and
## AttributeComponent.RESISTANCE_STATS maps each resisted type to the stat that
## scales it. A new element needs a constant here and, when resistible, one
## entry in that table.
class_name DamageType
extends RefCounted

## Plain hits: weapons, punches, spikes. Unresisted.
const PHYSICAL: StringName = &"physical"
## Fire: fireballs, firebombs, fire traps, burns. Scaled by fire_resistance.
const FIRE: StringName = &"fire"
