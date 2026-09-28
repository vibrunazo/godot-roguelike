## Akira boss:
## - Registered as an enemy; minimum_spawn_difficulty keeps it out of regular
##   waves below that difficulty (boss arenas spawn it directly).
## - Its capsule rests on the floor.
## - Throws firebombs that leave fire traps built from that bomb's settings.
## - Its backpack riders side-slash a player in their zone with the fire slash
##   VFX, then can swing again once their own cooldown has passed.
## - With full fire resistance it ignores fire (no damage, reaction, stun or
##   burn) but not physical hits; burns apply once resistance is lowered; a
##   live fire trap harms a normal enemy next to it but not the boss.
## - Hits during an ability interrupt it only when the ability is
##   interruptable; stun cancels follow each mind state's can_break_stun.
## - The has_riders tag gates throwing riders versus summoning helpers;
##   throwing detaches the riders and spawns a minion per rider, summoning
##   spawns ground minions and restores the riders.
## Tunable values (difficulties, sizes, resistances, cooldowns, damage) are
## never asserted, not even relative to other enemies: tests either read them
## from the live nodes or set their own. Art (meshes, colors, VFX assets,
## sounds) is verified visually with capture.py, not here.
extends "res://test/lib/test_suite.gd"

const BOSS_SCENE: PackedScene = preload("res://Enemy/akira_boss.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const FIRE_TRAP_SCENE: PackedScene = preload("res://Hazards/fire_trap.tscn")
const BURN_EFFECT: GameplayEffect = preload("res://Components/effect_fire_burn.tres")
const RIDERS_TAG: StringName = &"has_riders"
## The boss carries one rider on each side.
const RIDER_COUNT: int = 2
## Test-owned values.
const TEST_DAMAGE: float = 10.0
const THROW_DISTANCE: float = 6.0
const TEST_ABILITY_DELAY: float = 0.05
const TEST_TRAP_SIZE: Vector2 = Vector2(4.0, 2.0)
const TEST_TRAP_INTERVAL: float = 0.1
## Test-owned fire resistances (1.0 = immune, 0.0 = none) and spawn gate.
const IMMUNE: float = 1.0
const VULNERABLE: float = 0.0
const TEST_GATE_OFFSET: int = 5
## Generous budget for ability flights, landings and AI decisions.
const LONG_FRAMES: int = 900
## Test-owned health for the test player, so boss attacks never end the run
## (a defeated player opens the game-over screen, which pauses the tree).
const PLAYER_HEALTH: float = 100000.0

var _arena: Node3D
var _floor_top: float


func before_each() -> void:
	_arena = load_arena()
	_floor_top = arena_floor_top(_arena)


func after_each() -> void:
	UI.resume_game()


# --- Registration and body -----------------------------------------------------

func test_boss_is_registered_and_gated_by_its_minimum_spawn_difficulty() -> void:
	var registered: EnemyResource = GlobalVars.get_enemy_resource(BOSS_SCENE)
	if not check(registered != null, "GlobalVars.enemies should register the boss"):
		return
	var boss: Character = autofree(registered.scene.instantiate()) as Character
	check(boss.is_enemy(), "the registered boss scene should be an enemy")
	# Gate a copy of the boss's resource with a test-owned minimum difficulty,
	# so the check covers the gating, not how the boss happens to be tuned.
	var gated: EnemyResource = registered.duplicate() as EnemyResource
	gated.minimum_spawn_difficulty = gated.difficulty_level + TEST_GATE_OFFSET
	var resources: Array[EnemyResource] = [gated]
	var tier: int = gated.difficulty_level
	check((ProgressionState.build_difficulty_pool(resources).get(tier, []) as Array).has(gated), "ungated, the pool should offer the boss at its difficulty")
	check(not (ProgressionState.build_difficulty_pool(resources, gated.minimum_spawn_difficulty - 1).get(tier, []) as Array).has(gated), "below its minimum difficulty the boss must not appear in regular waves")
	check((ProgressionState.build_difficulty_pool(resources, gated.minimum_spawn_difficulty).get(tier, []) as Array).has(gated), "at its minimum difficulty the boss should join regular waves")


func test_boss_rests_on_the_floor() -> void:
	var boss: Character = _spawn_still(BOSS_SCENE, Vector3(0.0, _floor_top + 3.0, 0.0))
	if not await wait_until(func() -> bool: return boss.is_on_floor(), "the boss should land", LONG_FRAMES):
		return
	await wait_physics_frames(5)
	var capsule: CapsuleShape3D = boss.collision_shape_3d.shape as CapsuleShape3D
	var rest_height: float = _floor_top + capsule.height * 0.5 - boss.collision_shape_3d.position.y
	check_approx(boss.global_position.y, rest_height, "the boss's capsule should rest on the floor (no float, no sink)", 0.08)


# --- Firebombs -----------------------------------------------------------------

func test_boss_firebombs_leave_fire_traps_built_from_the_bomb() -> void:
	var boss: Character = await _settled_boss()
	# Aim at a bare floor point: a bomb that hits a character in flight leaves
	# no fire trap by design.
	var target: Marker3D = autofree(Marker3D.new()) as Marker3D
	target.position = Vector3(boss.global_position.x, _floor_top, boss.global_position.z + THROW_DISTANCE)
	_arena.add_child(target)
	boss.current_target = target
	(boss.get_node("ProjectileSpawnerComponent") as ProjectileSpawnerComponent).spawn_projectile()
	var bomb: FirebombProjectile = null
	for child: Node in get_children():
		if child is FirebombProjectile:
			bomb = child as FirebombProjectile
	if not check(bomb != null, "the boss should throw a firebomb"):
		return
	var size: Vector2 = bomb.trap_size
	var damage: float = bomb.trap_damage
	if not await wait_until(func() -> bool: return not _nodes_of(FireTrap).is_empty(), "the boss's firebomb should land and leave a fire trap", LONG_FRAMES):
		return
	var trap: FireTrap = _nodes_of(FireTrap)[0] as FireTrap
	check_eq(trap.trap_size, size, "the fire trap should take the boss bomb's trap_size")
	check_approx(trap.damage, damage, "the fire trap should take the boss bomb's trap_damage")


# --- Riders --------------------------------------------------------------------

func test_riders_slash_a_player_in_their_zone_and_swing_again_after_cooldown() -> void:
	var boss: Character = await _settled_boss()
	var riders: AkiraBossRiders = boss.get_node("RiderController") as AkiraBossRiders
	var slot: WeaponSlot = riders.left_rider_root.find_child("WeaponSlot", true, false) as WeaponSlot
	var zone: CollisionShape3D = slot.hitbox.find_child("CollisionShape3D", true, false) as CollisionShape3D
	var player: Character = await _grounded_player(Vector3(zone.global_position.x, _floor_top + 1.0, zone.global_position.z))
	player.knockback_component.max_knockback = 0.0
	var vfx: MeshInstance3D = slot.find_child("SlashVFX", true, false) as MeshInstance3D
	var vfx_seen: Array[bool] = [false]
	var min_threshold: Array[float] = [1.0]
	var watch_vfx: Callable = func() -> void:
		if vfx != null and slot.enabled and vfx.visible:
			vfx_seen[0] = true
			var material: ShaderMaterial = vfx.material_override as ShaderMaterial
			if material != null:
				min_threshold[0] = minf(min_threshold[0], float(material.get_shader_parameter("Threshold")))
	get_tree().physics_frame.connect(watch_vfx)
	riders.force_rider_attack(true)
	check(not riders.is_rider_ready(true), "a swing should start the rider's cooldown")
	var first_hit: bool = await wait_signal(player.hurtbox.struck, "the rider's side-slash should hit a player in its zone", LONG_FRAMES)
	# The rider controller swings on its own at a player in range once its
	# cooldown has passed, so a second hit must follow within one swing plus
	# one cooldown (stale hit exceptions would block it).
	var second_hit: bool = false
	if first_hit:
		second_hit = await wait_signal(player.hurtbox.struck, "the rider should hit again after its cooldown (no stale hit exceptions)", _frames_for(AkiraBossRiders.SLASH_LENGTH + riders.attack_cooldown))
	get_tree().physics_frame.disconnect(watch_vfx)
	if vfx != null:
		check(vfx_seen[0], "the fire slash VFX should show during the swing")
		check(min_threshold[0] < 1.0, "the fire slash VFX should sweep during the swing")


# --- Fire immunity -------------------------------------------------------------

func test_full_fire_resistance_ignores_fire_hits_but_not_physical_hits() -> void:
	var boss: Character = await _settled_boss()
	var attributes: AttributeComponent = boss.attribute_component
	attributes.set_base(AttributeComponent.STAT_FIRE_RESISTANCE, IMMUNE)
	var strikes: Array[int] = [0]
	boss.hurtbox.struck.connect(func(_damage: float) -> void: strikes[0] += 1)
	var health_before: float = _health(boss)
	check(not boss.hurtbox.receive_hit(TEST_DAMAGE, Vector3.ZERO, &"fire"), "a fire hit should be rejected")
	check_approx(_health(boss), health_before, "a fire hit must not damage the boss")
	check_eq(strikes[0], 0, "a fire hit must not trigger a hit reaction")
	check(boss.state_machine.state != boss.stun_state, "a fire hit must not stun the boss")
	check(boss.hurtbox.receive_hit(TEST_DAMAGE, Vector3.ZERO, &"physical"), "a physical hit should land")
	check_approx(health_before - _health(boss), TEST_DAMAGE * attributes.get_damage_multiplier(&"physical"), "a physical hit should deal its damage")
	check_eq(strikes[0], 1, "a physical hit should trigger exactly one hit reaction")


func test_burns_are_rejected_until_fire_resistance_is_lowered() -> void:
	var boss: Character = await _settled_boss()
	var attributes: AttributeComponent = boss.attribute_component
	attributes.set_base(AttributeComponent.STAT_FIRE_RESISTANCE, IMMUNE)
	check_eq(attributes.apply_effect(BURN_EFFECT), &"", "a burn should be rejected while the boss is immune")
	attributes.set_base(AttributeComponent.STAT_FIRE_RESISTANCE, VULNERABLE)
	if not check(attributes.apply_effect(BURN_EFFECT) != &"", "a burn should apply once fire resistance is lowered"):
		return
	var health_before: float = _health(boss)
	await wait_until(func() -> bool: return _health(boss) < health_before, "the accepted burn should tick damage", LONG_FRAMES)


func test_a_live_fire_trap_harms_a_vulnerable_enemy_but_not_an_immune_boss() -> void:
	var boss: Character = await _settled_boss()
	boss.attribute_component.set_base(AttributeComponent.STAT_FIRE_RESISTANCE, IMMUNE)
	# Place the control just clear of the boss's capsule: overlapping spawns
	# shove the boss into a fall and a landing stun, which is not a fire reaction.
	var control_instance: Character = autofree(MELEE_SCENE.instantiate()) as Character
	var gap: float = _radius(boss) + float((control_instance.get_node("CollisionShape3D") as CollisionShape3D).shape.get("radius")) + 0.5
	control_instance.free()
	var control: Character = _spawn_still(MELEE_SCENE, boss.global_position + Vector3(gap, 0.0, 0.0))
	control.attribute_component.set_base(AttributeComponent.STAT_FIRE_RESISTANCE, VULNERABLE)
	await wait_until(func() -> bool: return control.is_on_floor() and boss.state_machine.state == boss.state_machine.initial_state, "the control enemy should land and the boss stay settled")
	var strikes: Array[int] = [0]
	boss.hurtbox.struck.connect(func(_damage: float) -> void: strikes[0] += 1)
	var boss_health: float = _health(boss)
	var control_health: float = _health(control)
	var trap: FireTrap = FIRE_TRAP_SCENE.instantiate() as FireTrap
	trap.position = Vector3(boss.global_position.x + gap * 0.5, _floor_top, boss.global_position.z)
	autofree(trap)
	_arena.add_child(trap)
	trap.set_trap_size(Vector2(gap + TEST_TRAP_SIZE.x, TEST_TRAP_SIZE.y))
	trap.damage_interval = TEST_TRAP_INTERVAL
	var stunned: Array[bool] = [false]
	await wait_until(func() -> bool:
		stunned[0] = stunned[0] or boss.state_machine.state == boss.stun_state
		return _health(control) < control_health, "the fire trap should burn the normal enemy next to the boss", LONG_FRAMES)
	check_approx(_health(boss), boss_health, "the fire trap must not damage the boss")
	check_eq(strikes[0], 0, "the fire trap must not trigger hit reactions on the boss")
	check(not stunned[0], "the fire trap must not stun the boss")


# --- Abilities -----------------------------------------------------------------

func test_hits_interrupt_boss_abilities_only_when_interruptable() -> void:
	var boss: Character = await _settled_boss()
	for ability_name: String in ["EnemyAttack", "EnemyPunch", "EnemyFirebomb"]:
		var ability: CharacterAttack = boss.state_machine.get_node(ability_name) as CharacterAttack
		boss.state_machine.request_state(ability_name)
		await wait_physics_frames(2)
		if not check(boss.state_machine.state == ability, "setup: the boss should enter %s" % ability_name):
			continue
		var health_before: float = _health(boss)
		check(boss.hurtbox.receive_hit(TEST_DAMAGE, Vector3.ZERO), "a hit during %s should land" % ability_name)
		check_approx(health_before - _health(boss), TEST_DAMAGE, "a hit during %s should deal its damage" % ability_name)
		if ability.uninterruptable:
			check(boss.state_machine.state == ability, "an uninterruptable %s must not be stunned out" % ability_name)
		else:
			check(boss.state_machine.state == boss.stun_state, "an interruptable %s should be stunned out" % ability_name)
		boss.state_machine.request_state(str(boss.state_machine.initial_state.name))


func test_stun_cancels_follow_each_mind_states_can_break_stun() -> void:
	var boss: Character = await _settled_boss()
	var mind: AIStateMachine = boss.ai_state_machine
	var orders: Dictionary[String, bool] = {
		"EnemyAttack": (mind.get_node("AISlam") as AIConditionalAttack).can_break_stun,
		"EnemyPunch": (mind.get_node("AIPursue") as AIPursue).can_break_stun,
		"EnemyFirebomb": (mind.get_node("AIFirebomb") as AIConditionalAttack).can_break_stun,
	}
	for ability_name: String in orders:
		boss.state_machine.request_state(str(boss.stun_state.name))
		var may_break: bool = orders[ability_name]
		check_eq(mind.order_attack(ability_name, may_break), may_break, "ordering %s from a stun should succeed exactly when its mind state may break stun" % ability_name)
		var expected: State = boss.state_machine.get_node(ability_name) as State if may_break else boss.stun_state
		check(boss.state_machine.state == expected, "after the %s order the boss should be in %s" % [ability_name, expected.name])
		boss.state_machine.request_state(str(boss.state_machine.initial_state.name))


func test_a_stunned_boss_breaks_out_into_an_ability_on_its_own() -> void:
	var boss: Character = _spawn(BOSS_SCENE, Vector3(0.0, _floor_top + 3.0, 0.0))
	var mind: AIStateMachine = boss.ai_state_machine
	var breakers: Array[String] = []
	if (mind.get_node("AISlam") as AIConditionalAttack).can_break_stun:
		breakers.append("EnemyAttack")
	if (mind.get_node("AIPursue") as AIPursue).can_break_stun:
		breakers.append("EnemyPunch")
	if (mind.get_node("AIFirebomb") as AIConditionalAttack).can_break_stun:
		breakers.append("EnemyFirebomb")
	if breakers.is_empty():
		return
	await _grounded_player(Vector3(2.0, _floor_top + 1.0, 0.0))
	if not await wait_until(func() -> bool: return boss.is_on_floor() and boss.state_machine.state == boss.state_machine.initial_state, "the boss should land and settle", LONG_FRAMES):
		return
	var stun_name: String = str(boss.stun_state.name)
	boss.state_machine.request_state(stun_name)
	await wait_until(func() -> bool:
		var now: String = str(boss.state_machine.state.name)
		if breakers.has(now):
			return true
		if now != stun_name:
			# The stun ran out before an order landed: stun again, so the ability
			# observed has to break out of a live stun.
			boss.state_machine.request_state(stun_name)
		return false, "a stunned boss with a player in range should break out into an ability", LONG_FRAMES)


# --- Riders tag, throw and summon ----------------------------------------------

func test_riders_tag_gates_throwing_versus_summoning() -> void:
	var boss: Character = await _settled_boss()
	var attributes: AttributeComponent = boss.attribute_component
	check(boss.has_tag(RIDERS_TAG), "the boss should start with its riders")
	var required: Array[StringName] = [RIDERS_TAG]
	var any: Array[StringName] = [RIDERS_TAG, &"test_missing_tag"]
	check(boss.has_all_tags(required) and boss.has_any_tag(any), "tag queries should see the riders tag")
	var events: Array[StringName] = [&"", &""]
	attributes.tag_added.connect(func(tag: StringName) -> void: events[0] = tag)
	attributes.tag_removed.connect(func(tag: StringName) -> void: events[1] = tag)
	attributes.add_tag(&"test_tag")
	check_eq(events[0], &"test_tag", "adding a tag should emit tag_added")
	attributes.remove_tag(&"test_tag")
	check_eq(events[1], &"test_tag", "removing a tag should emit tag_removed")
	var throw: CharacterAttack = boss.state_machine.get_node("EnemyThrowRiders") as CharacterAttack
	var summon: CharacterAttack = boss.state_machine.get_node("EnemySummonHelpers") as CharacterAttack
	throw.cooldown_timer = 0.0
	summon.cooldown_timer = 0.0
	check(throw.can_activate() and not summon.can_activate(), "with riders the boss may throw them but not summon helpers")
	attributes.remove_tag(RIDERS_TAG)
	await wait_physics_frames(1)
	check(not throw.can_activate(), "without riders the boss must not throw them")
	if summon.start_cooldown_on_enabled:
		check(summon.cooldown_timer > 0.0, "summoning should start its cooldown when it becomes available")
	summon.cooldown_timer = 0.0
	check(summon.can_activate(), "without riders and off cooldown the boss may summon helpers")
	attributes.add_tag(RIDERS_TAG)
	check(throw.can_activate() and not summon.can_activate(), "regaining riders should re-enable throwing and block summoning")


func test_throwing_riders_detaches_them_and_spawns_a_minion_per_rider() -> void:
	var boss: Character = await _settled_boss()
	var riders: AkiraBossRiders = boss.get_node("RiderController") as AkiraBossRiders
	var player: Character = await _grounded_player(boss.global_position + Vector3(0.0, 0.0, THROW_DISTANCE))
	boss.current_target = player
	var throw: AkiraBossThrowRidersAttack = boss.state_machine.get_node("EnemyThrowRiders") as AkiraBossThrowRidersAttack
	throw.cooldown_timer = 0.0
	throw.throw_delay = TEST_ABILITY_DELAY
	boss.state_machine.request_state("EnemyThrowRiders")
	if not await wait_until(func() -> bool: return not riders.has_riders(), "throwing should detach the riders", LONG_FRAMES):
		return
	check(not boss.has_tag(RIDERS_TAG), "throwing should remove the riders tag")
	check(not riders.left_rider_root.visible and not riders.right_rider_root.visible, "thrown riders should no longer show on the boss")
	await wait_until(func() -> bool: return _minions(boss).size() >= RIDER_COUNT, "each thrown rider should land as a minion", LONG_FRAMES)


func test_summoning_helpers_spawns_minions_and_restores_the_riders() -> void:
	var boss: Character = await _settled_boss()
	var riders: AkiraBossRiders = boss.get_node("RiderController") as AkiraBossRiders
	riders.detach_riders()
	boss.attribute_component.remove_effect(RIDERS_TAG)
	boss.attribute_component.remove_tag(RIDERS_TAG)
	await wait_physics_frames(1)
	if not check(not riders.has_riders() and not boss.has_tag(RIDERS_TAG), "setup: the boss should have no riders"):
		return
	var summon: AkiraBossSummonHelpersAttack = boss.state_machine.get_node("EnemySummonHelpers") as AkiraBossSummonHelpersAttack
	summon.cooldown_timer = 0.0
	summon.summon_delay = TEST_ABILITY_DELAY
	boss.state_machine.request_state("EnemySummonHelpers")
	if not await wait_until(func() -> bool: return riders.has_riders() and _minions(boss).size() >= RIDER_COUNT, "summoning should spawn ground minions and restore the riders", LONG_FRAMES):
		return
	check(boss.has_tag(RIDERS_TAG), "restored riders should bring back the riders tag")
	check(riders.left_rider_root.visible and riders.right_rider_root.visible, "restored riders should show on the boss again")


# --- helpers -------------------------------------------------------------------

func _spawn(scene: PackedScene, at: Vector3) -> Character:
	return spawn(scene, _arena, at) as Character


## A character with its AI stopped, so only the test drives it.
func _spawn_still(scene: PackedScene, at: Vector3) -> Character:
	var character: Character = _spawn(scene, at)
	disable_ai(character)
	return character


## A boss standing at the arena centre with its AI stopped.
func _settled_boss() -> Character:
	var boss: Character = _spawn_still(BOSS_SCENE, Vector3(0.0, _floor_top + 3.0, 0.0))
	await wait_until(func() -> bool: return boss.is_on_floor() and boss.state_machine.state == boss.state_machine.initial_state, "the boss should land and settle", LONG_FRAMES)
	return boss


## A player standing at the given point with live input off and test-owned
## health high enough to survive the boss.
func _grounded_player(at: Vector3) -> Character:
	var player: Character = _spawn(PLAYER_SCENE, at)
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, PLAYER_HEALTH)
	await wait_until(func() -> bool: return player.is_on_floor(), "the player should land")
	return player


## Living enemies other than the boss (thrown riders and summoned helpers).
func _minions(boss: Character) -> Array[Character]:
	var found: Array[Character] = []
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if node != boss and node is Character and (node as Character).is_alive():
			found.append(node as Character)
	return found


## Nodes of a class spawned into the world (game code parents them to the suite).
func _nodes_of(type: Variant) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in get_children():
		if is_instance_of(child, type) and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _radius(character: Character) -> float:
	return float(character.collision_shape_3d.shape.get("radius"))


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Physics frames covering the given game time, plus a small margin.
func _frames_for(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 5
