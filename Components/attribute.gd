## Single tunable stat (max_health, attack, speed, ...) with a base value and a
## stack of active modifiers. The current value recomputes deterministically as:
## (base + sum(ADD)) * (1 + sum(MULT_ADD)) * product(1 + MULT_COMP),
## clamped to [min_value, max_value].
## Resource pools (health, mana) are NOT Attributes; they live on
## AttributeComponent as current values clamped to their linked max stat and
## move only through instant deltas (damage, heal, spend).
class_name Attribute
extends RefCounted

## Modifier stacking operations. Normal buffs and debuffs use MULT_ADD so they
## stack additively (two +50% buffs equal +100%, not +125%). MULT_COMP is
## reserved for rare compounding effects (difficulty auras) that multiply
## against everything else.
enum Op {
	ADD, ## Flat addition to the base value.
	MULT_ADD, ## Percentage as a fraction (0.5 = +50%), summed with other MULT_ADD entries.
	MULT_COMP, ## Percentage as a fraction, compounding multiplicatively with everything else.
}

## Unmodified base value set by designers or permanent upgrades.
var base_value: float = 0.0
## Last recomputed current value. Updated by every mutation via recalculate().
var current_value: float = 0.0
## Lower clamp bound applied after stacking.
var min_value: float = 0.0
## Upper clamp bound applied after stacking. INF means uncapped.
var max_value: float = INF

## Active modifier entries. Each Dictionary holds id (StringName, unique per
## entry), op (int, Op), magnitude (float), duration (float, <= 0.0 means
## permanent), remaining (float, seconds left for timed entries).
var _modifiers: Array[Dictionary] = []


## Adds a modifier entry, replacing any existing entry with the same id
## (re-applying the same effect refreshes it; distinct ids stack).
## Recalculates and returns the new current value.
func add_modifier(modifier_id: StringName, op: int, magnitude: float, duration: float = 0.0) -> float:
	remove_modifier(modifier_id)
	_modifiers.append({
		"id": modifier_id,
		"op": op,
		"magnitude": magnitude,
		"duration": duration,
		"remaining": duration,
	})
	return recalculate()


## Removes the modifier entry with the given id. Returns true when one existed.
## Recalculates when an entry was removed.
func remove_modifier(modifier_id: StringName) -> bool:
	for i: int in range(_modifiers.size()):
		var entry: Dictionary = _modifiers[i]
		if StringName(entry.get("id", &"")) == modifier_id:
			_modifiers.remove_at(i)
			recalculate()
			return true
	return false


## Returns true when a modifier entry with the given id is active.
func has_modifier(modifier_id: StringName) -> bool:
	for entry: Dictionary in _modifiers:
		if StringName(entry.get("id", &"")) == modifier_id:
			return true
	return false


## Returns true when at least one timed (duration > 0.0) modifier is active.
func has_timed_modifiers() -> bool:
	for entry: Dictionary in _modifiers:
		if float(entry.get("duration", 0.0)) > 0.0:
			return true
	return false


## Returns an array of instance IDs for all active timed (duration > 0.0) modifiers.
func get_timed_modifier_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in _modifiers:
		if float(entry.get("duration", 0.0)) > 0.0:
			ids.append(StringName(entry.get("id", &"")))
	return ids


## Removes all timed modifiers (duration > 0.0). Returns true if any were removed.
func clear_timed_modifiers() -> bool:
	var removed: bool = false
	for i: int in range(_modifiers.size() - 1, -1, -1):
		var entry: Dictionary = _modifiers[i]
		if float(entry.get("duration", 0.0)) > 0.0:
			_modifiers.remove_at(i)
			removed = true
	if removed:
		recalculate()
	return removed



## Advances timed modifiers by delta, dropping expired entries. Returns true
## when at least one entry expired (callers should emit change signals then).
func tick(delta: float) -> bool:
	var expired: bool = false
	for i: int in range(_modifiers.size() - 1, -1, -1):
		var entry: Dictionary = _modifiers[i]
		if float(entry.get("duration", 0.0)) <= 0.0:
			continue
		var remaining: float = float(entry.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			_modifiers.remove_at(i)
			expired = true
		else:
			entry["remaining"] = remaining
			_modifiers[i] = entry
	if expired:
		recalculate()
	return expired


## Recomputes the current value from base plus the modifier stack and returns it.
func recalculate() -> float:
	var add_total: float = 0.0
	var mult_add_total: float = 0.0
	var mult_comp_total: float = 1.0
	for entry: Dictionary in _modifiers:
		var op: int = int(entry.get("op", Op.ADD))
		var magnitude: float = float(entry.get("magnitude", 0.0))
		match op:
			Op.ADD:
				add_total += magnitude
			Op.MULT_ADD:
				mult_add_total += magnitude
			Op.MULT_COMP:
				mult_comp_total *= 1.0 + magnitude
			_:
				push_warning("Attribute: ignoring modifier with unknown op %d." % op)
	current_value = clampf((base_value + add_total) * (1.0 + mult_add_total) * mult_comp_total, min_value, max_value)
	return current_value
