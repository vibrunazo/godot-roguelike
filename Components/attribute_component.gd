## Central stat store for one character (the project's GAS AttributeSet equivalent).
## Owns two kinds of data:
## - Resource pools (health, mana): current values clamped to 0..max-stat that
##   move only through instant deltas (damage_pool, restore_pool,
##   set_pool_current). Pools carry no modifier stack, so expiring a max-stat
##   buff re-clamps but never phantom-deletes earned pool value.
## - Stat attributes (max_health, max_mana, attack, defense, speed,
##   attack_speed): base value plus a stack of active modifiers, recomputed as
##   (base + sum(ADD)) * (1 + sum(MULT_ADD)) * product(1 + MULT_COMP).
## The base_* exports seed each stat once when entering the tree (init-only);
## all runtime reads and writes go through the typed API below, which is the
## single source of truth. Processing stays disabled unless a timed modifier
## is active, so buffless characters cost nothing per tick.
class_name AttributeComponent
extends Node

## Emitted whenever a pool or stat current value changes.
signal attribute_changed(attribute_name: StringName, current_value: float)
## Emitted exactly when the health pool transitions to zero via damage_pool().
## Max-stat edits that clamp the pool never emit this (only damage kills).
signal defeat()

## Pool names (read via get_current, written via damage/restore/set_pool_current).
const POOL_HEALTH: StringName = &"health"
const POOL_MANA: StringName = &"mana"
## Stat names (read via get_current/get_base, written via set_base/apply_modifier).
const STAT_MAX_HEALTH: StringName = &"max_health"
const STAT_MAX_MANA: StringName = &"max_mana"
const STAT_ATTACK: StringName = &"attack"
const STAT_DEFENSE: StringName = &"defense"
const STAT_SPEED: StringName = &"speed"
const STAT_ATTACK_SPEED: StringName = &"attack_speed"

const STAT_NAMES: Array[StringName] = [STAT_MAX_HEALTH, STAT_MAX_MANA, STAT_ATTACK, STAT_DEFENSE, STAT_SPEED, STAT_ATTACK_SPEED]
const POOL_NAMES: Array[StringName] = [POOL_HEALTH, POOL_MANA]
## Maps each pool to the stat that caps it.
const POOL_MAX_LINK: Dictionary = {POOL_HEALTH: STAT_MAX_HEALTH, POOL_MANA: STAT_MAX_MANA}

## Base maximum health. Seeds the max_health stat once on tree entry.
@export var base_max_health: float = 100.0
## Base maximum mana. Seeds the max_mana stat once on tree entry.
@export var base_max_mana: float = 0.0
## Base attack in percent (100.0 = 100%, read via Character.get_damage_modifier()).
@export var base_attack: float = 100.0
## Base defense (flat data for now; no damage formula reads it yet).
@export var base_defense: float = 0.0
## Base movement speed in meters per second, read by movement states.
@export var base_speed: float = 8.0
## Base attack speed multiplier (1.0 = normal; no cooldown scaler reads it yet).
@export var base_attack_speed: float = 1.0

## Stat name -> Attribute. Built in _init so the API is safe before tree entry.
var _stats: Dictionary = {}
## Pool name -> current float value.
var _pools: Dictionary = {POOL_HEALTH: 0.0, POOL_MANA: 0.0}
## Stat names whose base was written programmatically before tree entry.
## Export seeding skips these so explicit setup is never overwritten.
var _base_overrides: Dictionary = {}
var _effect_counter: int = 0
var _seeded_from_exports: bool = false


func _init() -> void:
	for stat_name: StringName in STAT_NAMES:
		_stats[stat_name] = Attribute.new()
	set_process(false)


func _enter_tree() -> void:
	_seed_from_exports()


func _ready() -> void:
	_seed_from_exports()
	_update_processing()


## Returns true for the six buffable stat names.
func is_stat(attribute_name: StringName) -> bool:
	return _stats.has(attribute_name)


## Returns true for the two pool names (health, mana).
func is_pool(attribute_name: StringName) -> bool:
	return _pools.has(attribute_name)


## Returns true for any known pool or stat name.
func has_attribute(attribute_name: StringName) -> bool:
	return _stats.has(attribute_name) or _pools.has(attribute_name)


## Returns the unmodified base of a stat. Pools have no base; querying one is
## a programming error and returns 0.0 (query the linked max stat instead).
func get_base(stat_name: StringName) -> float:
	var attr: Attribute = _stats.get(stat_name) as Attribute
	if attr == null:
		push_error("AttributeComponent: unknown stat '%s'." % stat_name)
		return 0.0
	return attr.base_value


## Writes a stat base (permanent change, e.g. shop upgrades). Emits
## attribute_changed when the current value moves and re-clamps the linked
## pool, which emits its own change when clamped. Never emits defeat.
func set_base(stat_name: StringName, value: float) -> void:
	var attr: Attribute = _stats.get(stat_name) as Attribute
	if attr == null:
		push_error("AttributeComponent: unknown stat '%s'." % stat_name)
		return
	_base_overrides[stat_name] = value
	var before: float = attr.current_value
	attr.base_value = value
	var after: float = attr.recalculate()
	if not is_equal_approx(before, after):
		attribute_changed.emit(stat_name, after)
	_clamp_pool_to_max(stat_name)


## Returns the current value of a pool or stat (post-modifier for stats).
func get_current(attribute_name: StringName) -> float:
	if _pools.has(attribute_name):
		return float(_pools[attribute_name])
	var attr: Attribute = _stats.get(attribute_name) as Attribute
	if attr == null:
		push_error("AttributeComponent: unknown attribute '%s'." % attribute_name)
		return 0.0
	return attr.current_value


## Adds a modifier entry to a stat. Re-applying the same id refreshes that
## entry; distinct ids stack. Duration <= 0.0 means permanent until removed.
## Returns false for unknown stats or pools (pools take no modifiers).
func apply_modifier(target_stat: StringName, modifier_id: StringName, op: int, magnitude: float, duration: float = 0.0) -> bool:
	var attr: Attribute = _stats.get(target_stat) as Attribute
	if attr == null:
		push_error("AttributeComponent: cannot modify '%s' (unknown stat or pool)." % target_stat)
		return false
	var before: float = attr.current_value
	attr.add_modifier(modifier_id, op, magnitude, duration)
	_update_processing()
	if not is_equal_approx(before, attr.current_value):
		attribute_changed.emit(target_stat, attr.current_value)
	return true


## Removes one modifier entry from a stat. Returns true when one existed.
func remove_modifier(target_stat: StringName, modifier_id: StringName) -> bool:
	var attr: Attribute = _stats.get(target_stat) as Attribute
	if attr == null:
		push_error("AttributeComponent: unknown stat '%s'." % target_stat)
		return false
	var before: float = attr.current_value
	var removed: bool = attr.remove_modifier(modifier_id)
	_update_processing()
	if removed and not is_equal_approx(before, attr.current_value):
		attribute_changed.emit(target_stat, attr.current_value)
	return removed


## Applies a GameplayEffect resource to its target stat and returns a unique
## instance id for later removal. Returns &"" when the target is invalid.
func apply_effect(effect: GameplayEffect) -> StringName:
	if effect == null or not is_instance_valid(effect):
		push_error("AttributeComponent: cannot apply a null effect.")
		return &""
	_effect_counter += 1
	var fallback_name: String = "effect" if effect.effect_name.is_empty() else effect.effect_name
	var instance_id: StringName = StringName("%s_%d" % [fallback_name, _effect_counter])
	if not apply_modifier(effect.target_attribute, instance_id, effect.operation, effect.magnitude, effect.duration):
		return &""
	return instance_id


## Removes a previously applied effect instance by id. Returns true when found.
func remove_effect(instance_id: StringName) -> bool:
	for stat_name: StringName in STAT_NAMES:
		var attr: Attribute = _stats[stat_name] as Attribute
		if attr != null and attr.has_modifier(instance_id):
			return remove_modifier(stat_name, instance_id)
	return false


## Subtracts an instant delta from a pool (damage, mana spend) with exact
## arithmetic: overkill may drive the pool negative, and callers observe the
## precise remainder. Always emits attribute_changed, even for zero deltas.
## Emits defeat exactly when health transitions to zero or below from above.
func damage_pool(pool_name: StringName, amount: float) -> void:
	if not _pools.has(pool_name):
		push_error("AttributeComponent: unknown pool '%s'." % pool_name)
		return
	var before: float = float(_pools[pool_name])
	_pools[pool_name] = before - amount
	attribute_changed.emit(pool_name, float(_pools[pool_name]))
	if amount > 0.0 and before > 0.0 and float(_pools[pool_name]) <= 0.0 and pool_name == POOL_HEALTH:
		defeat.emit()


## Adds an instant delta to a pool (heal, mana restore), clamped to the linked
## max stat. Emits attribute_changed.
func restore_pool(pool_name: StringName, amount: float) -> void:
	if not _pools.has(pool_name):
		push_error("AttributeComponent: unknown pool '%s'." % pool_name)
		return
	var max_stat: StringName = POOL_MAX_LINK[pool_name] as StringName
	var cap: float = get_current(max_stat)
	_pools[pool_name] = clampf(float(_pools[pool_name]) + amount, 0.0, cap)
	attribute_changed.emit(pool_name, float(_pools[pool_name]))


## Writes a pool current value directly (clamped to 0..max). Emits
## attribute_changed but never defeat (only damage_pool damage can defeat).
func set_pool_current(pool_name: StringName, value: float) -> void:
	if not _pools.has(pool_name):
		push_error("AttributeComponent: unknown pool '%s'." % pool_name)
		return
	var max_stat: StringName = POOL_MAX_LINK[pool_name] as StringName
	_pools[pool_name] = clampf(value, 0.0, get_current(max_stat))
	attribute_changed.emit(pool_name, float(_pools[pool_name]))


## Returns true while the health pool is above zero.
func is_alive() -> bool:
	return float(_pools[POOL_HEALTH]) > 0.0


func _process(delta: float) -> void:
	var changed_stats: Array[StringName] = []
	for stat_name: StringName in STAT_NAMES:
		var attr: Attribute = _stats[stat_name] as Attribute
		if attr != null and attr.tick(delta):
			changed_stats.append(stat_name)
	for stat_name: StringName in changed_stats:
		attribute_changed.emit(stat_name, get_current(stat_name))
		_clamp_pool_to_max(stat_name)
	_update_processing()


## Seeds stat bases from the base_* exports on first tree entry and fills
## pools to full. Stats written programmatically before entry win over exports.
func _seed_from_exports() -> void:
	if _seeded_from_exports:
		return
	_seeded_from_exports = true
	_apply_export_base(STAT_MAX_HEALTH, base_max_health)
	_apply_export_base(STAT_MAX_MANA, base_max_mana)
	_apply_export_base(STAT_ATTACK, base_attack)
	_apply_export_base(STAT_DEFENSE, base_defense)
	_apply_export_base(STAT_SPEED, base_speed)
	_apply_export_base(STAT_ATTACK_SPEED, base_attack_speed)
	for pool_name: StringName in POOL_NAMES:
		var max_stat: StringName = POOL_MAX_LINK[pool_name] as StringName
		_pools[pool_name] = get_current(max_stat)


## Enables ticking only while a timed modifier exists anywhere.
func _update_processing() -> void:
	for stat_name: StringName in STAT_NAMES:
		var attr: Attribute = _stats[stat_name] as Attribute
		if attr != null and attr.has_timed_modifiers():
			set_process(true)
			return
	set_process(false)


func _apply_export_base(stat_name: StringName, exported_value: float) -> void:
	if _base_overrides.has(stat_name):
		return
	var attr: Attribute = _stats[stat_name] as Attribute
	if attr != null:
		attr.base_value = exported_value
		attr.recalculate()


## Re-clamps the pool linked to a max stat after that stat changed. Emits the
## pool change when clamping moved it. Never emits defeat.
func _clamp_pool_to_max(max_stat_name: StringName) -> void:
	for pool_name: StringName in POOL_NAMES:
		if (POOL_MAX_LINK[pool_name] as StringName) != max_stat_name:
			continue
		var cap: float = get_current(max_stat_name)
		var before: float = float(_pools[pool_name])
		var after: float = minf(before, cap)
		if not is_equal_approx(before, after):
			_pools[pool_name] = after
			attribute_changed.emit(pool_name, after)
