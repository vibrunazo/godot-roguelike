## Behavioral contract suite for AttributeComponent, Attribute stacking,
## GameplayEffect application, Hurtbox damage routing, and per-scene attribute
## parity. All expectations are relative (deltas, recompute rules,
## transitions), never hardcoded balance numbers.
extends "res://test/lib/test_suite.gd"

var _change_count: int = 0
var _last_change_name: StringName = &""
var _last_change_value: float = 0.0
var _defeat_count: int = 0
var _struck_reactions: int = 0

## Where test-owned status visuals sit relative to their host.
const VFX_OFFSET: Vector3 = Vector3(0.0, 0.6, 0.0)

const CHARACTER_SCENES: Array[String] = [
	"res://Player/player.tscn",
	"res://Enemy/enemy_base.tscn",
	"res://Enemy/melee_enemy.tscn",
	"res://Enemy/ranged_enemy.tscn",
	"res://Enemy/enemy_brute.tscn",
	"res://Enemy/enemy_thunder_mage.tscn",
	"res://Enemy/firebomber_enemy.tscn",
]


func before_each() -> void:
	_reset_counters()
	_struck_reactions = 0


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


func _on_test_health_changed(_value: float) -> void:
	_struck_reactions += 1


func _make_component() -> AttributeComponent:
	var comp: AttributeComponent = AttributeComponent.new()
	add_child(comp)
	return comp


## An AttributeComponent on a bare Node3D body with a StatusVisualsComponent,
## so status visuals show under that body (see _visuals()).
func _make_visual_host() -> AttributeComponent:
	var body: Node3D = Node3D.new()
	add_child(body)
	var comp: AttributeComponent = AttributeComponent.new()
	body.add_child(comp)
	var visuals: StatusVisualsComponent = StatusVisualsComponent.new()
	visuals.attribute_component = comp
	visuals.visual_parent = body
	body.add_child(visuals)
	return comp


## The status visuals shown on comp's body (its Node3D children; the
## components themselves are plain Nodes).
func _visuals(comp: AttributeComponent) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child: Node in comp.get_parent().get_children():
		if child is Node3D and not child.is_queued_for_deletion():
			found.append(child as Node3D)
	return found


## A test-owned health-pool effect draining total_damage over duration
## (0 = instant), optionally showing vfx_scene at VFX_OFFSET.
func _pool_effect(effect_name: String, total_damage: float, duration: float, vfx_scene: PackedScene = null) -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.effect_name = effect_name
	effect.target_attribute = AttributeComponent.POOL_HEALTH
	effect.total_damage = total_damage
	effect.duration = duration
	effect.vfx_scene = vfx_scene
	effect.vfx_offset = VFX_OFFSET
	return effect


## A test-owned 20 m square floor whose top sits at y = 0.
func _add_floor() -> StaticBody3D:
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.add_child(shape)
	add_child(floor_body)
	return floor_body


## The BoneAttachment3D following bone_name under the character's skeleton,
## or null.
func _find_bone_slot(character: Character, bone_name: String) -> BoneAttachment3D:
	var skel: Skeleton3D = character.find_child("*Skeleton*", true, false) as Skeleton3D
	if skel == null:
		return null
	for child: Node in skel.get_children():
		if child is BoneAttachment3D and (child as BoneAttachment3D).bone_name == bone_name:
			return child as BoneAttachment3D
	return null


## PART 1: additive-then-compounding stacking rule with refresh/remove.
func test_stacking_math() -> bool:
	print("\n>>> PART 1: Modifier stacking math")
	var comp: AttributeComponent = _make_component()
	var base_val: float = 120.0
	var add_val: float = 30.0
	var mult_a: float = 0.5
	var mult_b: float = 0.25
	var comp_mult: float = 0.2
	comp.set_base(AttributeComponent.STAT_ATTACK, base_val)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_val):
		return fail("Unmodified stat should equal its base.")
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_add", Attribute.Op.ADD, add_val)
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_mult_a", Attribute.Op.MULT_ADD, mult_a)
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_mult_b", Attribute.Op.MULT_ADD, mult_b)
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_comp", Attribute.Op.MULT_COMP, comp_mult)
	var expected: float = (base_val + add_val) * (1.0 + mult_a + mult_b) * (1.0 + comp_mult)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), expected):
		return fail("Stacked value mismatch. Expected %f, got %f." % [expected, comp.get_current(AttributeComponent.STAT_ATTACK)])
	print("Additive stacking verified: ", comp.get_current(AttributeComponent.STAT_ATTACK))
	# Re-applying the same id refreshes instead of double-stacking.
	comp.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_add", Attribute.Op.ADD, add_val)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), expected):
		return fail("Re-applying the same modifier id must refresh, not stack.")
	# Removing one entry restores the recomputed remainder.
	if not comp.remove_modifier(AttributeComponent.STAT_ATTACK, &"test_mult_b"):
		return fail("remove_modifier should report an existing entry.")
	var expected_after: float = (base_val + add_val) * (1.0 + mult_a) * (1.0 + comp_mult)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), expected_after):
		return fail("Value after removal mismatch. Expected %f, got %f." % [expected_after, comp.get_current(AttributeComponent.STAT_ATTACK)])
	if comp.remove_modifier(AttributeComponent.STAT_ATTACK, &"missing_id"):
		return fail("remove_modifier should report false for an unknown id.")
	# Pools reject modifier stacks.
	if comp.apply_modifier(AttributeComponent.POOL_HEALTH, &"bad", Attribute.Op.ADD, 10.0):
		return fail("Pools must reject modifier entries.")
	print("Refresh, removal, and pool rejection verified.")
	return true


## PART 2: pool deltas are relative and clamped to the max stat.
func test_pool_deltas_and_clamp() -> bool:
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
		return fail("Pool should drop by exactly the dealt delta.")
	if _change_count < 1 or _last_change_name != AttributeComponent.POOL_HEALTH:
		return fail("Pool damage should emit attribute_changed for the pool.")
	var overheal: float = 1000.0
	comp.restore_pool(AttributeComponent.POOL_HEALTH, overheal)
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), max_val):
		return fail("Overheal must clamp to the max stat.")
	if _defeat_count != 0:
		return fail("Non-lethal pool changes must not emit defeat.")
	print("Pool deltas and overheal clamp verified.")
	return true


## PART 3: buffing max health then letting it expire never deletes earned HP.
func test_max_buff_expiry_keeps_health() -> bool:
	print("\n>>> PART 3: Max-HP buff expiry preserves current health")
	var comp: AttributeComponent = _make_component()
	var base_max: float = 200.0
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, base_max)
	var buff: float = 1.0
	var damage: float = 60.0
	comp.apply_modifier(AttributeComponent.STAT_MAX_HEALTH, &"test_max_buff", Attribute.Op.MULT_ADD, buff, 0.25)
	var buffed_max: float = comp.get_current(AttributeComponent.STAT_MAX_HEALTH)
	if not is_equal_approx(buffed_max, base_max * (1.0 + buff)):
		return fail("Max buff should scale the max stat.")
	comp.damage_pool(AttributeComponent.POOL_HEALTH, damage)
	var wounded: float = comp.get_current(AttributeComponent.POOL_HEALTH)
	await get_tree().create_timer(0.45).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_MAX_HEALTH), base_max):
		return fail("Max stat should return to base after buff expiry.")
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), wounded):
		return fail("Buff expiry must not delete earned health (phantom loss).")
	print("Expiry preserved health at ", wounded, " while max returned to ", base_max, ".")
	return true


## PART 4: timed modifiers tick, restore, and gate processing.
func test_timed_expiry_and_processing() -> bool:
	print("\n>>> PART 4: Timed expiry and zero-overhead processing")
	var comp: AttributeComponent = _make_component()
	var base_speed: float = 10.0
	comp.set_base(AttributeComponent.STAT_SPEED, base_speed)
	if comp.is_processing():
		return fail("Component must idle with processing disabled.")
	comp.apply_modifier(AttributeComponent.STAT_SPEED, &"test_slow", Attribute.Op.MULT_ADD, -0.5, 0.25)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_SPEED), base_speed * 0.5):
		return fail("Timed slow should halve the stat while active.")
	if not comp.is_processing():
		return fail("Timed modifiers must enable processing.")
	await get_tree().create_timer(0.45).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_SPEED), base_speed):
		return fail("Stat should return to base after timed expiry.")
	if comp.is_processing():
		return fail("Processing must disable itself once timed modifiers expire.")
	print("Timed expiry and process gating verified.")
	return true


## PART 5: defeat fires exactly once on the killing transition.
func test_defeat_fires_once() -> bool:
	print("\n>>> PART 5: Defeat fires once on the killing blow")
	var comp: AttributeComponent = _make_component()
	comp.defeat.connect(_on_attr_defeat)
	_reset_counters()
	var max_val: float = 100.0
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, max_val)
	comp.damage_pool(AttributeComponent.POOL_HEALTH, max_val)
	if _defeat_count != 1:
		return fail("Killing damage should emit defeat exactly once.")
	if comp.is_alive():
		return fail("Component should report not alive at zero health.")
	comp.damage_pool(AttributeComponent.POOL_HEALTH, 10.0)
	if _defeat_count != 1:
		return fail("Overkill damage must not re-emit defeat.")
	print("Single defeat emission verified.")
	return true


## PART 6: Hurtbox routes damage into the attribute pool and rejects corpses.
func test_health_adapter() -> bool:
	print("\n>>> PART 6: Hurtbox damage routing")
	var holder: Node3D = Node3D.new()
	add_child(holder)
	await get_tree().process_frame
	var comp: AttributeComponent = AttributeComponent.new()
	comp.name = "AttributeComponent"
	holder.add_child(comp)
	var hurtbox: Hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.attribute_component = comp
	holder.add_child(hurtbox)
	await get_tree().process_frame
	await get_tree().process_frame
	_reset_counters()
	comp.attribute_changed.connect(_on_attr_changed)
	comp.defeat.connect(_on_attr_defeat)
	var max_val: float = comp.get_current(AttributeComponent.STAT_MAX_HEALTH)
	var damage: float = 25.0
	if not hurtbox.receive_hit(damage, Vector3.ZERO):
		return fail("receive_hit should report damage on a live target.")
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), max_val - damage):
		return fail("Hurtbox damage should reduce the attribute pool relatively.")
	if _change_count < 1 or _last_change_name != AttributeComponent.POOL_HEALTH:
		return fail("Pool damage should emit attribute_changed for the pool.")
	if not hurtbox.receive_hit(max_val, Vector3.ZERO):
		return fail("Lethal receive_hit should still report damage.")
	if _defeat_count != 1:
		return fail("Lethal Hurtbox damage should emit defeat exactly once.")
	if hurtbox.receive_hit(10.0, Vector3.ZERO):
		return fail("Corpses must reject further hits.")
	if _defeat_count != 1:
		return fail("Overkill hits must not re-emit defeat.")
	print("Hurtbox routing, signals, and corpse rejection verified.")
	return true


## PART 7: GameplayEffect applies and removes through the component.
func test_gameplay_effect_roundtrip() -> bool:
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
		return fail("apply_effect should return a live instance id.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_attack * 1.5):
		return fail("Effect should scale the stat while applied.")
	if not comp.remove_effect(instance_id):
		return fail("remove_effect should find the applied instance.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_attack):
		return fail("Effect removal should restore the base-derived value.")
	if comp.remove_effect(instance_id):
		return fail("Removing the same instance twice should report false.")
	# REFRESH (default): re-applying restarts the single entry, never stacks.
	var first_id: StringName = comp.apply_effect(effect)
	var second_id: StringName = comp.apply_effect(effect)
	if first_id != second_id:
		return fail("REFRESH re-application should return the same instance id.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_attack * 1.5):
		return fail("REFRESH re-application must not double-stack the magnitude.")
	if not comp.remove_effect(first_id):
		return fail("REFRESH removal should clear the entry.")
	# STACK: each application adds an independent entry with its own id.
	var poison: GameplayEffect = GameplayEffect.new()
	poison.effect_name = "test_poison"
	poison.target_attribute = AttributeComponent.STAT_ATTACK
	poison.operation = Attribute.Op.ADD
	poison.magnitude = 10.0
	poison.duration = 0.0
	poison.stacking = GameplayEffect.Stacking.STACK
	var stack_a: StringName = comp.apply_effect(poison)
	var stack_b: StringName = comp.apply_effect(poison)
	if stack_a == stack_b:
		return fail("STACK applications should mint distinct instance ids.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_attack + 20.0):
		return fail("Two STACK entries should both contribute.")
	if not comp.remove_effect(stack_a):
		return fail("Removing one stack should succeed.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_attack + 10.0):
		return fail("One remaining stack should contribute once.")
	if not comp.remove_effect(stack_b):
		return fail("Removing the last stack should succeed.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_ATTACK), base_attack):
		return fail("Removing all stacks should restore the base value.")
	print("GameplayEffect roundtrip, REFRESH, and STACK verified.")
	return true


## PART 8: Character stats, damage modifier, and Hurtbox route through attributes.
func test_character_facades() -> bool:
	print("\n>>> PART 8: Character attribute integration")
	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	await get_tree().physics_frame
	await get_tree().process_frame
	if player.attribute_component == null:
		return fail("Player should wire an AttributeComponent.")
	var attrs: AttributeComponent = player.attribute_component
	var base_speed: float = attrs.get_base(AttributeComponent.STAT_SPEED)
	if base_speed <= 0.0:
		return fail("Player speed base should be positive.")
	var speed_bonus: float = 2.0
	attrs.set_base(AttributeComponent.STAT_SPEED, base_speed + speed_bonus)
	if not is_equal_approx(attrs.get_current(AttributeComponent.STAT_SPEED), base_speed + speed_bonus):
		return fail("Speed base writes should move the speed stat.")
	var modifier_before: float = player.get_damage_modifier()
	var buff: float = 0.5
	attrs.apply_modifier(AttributeComponent.STAT_ATTACK, &"test_facade_buff", Attribute.Op.MULT_ADD, buff)
	if not is_equal_approx(player.get_damage_modifier(), modifier_before * (1.0 + buff)):
		return fail("Attack buffs should scale get_damage_modifier relatively.")
	var full: float = attrs.get_current(AttributeComponent.POOL_HEALTH)
	var damage: float = 7.0
	var player_hurtbox: Hurtbox = player.get_node_or_null("Hurtbox") as Hurtbox
	if player_hurtbox == null or not player_hurtbox.receive_hit(damage, Vector3.ZERO):
		return fail("Player Hurtbox should route hits into the attribute pool.")
	if not is_equal_approx(attrs.get_current(AttributeComponent.POOL_HEALTH), full - damage):
		return fail("Player damage should flow into the attribute pool.")
	print("Character attribute integration verified.")
	return true


## PART 9: an attack's hit effects apply on the hit and refresh on a re-hit
## instead of stacking a second copy (test-owned slow on the melee weapon).
func test_hit_effects_refresh_instead_of_stacking() -> bool:
	var attacker: Character = spawn(load("res://Enemy/melee_enemy.tscn") as PackedScene) as Character
	var victim: Character = spawn(load("res://Player/player.tscn") as PackedScene) as Character
	disable_ai(attacker)
	await get_tree().physics_frame
	var attack_comp: AttackComponent = (attacker.state_machine.get_node("EnemyAttack") as CharacterAttack).get_attack_component()
	var slow: GameplayEffect = GameplayEffect.new()
	slow.effect_name = "test_slow"
	slow.target_attribute = AttributeComponent.STAT_SPEED
	slow.operation = Attribute.Op.MULT_ADD
	slow.magnitude = -0.5
	slow.duration = 5.0
	var effects: Array[GameplayEffect] = [slow]
	attack_comp.effects_to_apply = effects
	attack_comp.reset_exceptions()
	var victim_attrs: AttributeComponent = victim.attribute_component
	var base_speed: float = victim_attrs.get_base(AttributeComponent.STAT_SPEED)
	if not attack_comp.deal_damage_to(victim.hurtbox, 0.0, Vector3.ZERO):
		return fail("Confirmed hits should report success.")
	var expected_slowed: float = base_speed * (1.0 + slow.magnitude)
	if not is_equal_approx(victim_attrs.get_current(AttributeComponent.STAT_SPEED), expected_slowed):
		return fail("The hit effect should scale speed by its own magnitude.")
	attack_comp.reset_exceptions()
	if not attack_comp.deal_damage_to(victim.hurtbox, 0.0, Vector3.ZERO):
		return fail("Second confirmed hit should report success.")
	if not is_equal_approx(victim_attrs.get_current(AttributeComponent.STAT_SPEED), expected_slowed):
		return fail("Re-hitting must refresh the effect, not stack a second copy.")
	return true


## PART 10: every shipped character carries consistent attribute bases.
func test_scene_parity() -> bool:
	print("\n>>> PART 10: Per-scene attribute parity")
	for scene_path: String in CHARACTER_SCENES:
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			return fail("Could not load %s." % scene_path)
		var character: Character = packed.instantiate() as Character
		if character == null:
			return fail("Scene %s did not instantiate a Character." % scene_path)
		add_child(character)
		await get_tree().physics_frame
		await get_tree().process_frame
		if character.attribute_component == null:
			return fail("Scene %s wires no AttributeComponent." % scene_path)
		var attrs: AttributeComponent = character.attribute_component
		if not is_equal_approx(attrs.get_base(AttributeComponent.STAT_MAX_HEALTH), attrs.get_current(AttributeComponent.STAT_MAX_HEALTH)):
			return fail("Scene %s max_health base drifted from its current value." % scene_path)
		if not is_equal_approx(attrs.get_current(AttributeComponent.POOL_HEALTH), attrs.get_current(AttributeComponent.STAT_MAX_HEALTH)):
			return fail("Scene %s health pool did not spawn full." % scene_path)
		if attrs.get_current(AttributeComponent.STAT_SPEED) <= 0.0:
			return fail("Scene %s has a non-positive speed stat." % scene_path)
		print("Parity OK: ", scene_path)
		character.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	return true


## PART 11a: fire sources share one burn identity, so any of them refreshes
## the same burn instead of stacking lookalikes.
func test_fire_sources_share_one_burn() -> bool:
	print("\n>>> PART 11a: Fire sources share one burn")
	var projectile: Area3D = spawn(load("res://Enemy/fireball_projectile.tscn") as PackedScene) as Area3D
	var trap: Node3D = spawn(load("res://Hazards/fire_trap.tscn") as PackedScene, null, Vector3(10.0, 0.0, 0.0)) as Node3D
	var firebomb: Area3D = spawn(load("res://Enemy/firebomb_projectile.tscn") as PackedScene, null, Vector3(-10.0, 0.0, 0.0)) as Area3D
	await get_tree().process_frame
	var proj_attack: AttackComponent = projectile.get_node_or_null("AttackComponent") as AttackComponent
	if proj_attack == null or proj_attack.effects_to_apply.is_empty():
		return fail("Fireball AttackComponent should configure a hit effect.")
	var burn: GameplayEffect = proj_attack.effects_to_apply[0]
	if burn.target_attribute != AttributeComponent.POOL_HEALTH or burn.total_damage <= 0.0 or burn.duration <= 0.0:
		return fail("Fireball burn should target the health pool with a positive timed total.")
	if burn.vfx_scene == null:
		return fail("Fireball burn should link a status visual scene.")
	var trap_attack: AttackComponent = trap.get_node_or_null("DamageHitbox/AttackComponent") as AttackComponent
	var bomb_attack: AttackComponent = firebomb.get_node_or_null("AttackComponent") as AttackComponent
	if trap_attack == null or bomb_attack == null or trap_attack.effects_to_apply.is_empty() or bomb_attack.effects_to_apply.is_empty():
		return fail("Fire trap and firebomb should each configure a hit effect.")
	for other: GameplayEffect in [trap_attack.effects_to_apply[0], bomb_attack.effects_to_apply[0]]:
		if other.effect_name != burn.effect_name:
			return fail("Fire sources should share one burn identity, so any of them refreshes the same burn.")
	return true


## PART 11b: damage-over-time drain, refresh, and expiry; instant pool effects
## apply at once.
func test_damage_over_time() -> bool:
	print("\n>>> PART 11b: Damage over time")
	var comp: AttributeComponent = _make_component()
	var max_val: float = 200.0
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, max_val)
	comp.restore_pool(AttributeComponent.POOL_HEALTH, max_val)
	var dot: GameplayEffect = _pool_effect("test_burn", 20.0, 0.4)
	if comp.apply_effect(dot) == &"":
		return fail("DoT application should return a live instance id.")
	if not comp.is_processing():
		return fail("Active DoT should enable processing.")
	await get_tree().create_timer(0.2).timeout
	await get_tree().process_frame
	var mid: float = comp.get_current(AttributeComponent.POOL_HEALTH)
	if not (mid < max_val and mid > max_val - dot.total_damage):
		return fail("DoT should be partially drained mid-duration.")
	var refresh_id: StringName = comp.apply_effect(dot)
	if refresh_id == &"":
		return fail("DoT re-application should refresh.")
	await get_tree().create_timer(0.6).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var drained: float = max_val - comp.get_current(AttributeComponent.POOL_HEALTH)
	if drained < 25.0 or drained > 35.0:
		return fail("Refreshed DoT should drain its remainder plus one total, got %f." % drained)
	if comp.is_processing():
		return fail("Processing must disable itself once the DoT expires.")
	if comp.remove_effect(refresh_id):
		return fail("Expired DoT entries should already be gone.")
	# Instant pool effects apply their total immediately with no entry.
	comp.apply_effect(_pool_effect("test_potion", -30.0, 0.0))
	if comp.is_processing():
		return fail("Instant effects must never enable processing.")
	print("DoT drain, refresh, expiry, and instant pools verified.")
	return true


## PART 12: struck reactions (health_changed, hence stun, damage flash, and
## hurt shake) fire once per landed hit; DoT ticks drain the pool silently.
func test_dot_suppresses_reactions() -> bool:
	print("\n>>> PART 12: DoT reaction suppression")
	var player: Character = spawn(load("res://Player/player.tscn") as PackedScene) as Character
	await get_tree().process_frame
	await get_tree().process_frame
	if player == null:
		return fail("Player scene should instantiate a Character.")
	var player_hurtbox: Hurtbox = player.get_node_or_null("Hurtbox") as Hurtbox
	var comp: AttributeComponent = player.get_node_or_null("AttributeComponent") as AttributeComponent
	if player_hurtbox == null or comp == null:
		return fail("Player should wire a Hurtbox and an AttributeComponent.")
	_struck_reactions = 0
	player.health_changed.connect(_on_test_health_changed)
	if not player_hurtbox.receive_hit(5.0, Vector3.ZERO):
		return fail("Direct hit should land.")
	if _struck_reactions != 1:
		return fail("Direct hit should emit exactly one struck reaction.")
	var before: float = comp.get_current(AttributeComponent.POOL_HEALTH)
	var burn_vfx: PackedScene = load("res://Singletons/VFX/status_burning.tscn") as PackedScene
	if burn_vfx == null:
		return fail("Status burning VFX scene should load.")
	player.global_position = Vector3(5.0, 0.0, 7.0)
	if comp.apply_effect(_pool_effect("test_burn_reaction", 10.0, 0.4, burn_vfx)) == &"":
		return fail("Burn application should return a live instance id.")
	await get_tree().process_frame
	var burn_fx: Node3D = player.get_node_or_null("StatusBurning") as Node3D
	if burn_fx == null:
		return fail("Burn visual should attach to the victim's body.")
	var ride_offset: Vector3 = burn_fx.global_position - player.global_position
	if ride_offset.distance_to(VFX_OFFSET) > 0.05:
		return fail("Burn visual should ride the victim at its offset, got %s." % ride_offset)
	await get_tree().create_timer(0.6).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var drained: float = before - comp.get_current(AttributeComponent.POOL_HEALTH)
	if drained < 8.0 or drained > 12.0:
		return fail("Burn should drain its total over time, got %f." % drained)
	if _struck_reactions != 1:
		return fail("Burn ticks must not re-emit struck reactions, got %d." % _struck_reactions)
	print("Struck-gated reactions and silent DoT drain verified.")
	return true


## PART 13a: a timed effect's status visual spawns once at the configured
## offset, survives refresh, and frees on expiry.
func test_effect_vfx_lifecycle() -> bool:
	print("\n>>> PART 13a: Effect status visual lifecycle")
	var burn_vfx: PackedScene = load("res://Singletons/VFX/status_burning.tscn") as PackedScene
	if burn_vfx == null:
		return fail("Status burning VFX scene should load.")
	var comp: AttributeComponent = _make_visual_host()
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, 200.0)
	comp.restore_pool(AttributeComponent.POOL_HEALTH, 200.0)
	var burn: GameplayEffect = _pool_effect("test_burn_vfx", 10.0, 0.3, burn_vfx)
	var burn_id: StringName = comp.apply_effect(burn)
	if burn_id == &"":
		return fail("Burn application should return a live instance id.")
	if _visuals(comp).size() != 1:
		return fail("Timed effect with a scene should spawn exactly one visual.")
	var fx: Node3D = _visuals(comp)[0]
	if not is_equal_approx(fx.position.y, VFX_OFFSET.y):
		return fail("Effect visual should sit at the configured offset.")
	var refresh_id: StringName = comp.apply_effect(burn)
	if refresh_id != burn_id or _visuals(comp).size() != 1 or _visuals(comp)[0] != fx:
		return fail("Refresh should reuse the live visual, not spawn a second.")
	await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(fx) or not _visuals(comp).is_empty():
		return fail("Expired effect should free its visual.")
	print("Effect visual spawn, refresh reuse, and expiry verified.")
	return true


## PART 13b: only effects with a scene that last show a visual: instant effects
## and sceneless effects spawn nothing, and a timed stat effect's or a
## permanent tag-only effect's visual frees on manual removal.
func test_effect_vfx_needs_timed_effect_and_scene() -> bool:
	print("\n>>> PART 13b: Which effects show a status visual")
	var burn_vfx: PackedScene = load("res://Singletons/VFX/status_burning.tscn") as PackedScene
	if burn_vfx == null:
		return fail("Status burning VFX scene should load.")
	var comp: AttributeComponent = _make_visual_host()
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, 200.0)
	comp.restore_pool(AttributeComponent.POOL_HEALTH, 200.0)
	comp.apply_effect(_pool_effect("test_instant_vfx", 5.0, 0.0, burn_vfx))
	if not _visuals(comp).is_empty():
		return fail("Instant effects must never spawn a visual.")
	var chill: GameplayEffect = GameplayEffect.new()
	chill.effect_name = "test_chill_vfx"
	chill.target_attribute = AttributeComponent.STAT_SPEED
	chill.operation = Attribute.Op.MULT_ADD
	chill.magnitude = -0.5
	chill.duration = 30.0
	chill.vfx_scene = burn_vfx
	var chill_id: StringName = comp.apply_effect(chill)
	if chill_id == &"" or _visuals(comp).size() != 1:
		return fail("Timed stat effect should spawn its visual.")
	var chill_fx: Node3D = _visuals(comp)[0]
	if not comp.remove_effect(chill_id):
		return fail("Stat effect removal should succeed.")
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(chill_fx) or not _visuals(comp).is_empty():
		return fail("Removed effect should free its visual.")
	if comp.apply_effect(_pool_effect("test_plain_dot", 5.0, 0.3)) == &"":
		return fail("Sceneless DoT should still apply.")
	if not _visuals(comp).is_empty():
		return fail("Effects without a scene must spawn nothing.")
	var marked: GameplayEffect = GameplayEffect.new()
	marked.effect_name = "test_marked_vfx"
	marked.target_attribute = &""
	marked.granted_tags = [&"test.marked"]
	marked.vfx_scene = burn_vfx
	var marked_id: StringName = comp.apply_effect(marked)
	if marked_id == &"" or _visuals(comp).size() != 1:
		return fail("A permanent tag-only effect with a scene should show its visual.")
	var marked_fx: Node3D = _visuals(comp)[0]
	comp.remove_effect(marked_id)
	await get_tree().process_frame
	if is_instance_valid(marked_fx):
		return fail("Removing a tag-only effect should free its visual.")
	print("Instant, sceneless and removed-effect visuals verified.")
	return true


## PART 14: defeated enemies rest where they fell without blocking movement:
## the body shape is shut off (walk-through corpses) while the defeat state
## pins velocity to zero, so the corpse never drifts or falls through.
func test_corpse_stays_grounded() -> bool:
	print("\n>>> PART 14: Corpse grounding")
	_add_floor()
	var enemy: Character = (load("res://Enemy/melee_enemy.tscn") as PackedScene).instantiate() as Character
	add_child(enemy)
	enemy.global_position = Vector3(0.0, 1.0, 0.0)
	if not await wait_until(func() -> bool: return enemy.is_on_floor(), "setup: the enemy should land"):
		return false
	var rest_y: float = enemy.global_position.y
	var enemy_attrs: AttributeComponent = enemy.get_node("AttributeComponent") as AttributeComponent
	enemy_attrs.damage_pool(AttributeComponent.POOL_HEALTH, enemy_attrs.get_current(AttributeComponent.STAT_MAX_HEALTH))
	# Grounding holds over time: give the corpse a second to drift or fall.
	await wait_physics_frames(Engine.physics_ticks_per_second)
	if enemy.collision_shape_3d == null or not enemy.collision_shape_3d.disabled:
		return fail("Defeat must shut off the body shape so corpses never block.")
	var enemy_hurtbox: Hurtbox = enemy.get_node_or_null("Hurtbox") as Hurtbox
	if enemy_hurtbox == null or enemy_hurtbox.monitoring or enemy_hurtbox.monitorable:
		return fail("Defeat must shut off the hurtbox so corpses are never re-hit.")
	if enemy.global_position.y < rest_y - 0.5:
		return fail("Corpse fell through the floor, y %f -> %f." % [rest_y, enemy.global_position.y])
	print("Corpse non-blocking shutdown and grounding verified.")
	return true


## PART 15: a lethal hit through the real hit path must settle in the defeat
## state. Defeat is reported during damage_pool, before struck reactions fire,
## so the dead must ignore stun or it would override defeat and leave the
## corpse stuck standing.
func test_lethal_hit_reaches_defeat() -> bool:
	print("\n>>> PART 15: Lethal hit reaches defeat")
	_add_floor()
	var enemy: Character = (load("res://Enemy/melee_enemy.tscn") as PackedScene).instantiate() as Character
	add_child(enemy)
	enemy.global_position = Vector3(0.0, 1.0, 0.0)
	if not await wait_until(func() -> bool: return enemy.is_on_floor(), "setup: the enemy should land"):
		return false
	var enemy_hurtbox: Hurtbox = enemy.get_node_or_null("Hurtbox") as Hurtbox
	if enemy_hurtbox == null:
		return fail("Melee enemy should wire a Hurtbox.")
	if not enemy_hurtbox.receive_hit(99999.0, Vector3.ZERO):
		return fail("Lethal hit should land.")
	if not await wait_until(func() -> bool: return enemy.state_machine.state == enemy.defeat_state, "Lethal hit should settle in the defeat state."):
		return false
	print("Lethal hit defeat verified.")
	return true


## PART 16: permanent max-HP gains raise current HP by the same amount (shop
## sigil case); timed gains grant capacity only so expiry deletes nothing;
## removing a gain re-clamps an over-full pool but preserves wounds.
func test_max_raise_carries_pool() -> bool:
	print("\n>>> PART 16: Permanent max-HP gains raise current HP")
	var comp: AttributeComponent = _make_component()
	var base_max: float = 200.0
	var gain: float = 20.0
	comp.set_base(AttributeComponent.STAT_MAX_HEALTH, base_max)
	comp.set_pool_current(AttributeComponent.POOL_HEALTH, base_max)
	comp.apply_modifier(AttributeComponent.STAT_MAX_HEALTH, &"test_max_gain", Attribute.Op.ADD, gain)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_MAX_HEALTH), base_max + gain):
		return fail("Permanent max buff should raise the max stat.")
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), base_max + gain):
		return fail("Permanent max-HP gain must raise current HP by the same amount.")
	var timed_gain: float = 30.0
	comp.apply_modifier(AttributeComponent.STAT_MAX_HEALTH, &"test_max_timed", Attribute.Op.ADD, timed_gain, 5.0)
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_MAX_HEALTH), base_max + gain + timed_gain):
		return fail("Timed max buff should raise the max stat.")
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), base_max + gain):
		return fail("Timed max buff must not raise current HP.")
	if not comp.remove_modifier(AttributeComponent.STAT_MAX_HEALTH, &"test_max_timed"):
		return fail("Timed max buff should be removable.")
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), base_max + gain):
		return fail("Removing a timed max buff must not delete health.")
	if not comp.remove_modifier(AttributeComponent.STAT_MAX_HEALTH, &"test_max_gain"):
		return fail("Permanent max buff should be removable.")
	if not is_equal_approx(comp.get_current(AttributeComponent.STAT_MAX_HEALTH), base_max):
		return fail("Max stat should return to base after removal.")
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), base_max):
		return fail("Removing a max gain must re-clamp an over-full pool to max.")
	comp.apply_modifier(AttributeComponent.STAT_MAX_HEALTH, &"test_max_gain", Attribute.Op.ADD, gain)
	comp.damage_pool(AttributeComponent.POOL_HEALTH, gain + 10.0)
	var wounded: float = comp.get_current(AttributeComponent.POOL_HEALTH)
	if not comp.remove_modifier(AttributeComponent.STAT_MAX_HEALTH, &"test_max_gain"):
		return fail("Permanent max buff should be removable when wounded.")
	if not is_equal_approx(comp.get_current(AttributeComponent.POOL_HEALTH), wounded):
		return fail("Removing a max gain must preserve wounds below the new max.")
	print("Permanent max gains carry current HP; timed gains and removals behave.")
	return true


## PART 17: effects with vfx_bone attach to a BoneAttachment3D under the
## character's Skeleton3D so the visual follows the bone through animations
## and collapses to the floor with the corpse upon defeat.
func test_effect_vfx_bone_attachment() -> bool:
	print("\n>>> PART 17: Bone-attached status visuals follow corpse on defeat")
	_add_floor()
	var enemy: Character = spawn(load("res://Enemy/melee_enemy.tscn") as PackedScene) as Character
	await get_tree().physics_frame
	await get_tree().physics_frame

	var comp: AttributeComponent = enemy.get_node_or_null("AttributeComponent") as AttributeComponent
	if comp == null:
		return fail("Melee enemy must have an AttributeComponent.")
	var burn: GameplayEffect = load("res://Components/effect_fire_burn.tres") as GameplayEffect
	if burn == null or burn.vfx_scene == null or burn.vfx_bone != &"spine":
		return fail("effect_fire_burn.tres should configure vfx_scene and vfx_bone = &\"spine\".")
	if comp.apply_effect(burn) == &"":
		return fail("Burn application should return a valid instance id.")
	await get_tree().physics_frame
	await get_tree().physics_frame

	var spine_slot: BoneAttachment3D = _find_bone_slot(enemy, "spine")
	if spine_slot == null:
		return fail("Status visual should create or find a BoneAttachment3D for spine.")
	var burn_fx: Node3D = spine_slot.get_node_or_null("StatusBurning") as Node3D
	if burn_fx == null:
		return fail("Status burning visual should be parented under SpineSlot.")
	var initial_fx_y: float = burn_fx.global_position.y
	if initial_fx_y < 0.4:
		return fail("Initial spine visual should be around torso height (>= 0.4), got %f." % initial_fx_y)

	# Trigger defeat and wait for the defeat animation to collapse the skeleton to the floor
	enemy.on_defeat()
	await wait_until(func() -> bool: return burn_fx.global_position.y < initial_fx_y - 0.25, "the corpse should collapse")
	var defeated_fx_y: float = burn_fx.global_position.y
	if defeated_fx_y >= initial_fx_y - 0.25:
		return fail("Status visual should fall with the spine bone on defeat; initial=%f, defeated=%f." % [initial_fx_y, defeated_fx_y])

	comp.clear_temporary_effects()
	await get_tree().physics_frame
	if is_instance_valid(burn_fx):
		return fail("Visual should be freed when effect is cleared.")
	print("Bone-attached status visual followed corpse on defeat and freed on cleanup.")
	return true
