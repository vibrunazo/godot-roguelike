## Central stat store for one character (the project's GAS AttributeSet equivalent).
## Owns two kinds of data:
## - Resource pools (health, mana): current values clamped to 0..max-stat that
##   move only through instant deltas (damage_pool, restore_pool,
##   set_pool_current). Pools carry no modifier stack, so expiring a max-stat
##   buff re-clamps but never phantom-deletes earned pool value.
## - Stat attributes (max_health, max_mana, attack, defense, speed,
##   attack_speed, fire_resistance, rotation_speed): base value plus a stack of active
##   modifiers, recomputed as
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
## Emitted when a gameplay tag is added to this component.
signal tag_added(tag: StringName)
## Emitted when a gameplay tag is removed from this component.
signal tag_removed(tag: StringName)

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
## Fire resistance as a fraction (0.0 = none, 1.0 = immune). Scales all
## fire-typed damage; read via get_damage_multiplier, never directly.
const STAT_FIRE_RESISTANCE: StringName = &"fire_resistance"
## Rotation speed limit in degrees per second (360.0 = one full turn per
## second). Caps how fast Character.look_* rotate the mesh_mount; read via
## Character.get_rotation_speed(), never directly.
const STAT_ROTATION_SPEED: StringName = &"rotation_speed"

const STAT_NAMES: Array[StringName] = [STAT_MAX_HEALTH, STAT_MAX_MANA, STAT_ATTACK, STAT_DEFENSE, STAT_SPEED, STAT_ATTACK_SPEED, STAT_FIRE_RESISTANCE, STAT_ROTATION_SPEED]
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
## Base fire resistance as a fraction (0.0 = none, 1.0 = immune). Scales all
## fire-typed damage through get_damage_multiplier; fully-resisted hits deal
## nothing and trigger no hit reactions.
@export var base_fire_resistance: float = 0.0
## Base rotation speed limit in degrees per second (360.0 = one full turn per
## second). Seeds the rotation_speed stat once on tree entry; 0.0 holds facing.
@export var base_rotation_speed: float = 360.0
## Gameplay tags granted to this component initially on ready.
@export var initial_tags: Array[StringName] = []
## Gameplay effects applied to this component initially on ready.
@export var initial_effects: Array[GameplayEffect] = []

## Stat name -> Attribute. Built in _init so the API is safe before tree entry.
var _stats: Dictionary = {}
## Pool name -> current float value.
var _pools: Dictionary = {POOL_HEALTH: 0.0, POOL_MANA: 0.0}
## Active damage-over-time entries. Each Dictionary holds id (StringName),
## pool (StringName), rate (float, pool units per second, negative heals), and
## remaining (float, seconds left).
var _dots: Array[Dictionary] = []
## Stat names whose base was written programmatically before tree entry.
## Export seeding skips these so explicit setup is never overwritten.
var _base_overrides: Dictionary = {}
## Live status visuals: effect instance id (StringName) -> instanced
## GameplayEffect.vfx_scene node, parented to the nearest Node3D ancestor
## (the character body) at the effect's vfx_offset. One entry per timed
## effect instance, so stacked effects show one visual each and refreshes
## reuse theirs. Freed when the instance expires or is removed.
var _effect_vfx: Dictionary = {}
var _stack_counter: int = 0
var _seeded_from_exports: bool = false
## Tag name -> int count of active sources granting the tag.
var _tags: Dictionary = {}
## Effect instance id -> Array[StringName] of tags granted by that effect.
var _effect_tags: Dictionary = {}
## Timed tag-only effect entries: Dictionary with id (StringName), remaining (float).
var _timed_tag_effects: Array[Dictionary] = []
## Permanent tag-only effect entries: Array of instance_id (StringName).
var _permanent_tag_effects: Array[StringName] = []


func _init() -> void:
	for stat_name: StringName in STAT_NAMES:
		_stats[stat_name] = Attribute.new()
	set_process(false)


func _enter_tree() -> void:
	_seed_from_exports()


func _ready() -> void:
	_seed_from_exports()
	_update_processing()
	for tag: StringName in initial_tags:
		add_tag(tag)
	for effect: GameplayEffect in initial_effects:
		if effect != null:
			apply_effect(effect)


## Returns true if this component currently has the specified gameplay tag.
func has_tag(tag: StringName) -> bool:
	return _tags.get(tag, 0) > 0


## Returns true if this component has all tags in the given array.
func has_all_tags(tags: Array[StringName]) -> bool:
	for tag: StringName in tags:
		if not has_tag(tag):
			return false
	return true


## Returns true if this component has at least one of the tags in the given array.
func has_any_tag(tags: Array[StringName]) -> bool:
	if tags.is_empty():
		return false
	for tag: StringName in tags:
		if has_tag(tag):
			return true
	return false


## Adds one count of the specified gameplay tag. Emits tag_added if newly gained.
func add_tag(tag: StringName) -> void:
	if tag.is_empty():
		return
	var current: int = _tags.get(tag, 0)
	_tags[tag] = current + 1
	if current == 0:
		tag_added.emit(tag)


## Removes one count of the specified gameplay tag. Emits tag_removed if fully lost.
func remove_tag(tag: StringName) -> void:
	if not _tags.has(tag):
		return
	var current: int = _tags[tag]
	if current <= 1:
		_tags.erase(tag)
		tag_removed.emit(tag)
	else:
		_tags[tag] = current - 1


## Returns all currently active gameplay tags.
func get_tags() -> Array[StringName]:
	var active_tags: Array[StringName] = []
	for tag: StringName in _tags.keys():
		if _tags[tag] > 0:
			active_tags.append(tag)
	return active_tags


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
	_reap_effect_vfx()
	if removed and not is_equal_approx(before, attr.current_value):
		attribute_changed.emit(target_stat, attr.current_value)
	return removed


## Applies a GameplayEffect resource and returns an instance id for later
## removal. Stat targets become modifier entries; pool targets become damage
## over time (duration > 0.0) or an instant delta. REFRESH effects reuse the
## effect name as their id, so re-applying restarts the duration; STACK
## effects mint a unique id per application, each removable independently.
## Returns &"" when the effect or its target is invalid.
func apply_effect(effect: GameplayEffect) -> StringName:
	if effect == null or not is_instance_valid(effect):
		push_error("AttributeComponent: cannot apply a null effect.")
		return &""
	if effect.effect_name.is_empty():
		push_error("AttributeComponent: effects need an effect_name identity.")
		return &""
	if _pools.has(effect.target_attribute):
		var pool_id: StringName = _apply_pool_effect(effect)
		if pool_id != &"":
			_register_granted_tags(pool_id, effect.granted_tags)
		return pool_id
	var instance_id: StringName = StringName(effect.effect_name)
	if effect.stacking == GameplayEffect.Stacking.STACK:
		_stack_counter += 1
		instance_id = StringName("%s_%d" % [effect.effect_name, _stack_counter])
	var is_tag_only: bool = not _stats.has(effect.target_attribute)
	if is_tag_only:
		if effect.duration > 0.0:
			_remove_timed_tag_effect(instance_id, true)
			_timed_tag_effects.append({
				"id": instance_id,
				"remaining": effect.duration
			})
			_update_processing()
		else:
			if not _permanent_tag_effects.has(instance_id):
				_permanent_tag_effects.append(instance_id)
		_register_granted_tags(instance_id, effect.granted_tags)
		_show_effect_vfx(instance_id, effect)
		return instance_id
	if effect.total_damage != 0.0:
		push_warning("AttributeComponent: total_damage only applies to pool targets; ignored on '%s'." % effect.target_attribute)
	if not apply_modifier(effect.target_attribute, instance_id, effect.operation, effect.magnitude, effect.duration):
		return &""
	_register_granted_tags(instance_id, effect.granted_tags)
	_show_effect_vfx(instance_id, effect)
	return instance_id


## Applies a pool-targeted effect: damage (or heal, for negative totals) over
## time while duration > 0.0, otherwise a single instant delta. Respects the
## effect stacking policy like stat entries do.
func _apply_pool_effect(effect: GameplayEffect) -> StringName:
	var instance_id: StringName = StringName(effect.effect_name)
	if effect.stacking == GameplayEffect.Stacking.STACK:
		_stack_counter += 1
		instance_id = StringName("%s_%d" % [effect.effect_name, _stack_counter])
	# Fully-resisted damage never starts: no entry, no tick, no status visual.
	if effect.total_damage > 0.0 and get_damage_multiplier(effect.damage_type) <= 0.0:
		return &""
	if effect.magnitude != 0.0:
		push_warning("AttributeComponent: magnitude only applies to stat targets; ignored on '%s'." % effect.target_attribute)
	if effect.duration > 0.0:
		_remove_dot(instance_id, true)
		_dots.append({
			"id": instance_id,
			"pool": effect.target_attribute,
			"rate": effect.total_damage / effect.duration,
			"remaining": effect.duration,
			"dtype": effect.damage_type,
		})
		_update_processing()
		_show_effect_vfx(instance_id, effect)
	else:
		if effect.total_damage >= 0.0:
			damage_pool(effect.target_attribute, effect.total_damage)
		else:
			restore_pool(effect.target_attribute, -effect.total_damage)
	return instance_id


## Removes a previously applied effect instance by id, from stat entries and
## damage-over-time entries alike. Returns true when found.
func remove_effect(instance_id: StringName) -> bool:
	var found: bool = false
	for stat_name: StringName in STAT_NAMES:
		var attr: Attribute = _stats[stat_name] as Attribute
		if attr != null and attr.has_modifier(instance_id):
			if remove_modifier(stat_name, instance_id):
				found = true
	if _remove_dot(instance_id):
		found = true
	if _remove_timed_tag_effect(instance_id):
		found = true
	if _permanent_tag_effects.has(instance_id):
		_permanent_tag_effects.erase(instance_id)
		found = true
	if _unregister_granted_tags(instance_id):
		found = true
	_reap_effect_vfx()
	return found


## Drops one damage-over-time entry by id. Returns true when one existed.
## Refresh re-application passes keep_visual to reuse the live status visual.
func _remove_dot(instance_id: StringName, keep_visual: bool = false) -> bool:
	for i: int in range(_dots.size()):
		var entry: Dictionary = _dots[i]
		if StringName(entry.get("id", &"")) == instance_id:
			_dots.remove_at(i)
			_update_processing()
			if not keep_visual:
				_reap_effect_vfx()
			return true
	return false


func _register_granted_tags(instance_id: StringName, tags: Array[StringName]) -> void:
	if tags.is_empty():
		return
	if _effect_tags.has(instance_id):
		_unregister_granted_tags(instance_id)
	var registered: Array[StringName] = []
	for tag: StringName in tags:
		if not tag.is_empty():
			add_tag(tag)
			registered.append(tag)
	if not registered.is_empty():
		_effect_tags[instance_id] = registered


func _unregister_granted_tags(instance_id: StringName) -> bool:
	if not _effect_tags.has(instance_id):
		return false
	var tags: Array[StringName] = _effect_tags[instance_id] as Array[StringName]
	_effect_tags.erase(instance_id)
	for tag: StringName in tags:
		remove_tag(tag)
	return true


func _remove_timed_tag_effect(instance_id: StringName, keep_visual: bool = false) -> bool:
	for i: int in range(_timed_tag_effects.size()):
		var entry: Dictionary = _timed_tag_effects[i]
		if StringName(entry.get("id", &"")) == instance_id:
			_timed_tag_effects.remove_at(i)
			_update_processing()
			if not keep_visual:
				_reap_effect_vfx()
			return true
	return false


## Instances the effect's vfx_scene on this component while the timed instance
## lives. Refreshes reuse the existing node (same instance id); stacked
## instances each get their own. No scene (or an instant pool effect, which
## never reaches here) means no visual.
func _show_effect_vfx(instance_id: StringName, effect: GameplayEffect) -> void:
	if effect.vfx_scene == null or _effect_vfx.has(instance_id):
		return
	var fx: Node = effect.vfx_scene.instantiate()
	_effect_vfx_parent().add_child(fx)
	if fx is Node3D:
		(fx as Node3D).position = effect.vfx_offset
	_effect_vfx[instance_id] = fx


## Status visuals must live under a Node3D to inherit the target's transform:
## a Node3D parented to this plain-Node component would sit at its local
## position in world space instead of on the character. Falls back to this
## component when no Node3D ancestor exists (bare test setups).
func _effect_vfx_parent() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node is Node3D:
			return node
		node = node.get_parent()
	return self


## Returns true while the instance id still owns a stat modifier or a
## damage-over-time entry.
func _has_effect_instance(instance_id: StringName) -> bool:
	for i: int in range(_dots.size()):
		if StringName((_dots[i] as Dictionary).get("id", &"")) == instance_id:
			return true
	for stat_name: StringName in STAT_NAMES:
		var attr: Attribute = _stats[stat_name] as Attribute
		if attr != null and attr.has_modifier(instance_id):
			return true
	for i: int in range(_timed_tag_effects.size()):
		if StringName((_timed_tag_effects[i] as Dictionary).get("id", &"")) == instance_id:
			return true
	if _permanent_tag_effects.has(instance_id):
		return true
	return false


## Clears all temporary/timed gameplay effects from this component:
## - All damage-over-time (DoTs) such as fire burn and poison.
## - All timed stat modifiers (e.g. slows, temporary buffs/debuffs).
## - All timed gameplay tag effects and their granted tags.
## - All status visual effects (e.g. burning fire particles/lights).
## Permanent base stats and permanent modifiers remain intact.
func clear_temporary_effects() -> void:
	for dot: Dictionary in _dots:
		var instance_id: StringName = StringName(dot.get("id", &""))
		_unregister_granted_tags(instance_id)
	_dots.clear()

	for timed_tag: Dictionary in _timed_tag_effects:
		var instance_id: StringName = StringName(timed_tag.get("id", &""))
		_unregister_granted_tags(instance_id)
	_timed_tag_effects.clear()

	for stat_name: StringName in STAT_NAMES:
		var attr: Attribute = _stats[stat_name] as Attribute
		if attr != null:
			for mod_id: StringName in attr.get_timed_modifier_ids():
				_unregister_granted_tags(mod_id)
			if attr.clear_timed_modifiers():
				attribute_changed.emit(stat_name, attr.current_value)
				_clamp_pool_to_max(stat_name)

	_reap_effect_tags()
	_reap_effect_vfx()
	_update_processing()


## Frees status visuals whose effect instance expired or was removed.
## Refreshes keep their id alive, so their visual survives untouched.
func _reap_effect_vfx() -> void:
	var dead: Array[StringName] = []
	for instance_id: StringName in _effect_vfx:
		if not _has_effect_instance(instance_id):
			dead.append(instance_id)
	for instance_id: StringName in dead:
		var fx: Node = _effect_vfx[instance_id] as Node
		_effect_vfx.erase(instance_id)
		if fx != null and is_instance_valid(fx):
			if fx is Node3D:
				(fx as Node3D).visible = false
			elif fx is CanvasItem:
				(fx as CanvasItem).visible = false
			fx.queue_free()



## Subtracts an instant delta from a pool (damage, mana spend), clamped at
## zero: overkill never drives the pool negative. Always emits
## attribute_changed, even for zero deltas. Emits defeat exactly when health
## transitions to zero from a positive value.
func damage_pool(pool_name: StringName, amount: float) -> void:
	if not _pools.has(pool_name):
		push_error("AttributeComponent: unknown pool '%s'." % pool_name)
		return
	var before: float = float(_pools[pool_name])
	_pools[pool_name] = maxf(0.0, before - amount)
	attribute_changed.emit(pool_name, float(_pools[pool_name]))
	if amount > 0.0 and before > 0.0 and float(_pools[pool_name]) <= 0.0 and pool_name == POOL_HEALTH:
		defeat.emit()


## Maps a damage type to the resistance stat that scales it. Empty means the
## type is unresisted. Add new mappings here when damage types grow.
static func resistance_stat_for(damage_type: StringName) -> StringName:
	if damage_type == &"fire":
		return STAT_FIRE_RESISTANCE
	return &""


## Fraction of damage_type damage that lands after resistance (1.0 = full,
## 0.0 = immune). Unknown or unresisted types always land fully.
func get_damage_multiplier(damage_type: StringName) -> float:
	var stat: StringName = resistance_stat_for(damage_type)
	if stat == &"" or not _stats.has(stat):
		return 1.0
	return clampf(1.0 - get_current(stat), 0.0, 1.0)


## damage_pool with a damage type: scales by resistance first. Fully-resisted
## hits change nothing and never emit defeat, so callers can skip reactions.
func damage_pool_typed(pool_name: StringName, amount: float, damage_type: StringName = &"physical") -> void:
	var mult: float = get_damage_multiplier(damage_type)
	if mult <= 0.0:
		return
	damage_pool(pool_name, amount * mult)


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
	_tick_dots(delta)
	_tick_timed_tag_effects(delta)
	var changed_stats: Array[StringName] = []
	for stat_name: StringName in STAT_NAMES:
		var attr: Attribute = _stats[stat_name] as Attribute
		if attr != null and attr.tick(delta):
			changed_stats.append(stat_name)
	for stat_name: StringName in changed_stats:
		attribute_changed.emit(stat_name, get_current(stat_name))
		_clamp_pool_to_max(stat_name)
	_reap_effect_tags()
	_update_processing()
	_reap_effect_vfx()


## Advances damage-over-time entries, applying each entry's share of pool
## damage (or healing for negative rates) and dropping expired entries.
func _tick_dots(delta: float) -> void:
	for i: int in range(_dots.size() - 1, -1, -1):
		var entry: Dictionary = _dots[i]
		var remaining: float = float(entry.get("remaining", 0.0))
		var step: float = minf(delta, remaining)
		var tick_amount: float = float(entry.get("rate", 0.0)) * step
		var pool_name: StringName = StringName(entry.get("pool", POOL_HEALTH))
		var dtype: StringName = StringName(entry.get("dtype", &"physical"))
		if tick_amount >= 0.0:
			damage_pool_typed(pool_name, tick_amount, dtype)
		else:
			restore_pool(pool_name, -tick_amount)
		if remaining <= delta:
			_dots.remove_at(i)
		else:
			entry["remaining"] = remaining - delta
			_dots[i] = entry


func _tick_timed_tag_effects(delta: float) -> void:
	for i: int in range(_timed_tag_effects.size() - 1, -1, -1):
		var entry: Dictionary = _timed_tag_effects[i]
		var remaining: float = float(entry.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			var id: StringName = StringName(entry.get("id", &""))
			_timed_tag_effects.remove_at(i)
			_unregister_granted_tags(id)
		else:
			entry["remaining"] = remaining
			_timed_tag_effects[i] = entry


func _reap_effect_tags() -> void:
	var expired: Array[StringName] = []
	for instance_id: StringName in _effect_tags.keys():
		if not _has_effect_instance(instance_id):
			expired.append(instance_id)
	for instance_id: StringName in expired:
		_unregister_granted_tags(instance_id)


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
	_apply_export_base(STAT_FIRE_RESISTANCE, base_fire_resistance)
	_apply_export_base(STAT_ROTATION_SPEED, base_rotation_speed)
	for pool_name: StringName in POOL_NAMES:
		var max_stat: StringName = POOL_MAX_LINK[pool_name] as StringName
		_pools[pool_name] = get_current(max_stat)


## Enables ticking only while a timed modifier, damage-over-time, or timed tag entry exists.
func _update_processing() -> void:
	if not _dots.is_empty() or not _timed_tag_effects.is_empty():
		set_process(true)
		return
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
