## Backpack bosses: every registered enemy carrying backpack riders (a
## BackpackRiders component), whatever its riders are:
## - its riders start aboard, and the rider tag alone decides whether they
##   show and fight: unboarding takes the tag away and hides them, boarding
##   gives it back and shows them,
## - the rider tag gates throwing the riders (needs them aboard) versus
##   summoning them (needs them gone), and the summon's cooldown starts when
##   it becomes available,
## - throwing sends every rider off, and each lands as an enemy of its own
##   kind (the enemy its lob carries),
## - no order can cut a throw or a summon short before it releases (the
##   riders leave, the lobs drop); afterwards the boss takes orders again,
## - a rider's lob hurts a player where it lands,
## - summoning drops helpers of each rider's kind beside the boss and boards
##   the riders again.
## Delays, damage and counts are set by the test or read from the live nodes.
## Each test runs on every backpack boss in turn, so a new one is covered as
## soon as it is registered.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned values.
const TEST_DAMAGE: float = 10.0
const TEST_RADIUS: float = 2.5
const THROW_DISTANCE: float = 6.0
const TEST_ABILITY_DELAY: float = 0.05
## A release delay long enough to try an order before it.
const TEST_COMMIT_DELAY: float = 0.3
## Generous budget for ability flights, landings and settling.
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


func test_riders_board_and_leave_with_the_rider_tag() -> void:
	for scene: PackedScene in _backpack_boss_scenes():
		var world_before: Array[Node] = get_children()
		var boss: Character = await _settled_boss(scene)
		var backpack: BackpackRiders = _backpack(boss)
		var label: String = scene.resource_path.get_file()
		check(backpack.has_riders() and boss.has_tag(backpack.rider_tag), "%s should start with its riders aboard" % label)
		check(_riders_aboard(backpack, true), "%s's riders should start aboard and shown" % label)
		backpack.unboard_riders()
		check(not boss.has_tag(backpack.rider_tag), "unboarding should take the rider tag from %s" % label)
		check(_riders_aboard(backpack, false), "%s's riders should be gone and hidden once unboarded" % label)
		backpack.board_riders()
		check(boss.has_tag(backpack.rider_tag), "boarding should give %s the rider tag back" % label)
		check(_riders_aboard(backpack, true), "%s's riders should be aboard and shown again" % label)
		await _clear_world(world_before, [boss])


func test_the_rider_tag_gates_throwing_versus_summoning() -> void:
	for scene: PackedScene in _backpack_boss_scenes():
		var world_before: Array[Node] = get_children()
		var boss: Character = await _settled_boss(scene)
		var backpack: BackpackRiders = _backpack(boss)
		var attributes: AttributeComponent = boss.attribute_component
		var label: String = scene.resource_path.get_file()
		var tag: StringName = backpack.rider_tag
		var required: Array[StringName] = [tag]
		var any: Array[StringName] = [tag, &"test_missing_tag"]
		check(boss.has_all_tags(required) and boss.has_any_tag(any), "tag queries on %s should see the rider tag" % label)
		var events: Array[StringName] = [&"", &""]
		attributes.tag_added.connect(func(added: StringName) -> void: events[0] = added)
		attributes.tag_removed.connect(func(removed: StringName) -> void: events[1] = removed)
		attributes.add_tag(&"test_tag")
		check_eq(events[0], &"test_tag", "adding a tag should emit tag_added")
		attributes.remove_tag(&"test_tag")
		check_eq(events[1], &"test_tag", "removing a tag should emit tag_removed")
		var throw: ThrowRidersAttack = _state_of(boss, "ThrowRidersAttack") as ThrowRidersAttack
		var summon: SummonRidersAttack = _state_of(boss, "SummonRidersAttack") as SummonRidersAttack
		if not check(throw != null and summon != null, "%s should have a throw and a summon attack" % label):
			continue
		throw.cooldown_timer = 0.0
		summon.cooldown_timer = 0.0
		check(throw.can_activate() and not summon.can_activate(), "with riders aboard %s may throw them but not summon" % label)
		backpack.unboard_riders()
		await wait_physics_frames(1)
		check(not throw.can_activate(), "without riders %s must not throw them" % label)
		if summon.start_cooldown_on_enabled:
			check(summon.cooldown_timer > 0.0, "%s's summon should start its cooldown when it becomes available" % label)
		summon.cooldown_timer = 0.0
		check(summon.can_activate(), "without riders and off cooldown %s may summon" % label)
		backpack.board_riders()
		check(throw.can_activate() and not summon.can_activate(), "boarding should re-enable throwing and block summoning on %s" % label)
		await _clear_world(world_before, [boss])


func test_throwing_sends_each_rider_off_to_land_as_an_enemy_of_its_kind() -> void:
	for scene: PackedScene in _backpack_boss_scenes():
		var world_before: Array[Node] = get_children()
		var boss: Character = await _settled_boss(scene)
		var backpack: BackpackRiders = _backpack(boss)
		var label: String = scene.resource_path.get_file()
		_hold_rider_attacks(boss)
		var player: Character = await _grounded_player(boss.global_position + Vector3(0.0, 0.0, THROW_DISTANCE))
		boss.current_target = player
		var throw: ThrowRidersAttack = _state_of(boss, "ThrowRidersAttack") as ThrowRidersAttack
		throw.cooldown_timer = 0.0
		throw.throw_delay = TEST_ABILITY_DELAY
		var kinds: Array[String] = _rider_kinds(backpack)
		boss.state_machine.request_state(throw.name)
		if await wait_until(func() -> bool: return not backpack.has_riders(), "%s should send its riders off" % label, LONG_FRAMES):
			check(_riders_aboard(backpack, false), "thrown riders should no longer show on %s" % label)
			if await wait_until(func() -> bool: return _minions(boss).size() >= kinds.size(), "each rider %s throws should land as an enemy" % label, LONG_FRAMES):
				check_eq(_minion_kinds(boss), _sorted(kinds), "%s's riders should land as enemies of their own kinds" % label)
		await _clear_world(world_before, [boss, player])


func test_throwing_and_summoning_take_no_orders_until_they_release() -> void:
	for scene: PackedScene in _backpack_boss_scenes():
		var world_before: Array[Node] = get_children()
		var boss: Character = await _settled_boss(scene)
		var backpack: BackpackRiders = _backpack(boss)
		var label: String = scene.resource_path.get_file()
		_hold_rider_attacks(boss)
		var player: Character = await _grounded_player(boss.global_position + Vector3(0.0, 0.0, THROW_DISTANCE))
		boss.current_target = player
		var other: CharacterState = boss.state_machine.initial_state as CharacterState
		var throw: ThrowRidersAttack = _state_of(boss, "ThrowRidersAttack") as ThrowRidersAttack
		throw.throw_delay = TEST_COMMIT_DELAY
		boss.state_machine.request_state(throw.name)
		check(not boss.can_accept_order(other), "an order must not cut %s's throw short before the riders leave" % label)
		if await wait_until(func() -> bool: return not backpack.has_riders(), "%s should throw its riders" % label, LONG_FRAMES):
			check(boss.state_machine.state != throw or boss.can_accept_order(other), "once the riders are thrown %s should take orders again" % label)
		boss.state_machine.request_state(other.name)
		var summon: SummonRidersAttack = _state_of(boss, "SummonRidersAttack") as SummonRidersAttack
		summon.summon_delay = TEST_COMMIT_DELAY
		boss.state_machine.request_state(summon.name)
		check(not boss.can_accept_order(other), "an order must not cut %s's summon short before the lobs drop" % label)
		if await wait_until(func() -> bool: return summon.accepts_orders() or boss.state_machine.state != summon, "%s's summon should drop its lobs" % label, LONG_FRAMES):
			check(boss.state_machine.state != summon or boss.can_accept_order(other), "once the lobs drop %s should take orders again" % label)
		await _clear_world(world_before, [boss, player])


func test_a_riders_lob_hurts_a_player_where_it_lands() -> void:
	for scene: PackedScene in _backpack_boss_scenes():
		var world_before: Array[Node] = get_children()
		var boss: Character = await _settled_boss(scene)
		var label: String = scene.resource_path.get_file()
		_hold_rider_attacks(boss)
		var player: Character = await _grounded_player(boss.global_position + Vector3(0.0, 0.0, THROW_DISTANCE))
		# One lob on its own, landing on the player with test-owned damage and
		# no enemy, so only the landing blast can hurt the player.
		var rider: BackpackRider = _backpack(boss).riders[0]
		var before: float = _health(player)
		rider.launch(boss.global_position + Vector3.UP * 2.0, player.get_feet_position(), false, TEST_DAMAGE, TEST_RADIUS, 0.0)
		await wait_until(func() -> bool: return _health(player) < before, "a lob of %s's rider should hurt the player it lands on" % label, LONG_FRAMES)
		await _clear_world(world_before, [boss, player])


func test_summoning_drops_helpers_of_each_riders_kind_and_boards_the_riders() -> void:
	for scene: PackedScene in _backpack_boss_scenes():
		var world_before: Array[Node] = get_children()
		var boss: Character = await _settled_boss(scene)
		var backpack: BackpackRiders = _backpack(boss)
		var label: String = scene.resource_path.get_file()
		_hold_rider_attacks(boss)
		backpack.unboard_riders()
		await wait_physics_frames(1)
		if not check(not backpack.has_riders(), "setup: %s should have no riders" % label):
			await _clear_world(world_before, [boss])
			continue
		var summon: SummonRidersAttack = _state_of(boss, "SummonRidersAttack") as SummonRidersAttack
		summon.cooldown_timer = 0.0
		summon.summon_delay = TEST_ABILITY_DELAY
		var kinds: Array[String] = []
		for kind: String in _rider_kinds(backpack):
			for helper: int in summon.helpers_per_rider:
				kinds.append(kind)
		boss.state_machine.request_state(summon.name)
		if await wait_until(func() -> bool: return backpack.has_riders() and _minions(boss).size() >= kinds.size(), "%s's summon should drop its helpers and board its riders" % label, LONG_FRAMES):
			check(_riders_aboard(backpack, true), "summoned riders should show on %s again" % label)
			check_eq(_minion_kinds(boss), _sorted(kinds), "%s should summon helpers of each rider's kind" % label)
		await _clear_world(world_before, [boss])


# --- helpers -------------------------------------------------------------------

## The scenes of every registered enemy that carries backpack riders.
func _backpack_boss_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	for resource: EnemyResource in GlobalVars.enemies:
		if resource == null or resource.scene == null:
			continue
		var probe: Node = resource.scene.instantiate()
		if not probe.find_children("*", "BackpackRiders", true, false).is_empty():
			scenes.append(resource.scene)
		probe.free()
	check(not scenes.is_empty(), "setup: GlobalVars.enemies should register a backpack boss")
	return scenes


## A boss of scene standing at the arena centre with its AI stopped.
func _settled_boss(scene: PackedScene) -> Character:
	var boss: Character = spawn(scene, _arena, Vector3(0.0, _floor_top + 3.0, 0.0)) as Character
	disable_ai(boss)
	await wait_until(func() -> bool: return boss.is_on_floor() and boss.state_machine.state == boss.state_machine.initial_state, "%s should land and settle" % scene.resource_path.get_file(), LONG_FRAMES)
	return boss


## Stops the boss's riders attacking on their own (they still board, leave
## and fly), so only the mechanism under test touches the player.
func _hold_rider_attacks(boss: Character) -> void:
	_backpack(boss).process_mode = Node.PROCESS_MODE_DISABLED


func _backpack(boss: Character) -> BackpackRiders:
	return boss.find_children("*", "BackpackRiders", true, false)[0] as BackpackRiders


## The boss's body state of the given class (e.g. "ThrowRidersAttack"), or null.
func _state_of(boss: Character, type: String) -> CharacterState:
	var found: Array[Node] = boss.state_machine.find_children("*", type, false, false)
	return found[0] as CharacterState if not found.is_empty() else null


## Whether every rider is aboard and shown (aboard true) or gone and hidden.
func _riders_aboard(backpack: BackpackRiders, aboard: bool) -> bool:
	for rider: BackpackRider in backpack.riders:
		if rider.is_aboard() != aboard or rider.body.visible != aboard:
			return false
	return true


## The scene path of the enemy each rider becomes (the enemy its lob carries).
func _rider_kinds(backpack: BackpackRiders) -> Array[String]:
	var kinds: Array[String] = []
	for rider: BackpackRider in backpack.riders:
		var lob: LobbedSpawnProjectile = rider.lob_scene.instantiate() as LobbedSpawnProjectile
		kinds.append(lob.enemy_scene.resource_path)
		lob.free()
	return kinds


## Living enemies other than the boss (thrown riders and summoned helpers).
func _minions(boss: Character) -> Array[Character]:
	var found: Array[Character] = []
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if node != boss and node is Character and (node as Character).is_alive():
			found.append(node as Character)
	return found


## The sorted scene paths of the living minions.
func _minion_kinds(boss: Character) -> Array[String]:
	var kinds: Array[String] = []
	for minion: Character in _minions(boss):
		kinds.append(minion.scene_file_path)
	return _sorted(kinds)


func _sorted(paths: Array[String]) -> Array[String]:
	var sorted: Array[String] = paths.duplicate()
	sorted.sort()
	return sorted


## A player standing at the given point with live input off and test-owned
## health high enough to survive the boss.
func _grounded_player(at: Vector3) -> Character:
	var player: Character = spawn(PLAYER_SCENE, _arena, at) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, PLAYER_HEALTH)
	await wait_until(func() -> bool: return player.is_on_floor(), "the player should land")
	return player


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Frees the given nodes and everything game code added to the world since
## world_before (minions, lobs, projectiles), so the next boss starts in an
## empty arena.
func _clear_world(world_before: Array[Node], nodes: Array[Node]) -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	for child: Node in get_children():
		if not world_before.has(child):
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
