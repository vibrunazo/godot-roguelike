## Behavioral contract suite for AttributeComponent, Attribute stacking,
## GameplayEffect application, the HealthComponent adapter, and per-scene
## attribute parity. All expectations are relative (deltas, recompute rules,
## transitions), never hardcoded balance numbers.
extends Node

var _change_count: int = 0
var _last_change_name: StringName = &""
var _last_change_value: float = 0.0
var _defeat_count: int = 0

const CHARACTER_SCENES: Array[String] = [
	"res://Player/player.tscn",
	"res://Enemy/enemy_base.tscn",
	"res://Enemy/melee_enemy.tscn",
	"res://Enemy/ranged_enemy.tscn",
	"res://Enemy/enemy_brute.tscn",
	"res://Enemy/enemy_thunder_mage.tscn",
	"res://Enemy/firebomber_enemy.tscn",
]


func _ready() -> void:
	print("--- RUNNING ATTRIBUTE COMPONENT TEST ---")
	_run_all()


func _run_all() -> void:
	_reset_counters()
	if not await _part_stacking_math():
		return
	if not _part_pool_deltas_and_clamp():
		return
	if not await _part_max_buff_expiry_keeps_health():
		return
	await get_tree().process_frame
	if not await _part_timed_expiry_and_processing():
		return
	if not _part_defeat_fires_once():
		return
	if not await _part_health_adapter():
		return
	if not _part_gameplay_effect_roundtrip():
		return
	if not await _part_character_facades():
		return
	if not await _part_scene_parity():
		return
	print("====================================================================")
	print("  ALL ATTRIBUTE COMPONENT TESTS PASSED!                             ")
	print("====================================================================")
	get_tree().quit(0)


func _fail(message: String) -> bool:
	printerr("TEST FAILED: ", message)
	get_tree().quit(1)
	return false


func _reset_counters() -> void:
	_change_count = 0
	_last_change_name = &""
	_last_change_value = 0.0
	_defeat_count = 0


func _on_attr_changed(attribute_name: StringName, current_value: float) -> void:
	_change_count += 1
	_last_change_name = attribute_name
	_last_change_value = current_value


func _on_attr_defeat() -> void:
	_defeat_count += 1


func _make_component() -> AttributeComponent:
	var comp: AttributeComponent = AttributeComponent.new()
	add_child(comp)
	return comp


## PART 1: additive-then-compounding stacking rule with refresh/remove.
func _part_stacking_math() -> bool:
	print("\n>>> PART 1: Modifier stacking math")
	var comp: AttributeComponent = _make_component()
	var base_val: float = 120.0
	var add_val: float = 30.0
	var mult_a: float = 0.5
	var mult_b: float = 0.25
	var comp_mult: float = 0.2
	comp.set_base(AttributeComponent.STAT_ATTACK, base_val)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_val):
		comp.queue_free()
		return _fail("Unmodified stat should equal its base.")
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_add", Attribute.Op.ADD, add_val)
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_mult_a", Attribute.Op.MULT_ADD, mult_a)
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_mult_b", Attribute.Op.MULT_ADD, mult_b)
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_comp", Attribute.Op.MULT_COMP, comp_mult)
	var expected: float = (base_val + add_val) * (1.0 + mult_a + mult_b) * (1.0 + comp_mult)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), expected):
		comp.queue_free()
		return _fail("Stacked value mismatch. Expected %f, got %f." % [expected, comp.get_current(AttributeComponent.STAT_ATTACK)])
	print("Additive stacking verified: ", comp.get_current(AttributeComponent.STAT_ATTACK))
	# Re-applying the same id refreshes instead of double-stacking.
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_add", Attribute.Op.ADD, add_val)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), expected):
		comp.queue_free()
		return _fail("Re-applying the same modifier id must refresh, not stack.")
	# Removing one entry restores the recomputed remainder.
	if not comp.remove_modifier(AttributeComponent.STAT_ATTACK, &"test_mult_b"):
		comp.queue_free()
		return _fail("remove_modifier should report an existing entry.")
	var expected_after: float = (base_val + add_val) * (1.0 + mult_a) * (1.0 + comp_mult)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), expected_after):
		comp.queue_free()
		return _fail("Value after removal mismatch. Expected %f, got %f." % [expected_after, comp.get_current(AttributeComponent.STAT_ATTACK)])
	if comp.remove_modifier(AttributeComponent.STAT_ATTACK, &"missing_id"):
		comp.queue_free()
		return _fail("remove_modifier should report false for an unknown id.")
	# Pools reject modifier stacks.
	if comp.apply_modifier(AttributeComponent.POOL_HEALTH, &"bad", Attribute.Op.ADD, 10.0):
		comp.queue_free()
		return _fail("Pools must reject modifier entries.")
	comp.queue_free()
	await get_tree().process_frame
	print("Refresh, removal, and pool rejection verified.")
	return true


## PART 2: pool deltas are relative and clamped to the max stat.
func _part_pool_deltas_and_clamp() -> bool:
	print("\n>>> PART 2: Pool damage, heal, and clamping")
	var comp: AttributeComponent = _make_component()
	comp.attribute_changed.connect(_on_attr_changed)
	comp.defeat.connect(_on_attr_defeat)
	var max_val: float = 200.0
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, max_val)
	var full: float = comp.get_current(AttributeComponent.POOL_HEALTH)
	var damage: float = 45.0
	_reset_counters()
	comp.damage_pool(AttributeComponent.POOL_HEALTH, damage)
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), full - damage):
		return _fail("Pool should drop by exactly the dealt delta.")
	if _change_count < 1 or _last_change_name != AttributeComponent.POOL_HEALTH:
		return _fail("Pool damage should emit attribute_changed for the pool.")
	var overheal: float = 1000.0
	comp.restore_pool(AttributeComponent.POOL_HEALTH, overheal)
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), max_val):
		return _fail("Overheal must clamp to the max stat.")
	if _defeat_count != 0:
		return _fail("Non-lethal pool changes must not emit defeat.")
	print("Pool deltas and overheal clamp verified.")
	return true


## PART 3: buffing max health then letting it expire never deletes earned HP.
func _part_max_buff_expiry_keeps_health() -> bool:
	print("\n>>> PART 3: Max-HP buff expiry preserves current health")
	var comp: AttributeComponent = _make_component()
	var base_max: float = 200.0
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, base_max)
	var buff: float = 1.0
	var damage: float = 60.0
	comp.apply_modifier(AttributeComponent.STAT_MAX_HEALTH, &"test_max_buff", Attribute.Op.MULT_ADD, buff, 0.25)
	var buffed_max: float = comp.get_current(AttributeComponent.STAT_MAX_HEALTH)
	if not is_equal_approx(buffed_max, base_max * (1.0 + buff)):
		return _fail("Max buff should scale the max stat.")
	comp.damage_pool(AttributeComponent.POOL_HEALTH, damage)
	var wounded: float = comp.get_current(AttributeComponent.POOL_HEALTH)
	await get_tree().create_timer(0.45).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_MAX_HEALTH), base_max):
		return _fail("Max stat should return to base after buff expiry.")
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), wounded):
		return _fail("Buff expiry must not delete earned health (phantom loss).")
	print("Expiry preserved health at ", wounded, " while max returned to ", base_max, ".")
	return true


## PART 4: timed modifiers tick, restore, and gate processing.
func _part_timed_expiry_and_processing() -> bool:
	print("\n>>> PART 4: Timed expiry and zero-overhead processing")
	var comp: AttributeComponent = _make_component()
	var base_speed: float = 10.0
	comp.set_base(AttributeComponent.STAT_SPEED, base_speed)
	if comp.is_processing():
		return _fail("Component must idle with processing disabled.")
	comp.apply_modifier(AttributeComponent.STAT_SPEED, &"test_slow", Attribute.Op.MULT_ADD, -0.5, 0.25)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_SPEED), base_speed * 0.5):
		return _fail("Timed slow should halve the stat while active.")
	if not comp.is_processing():
		return _fail("Timed modifiers must enable processing.")
	await get_tree().create_timer(0.45).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_SPEED), base_speed):
		return _fail("Stat should return to base after timed expiry.")
	if comp.is_processing():
		return _fail("Processing must disable itself once timed modifiers expire.")
	print("Timed expiry and process gating verified.")
	return true


## PART 5: defeat fires exactly once on the killing transition.
func _part_defeat_fires_once() -> bool:
	print("\n>>> PART 5: Defeat fires once on the killing blow")
	var comp: AttributeComponent = _make_component()
	comp.defeat.connect(_on_attr_defeat)
	_reset_counters()
	var max_val: float = 100.0
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, max_val)
	comp.damage_pool(AttributeComponent.POOL_HEALTH, max_val)
	if _defeat_count != 1:
		return _fail("Killing damage should emit defeat exactly once.")
	if comp.is_alive():
		return _fail("Component should report not alive at zero health.")
	comp.damage_pool(AttributeComponent.POOL_HEALTH, 10.0)
	if _defeat_count != 1:
		return _fail("Overkill damage must not re-emit defeat.")
	print("Single defeat emission verified.")
	return true


## PART 6: HealthComponent forwards storage and signals to attributes.
func _part_health_adapter() -> bool:
	print("\n>>> PART 6: HealthComponent attribute adapter")
	var holder: Node = Node.new()
	add_child(holder)
	await get_tree().process_frame
	var comp: AttributeComponent = AttributeComponent.new()
	comp.name = "AttributeComponent"
	holder.add_child(comp)
	var health: HealthComponent = HealthComponent.new()
	holder.add_child(health)
	await get_tree().process_frame
	await get_tree().process_frame
	if health.attribute_component != comp:
		holder.queue_free()
		return _fail("HealthComponent should resolve its sibling AttributeComponent.")
	var changes: Array[float] = []
	health.health_changed.connect(func(value: float) -> void: changes.append(value))
	_defeat_count = 0
	health.defeat.connect(_on_attr_defeat)
	var max_val: float = comp.get_current(AttributeComponent.STAT_MAX_HEALTH)
	var damage: float = 25.0
	health.take_damage(damage)
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), max_val - damage):
		holder.queue_free()
		return _fail("Adapter damage should reduce the attribute pool relatively.")
	if changes.is_empty():
		holder.queue_free()
		return _fail("Adapter damage should forward health_changed.")
	comp.set_pool_current(AttributeComponent.POOL_HEALTH, max_val)
	if _defeat_count != 0:
		holder.queue_free()
		return _fail("Direct pool writes must never emit defeat.")
	health.take_damage(max_val)
	if _defeat_count != 1:
		holder.queue_free()
		return _fail("Lethal adapter damage should forward defeat exactly once.")
	holder.queue_free()
	await get_tree().process_frame
	print("Adapter verb, signals, and defeat forwarding verified.")
	return true


## PART 7: GameplayEffect applies and removes through the component.
func _part_gameplay_effect_roundtrip() -> bool:
	print("\n>>> PART 7: GameplayEffect apply/remove roundtrip")
	var comp: AttributeComponent = _make_component()
	var base_attack: float = 100.0
	comp.set_base(AttributeComponent.STAT_ATTACK, base_attack)
	var effect: GameplayEffect = GameplayEffect.new()
	effect.effect_name = "test_rage"
	effect.target_attribute = AttributeComponent.STAT_ATTACK
	effect.operation = Attribute.Op.MULT_ADD
	effect.magnitude = 0.5
	effect.duration = 0.0
	var instance_id: StringName = comp.apply_effect(effect)
	if instance_id == &"":
		return _fail("apply_effect should return a live instance id.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_attack * 1.5):
		return _fail("Effect should scale the stat while applied.")
	if not comp.remove_effect(instance_id):
		return _fail("remove_effect should find the applied instance.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_attack):
		return _fail("Effect removal should restore the base-derived value.")
	if comp.remove_effect(instance_id):
		return _fail("Removing the same instance twice should report false.")
	print("GameplayEffect roundtrip verified.")
	return true


## PART 8: Character facades read and write through attributes.
func _part_character_facades() -> bool:
	print("\n>>> PART 8: Character stat facades")
	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	await get_tree().physics_frame
	await get_tree().process_frame
	if player.attribute_component == null:
		player.queue_free()
		return _fail("Player should wire an AttributeComponent.")
	var attrs: AttributeComponent = player.attribute_component
	if not is_equal_approx(player.movement_speed, attrs.get_current(AttributeComponent.STAT_SPEED)):
		player.queue_free()
		return _fail("movement_speed facade should read the speed stat.")
	if not is_equal_approx(player.damage_stat, attrs.get_current(AttributeComponent.STAT_ATTACK)):
		player.queue_free()
		return _fail("damage_stat facade should read the attack stat.")
	var new_speed: float = player.movement_speed + 2.0
	player.movement_speed = new_speed
	if not is_equal_approx(attrs.get_base(AttributeComponent.STAT_SPEED), new_speed):
		player.queue_free()
		return _fail("Writing movement_speed should update the speed base.")
	var modifier_before: float = player.get_damage_modifier()
	var buff: float = 0.5
	attrs.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_facade_buff", Attribute.Op.MULT_ADD, buff)
	if not is_equal_approx(player.get_damage_modifier(), modifier_before * (1.0 + buff)):
		player.queue_free()
		return _fail("Attack buffs should scale get_damage_modifier relatively.")
	var full: float = attrs.get_current(AttributeComponent.POOL_HEALTH)
	var damage: float = 7.0
	player.health_component.take_damage(damage)
	if not is_equal_approx(attrs.get_current(AttributeComponent.POOL_HEALTH), full - damage):
		player.queue_free()
		return _fail("Player damage should flow into the attribute pool.")
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Character facades verified.")
	return true


## PART 9: every shipped character keeps legacy readings through attributes.
func _part_scene_parity() -> bool:
	print("\n>>> PART 9: Per-scene attribute parity")
	for scene_path: String in CHARACTER_SCENES:
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			return _fail("Could not load %s." % scene_path)
		var character: Character = packed.instantiate() as Character
		if character == null:
			return _fail("Scene %s did not instantiate a Character." % scene_path)
		add_child(character)
		await get_tree().physics_frame
		await get_tree().process_frame
		if character.attribute_component == null:
			character.queue_free()
			return _fail("Scene %s wires no AttributeComponent." % scene_path)
		var attrs: AttributeComponent = character.attribute_component
		if not is_equal_approx(attrs.get_base(AttributeComponent.STAT_MAX_HEALTH), attrs.get_current(AttributeComponent.STAT_MAX_HEALTH)):
			character.queue_free()
			return _fail("Scene %s max_health base drifted from its current value." % scene_path)
		if not is_equal_approx(attrs.get_current(AttributeComponent.POOL_HEALTH), attrs.get_current(AttributeComponent.STAT_MAX_HEALTH)):
			character.queue_free()
			return _fail("Scene %s health pool did not spawn full." % scene_path)
		if not is_equal_approx(character.movement_speed, attrs.get_current(AttributeComponent.STAT_SPEED)):
			character.queue_free()
			return _fail("Scene %s movement_speed drifted from its attribute base." % scene_path)
		print("Parity OK: ", scene_path)
		character.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	return true
