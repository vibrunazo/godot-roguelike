## Characters, teams, and the enemy AI (mind) driving the body:
## - Player and enemies are Characters on opposite teams; nearest-target
##   resolution picks the closest living opponent.
## - Player input (by action name) sets the player's movement intent.
## - The AI mind commands the body; a hit stuns the body, and the mind cannot
##   attack until the body recovers; defeated characters stop acting entirely;
##   a falling body takes no orders, and an order never restarts the attack
##   the body is already running; an attack order the stunned body refuses
##   costs no cooldown, so the enemy attacks once the stun ends.
## - alert() wakes an idle mind (waiting or meandering) into combat and leaves
##   an engaged mind alone.
## - A meandering walk that stalls (blocked by a wall the navmesh does not
##   know) gives up after blocked_time and moves on to the wait state, while a
##   walk that keeps moving is never cut short.
## - Crowd avoidance: an enemy pursuing the player behind another enemy that
##   already stands at the player steers around it and reaches the player
##   instead of pushing into its back; dead enemies across its path do not
##   stop it.
## - Projectiles are parented to the world, so they outlive their shooter.
## - Ranged AI attacks a player in range and then moves on to one of its
##   configured next states; enemies never use auto-aim.
## - Aim gates: AIAttack and AIPursue only order an attack when the body faces
##   the target within desired_angle (they hold fire while unable to turn).
## - Waves place enemies at distinct points on the navmesh; wave budgets add up
##   to the difficulty with two tier-1 enemies first; difficulty follows
##   ProgressionState's own curve; the level title shows the level number.
##
## Cones, ranges, difficulties and speeds are read from the live nodes or set
## by the test, so retuning any of them never breaks the suite.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://Enemy/ranged_enemy.tscn")
const BASE_ENEMY_SCENE: PackedScene = preload("res://Enemy/enemy_base.tscn")
const BRUTE_SCENE: PackedScene = preload("res://Enemy/enemy_brute.tscn")
## Frame budget for an AI decision that involves turning and attacking.
const DECISION_FRAMES: int = 600
## Frames an aim gate must hold fire while the body cannot turn.
const HOLD_FRAMES: int = 30
## Test-owned wave budget and tier layout for the wave generation tests.
const TEST_BUDGET: int = 10
const WAVE_SAMPLES: int = 25
## Test-owned level number for the level title test.
const TITLE_LEVEL: int = 7
## Test-owned drop height that makes a spawned enemy fall.
const DROP_HEIGHT: float = 8.0
## Test-owned attack cooldown, far longer than DECISION_FRAMES covers, so an
## attack that wrongly started its cooldown cannot fire within a decision.
const LONG_COOLDOWN: float = 60.0
## Test-owned stall limit and progress distance for blocked meander walks.
const TEST_BLOCKED_TIME: float = 0.5
const TEST_BLOCKED_DISTANCE: float = 0.5
## Test-owned meander walk length, many blocked_times long at walking speed.
const WALK_DISTANCE: float = 6.0
## Test-owned gap between a caged enemy's body and the cage walls.
const CAGE_GAP: float = 0.15
## Test-owned distance between the player and the pursuer's start.
const BLOCKER_GAP: float = 4.0
## Test-owned number of corpses lying shoulder to shoulder across a path.
const CORPSE_ROW: int = 3

var _arena: Node3D


func before_each() -> void:
	_arena = load_arena()


func after_each() -> void:
	ProgressionState.reset_run()


# --- Characters and teams ------------------------------------------------------

func test_player_and_enemies_are_characters_on_opposite_teams() -> void:
	var player: Character = autofree(PLAYER_SCENE.instantiate()) as Character
	check(player.is_player() and not player.is_enemy(), "the player should be on the player team")
	check(player.is_in_group("player") and not player.is_in_group("enemy"), "the player should only be in the 'player' group")
	for scene: PackedScene in [BASE_ENEMY_SCENE, MELEE_SCENE, RANGED_SCENE]:
		var enemy: Character = autofree(scene.instantiate()) as Character
		if check(enemy != null, "%s should instantiate a Character" % scene.resource_path):
			check(enemy.is_enemy() and not enemy.is_player(), "%s should be on the enemy team" % scene.resource_path)
			check(enemy.is_in_group("enemy") and not enemy.is_in_group("player"), "%s should only be in the 'enemy' group" % scene.resource_path)


func test_nearest_target_is_the_closest_living_opponent() -> void:
	var player: Character = _spawn(PLAYER_SCENE, Vector3(0.0, 1.0, 0.0))
	var near: Character = _spawn(MELEE_SCENE, Vector3(5.0, 1.0, 0.0))
	var far: Character = _spawn(MELEE_SCENE, Vector3(10.0, 1.0, 0.0))
	await wait_physics_frames(1)
	check(player.get_nearest_target() == near, "the player should target the closest enemy")
	check(near.get_nearest_target() == player, "an enemy should target the player")
	near.hurtbox.receive_hit(near.attribute_component.get_current(AttributeComponent.POOL_HEALTH), Vector3.ZERO)
	check(player.get_nearest_target() == far, "defeated enemies should never be targeted")


func test_player_input_sets_the_movement_intent() -> void:
	var player: Character = _spawn(PLAYER_SCENE, (_arena.get_node("PlayerSpawn") as Node3D).global_position)
	var input_component: PlayerInputComponent = player.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if not check(input_component != null and input_component.character == player, "the player's input component should drive the player"):
		return
	hold_action(&"move_right")
	await wait_until(func() -> bool: return not player.move_direction.is_zero_approx(), "holding a move action should set a movement intent", 10)
	check(is_zero_approx(player.move_direction.y), "the movement intent should be horizontal")
	release_action(&"move_right")
	await wait_until(func() -> bool: return player.move_direction.is_zero_approx(), "releasing the move action should clear the intent", 10)


# --- Mind and body -------------------------------------------------------------

func test_ai_mind_commands_move_and_stop_the_body() -> void:
	var enemy: Character = _spawn(MELEE_SCENE, (_arena.get_node("EnemySpawn") as Node3D).global_position)
	disable_ai(enemy)
	var direction: Vector3 = Vector3(0.0, 0.0, 1.0)
	enemy.ai_state_machine.command_move(direction, direction)
	check(enemy.move_direction.is_equal_approx(direction), "command_move should set the body's movement intent")
	check(enemy.face_target.is_equal_approx(direction), "command_move should set the body's facing target")
	enemy.ai_state_machine.command_stop()
	check(enemy.move_direction.is_zero_approx() and enemy.face_target.is_zero_approx(), "command_stop should clear the body's intents")


func test_a_hit_stuns_the_body_and_the_mind_cannot_attack_until_it_recovers() -> void:
	var enemy: Character = await _grounded_enemy(MELEE_SCENE)
	disable_ai(enemy)
	var body: StateMachine = enemy.state_machine
	var stun_name: String = str(enemy.stun_state.name)
	var attack: CharacterState = (enemy.ai_state_machine.get_node("AIPursue") as AIPursue).body_state
	check(enemy.hurtbox.receive_hit(1.0, Vector3.ZERO), "the hit should land")
	check_eq(str(body.state.name), stun_name, "a hit should put the body in its stun state")
	check(not enemy.ai_state_machine.order_attack(attack), "the mind must not be able to order an attack while stunned")
	check_eq(str(body.state.name), stun_name, "a refused order must not interrupt the stun")
	await wait_until(func() -> bool: return str(body.state.name) != stun_name, "the body should recover from the stun", DECISION_FRAMES)
	check(enemy.ai_state_machine.order_attack(attack), "after recovering, the mind should be able to order an attack")
	check_eq(body.state, attack, "the ordered attack should run on the body")


func test_an_attack_refused_while_stunned_is_still_ready_after_the_stun() -> void:
	var enemy: Character = await _grounded_enemy(RANGED_SCENE)
	var mind: AIStateMachine = enemy.ai_state_machine
	var ai_attack: AIAttack = mind.get_node("AIAttack") as AIAttack
	var attack: CharacterAttack = ai_attack.body_state as CharacterAttack
	var meander: AIMeander = mind.get_node("AIMeander") as AIMeander
	# Test-owned: a long cooldown, and an aim gate that orders at once, so
	# the order lands while the body is still stunned.
	attack.cooldown = LONG_COOLDOWN
	ai_attack.desired_angle = 360.0
	var player: Character = _spawn_quiet_player(enemy.global_position + Vector3(meander.attack_range * 0.75, 0.0, 0.0))
	await wait_until(func() -> bool: return player.is_on_floor(), "setup: the player should land")
	if not check(enemy.hurtbox.receive_hit(1.0, Vector3.ZERO) and enemy.state_machine.state == enemy.stun_state, "setup: the hit should stun the enemy"):
		return
	mind.request_state(ai_attack.name)
	if not await wait_until(func() -> bool: return mind.state != ai_attack, "the refused order should end the AI attack", DECISION_FRAMES):
		return
	check(not ai_attack.is_on_cooldown(), "an attack order the stunned body refused must not start the attack's cooldown")
	await wait_until(func() -> bool: return enemy.state_machine.state == attack, "once the stun ends the enemy should attack", DECISION_FRAMES)


func test_a_falling_body_takes_no_orders() -> void:
	var spawn_point: Vector3 = (_arena.get_node("EnemySpawn") as Node3D).global_position
	var enemy: Character = _spawn(MELEE_SCENE, spawn_point + Vector3.UP * DROP_HEIGHT)
	disable_ai(enemy)
	var fall: CharacterState = (enemy.state_machine.initial_state as CharacterState).fall_state
	if not await wait_until(func() -> bool: return enemy.state_machine.state == fall, "setup: an enemy dropped from above should fall", DECISION_FRAMES):
		return
	var attack: CharacterState = (enemy.ai_state_machine.get_node("AIPursue") as AIPursue).body_state
	check(not enemy.ai_state_machine.order_attack(attack, true), "the mind must not order a falling body, even when it may break stun")
	check_eq(enemy.state_machine.state, fall, "a refused order must not interrupt the fall")


func test_an_order_never_restarts_the_running_attack() -> void:
	var enemy: Character = await _grounded_enemy(MELEE_SCENE)
	disable_ai(enemy)
	var attack: CharacterState = (enemy.ai_state_machine.get_node("AIPursue") as AIPursue).body_state
	if not check(enemy.ai_state_machine.order_attack(attack), "setup: the first order should start the attack"):
		return
	check(not enemy.ai_state_machine.order_attack(attack), "ordering the attack the body is already running must be refused")


func test_alert_skips_the_wait_and_leaves_an_engaged_mind_alone() -> void:
	var enemy: Character = await _grounded_enemy(MELEE_SCENE)
	var mind: AIStateMachine = enemy.ai_state_machine
	var wait: AIWait = mind.get_node("AIWait") as AIWait
	mind.request_state(wait.name)
	# Calm, like an enemy in a room that has not been triggered yet.
	enemy.is_alerted = false
	enemy.alert()
	if not check_eq(mind.state, wait.next_state, "an alerted waiting mind should skip the wait"):
		return
	# The character alerts only once; the mind's own alert() is what an
	# engaged mind must ignore.
	mind.alert()
	check_eq(mind.state, wait.next_state, "alerting an engaged mind should leave it as it is")


func test_alert_engages_a_meandering_mind() -> void:
	var enemy: Character = await _grounded_enemy(RANGED_SCENE)
	var mind: AIStateMachine = enemy.ai_state_machine
	var meander: AIMeander = mind.get_node("AIMeander") as AIMeander
	if not check(meander.pursue_state == null and meander.attack_state != null, "setup: the ranged enemy engages by attacking (no pursuit state)"):
		return
	mind.request_state(meander.name)
	# Calm, like an enemy in a room that has not been triggered yet.
	enemy.is_alerted = false
	enemy.alert()
	check_eq(mind.state, meander.attack_state, "an alerted meandering mind should engage its attack state")


func test_a_blocked_meander_walk_gives_up_and_waits() -> void:
	var enemy: Character = await _grounded_enemy(RANGED_SCENE)
	var mind: AIStateMachine = enemy.ai_state_machine
	var meander: AIMeander = mind.get_node("AIMeander") as AIMeander
	meander.blocked_time = TEST_BLOCKED_TIME
	meander.blocked_distance = TEST_BLOCKED_DISTANCE
	_cage(enemy)
	var destination: Vector3 = await _start_meander_walk(enemy, meander)
	if not await wait_until(func() -> bool: return mind.state != meander, "a blocked walk should give up", _frames_for(TEST_BLOCKED_TIME * 4.0)):
		return
	check_eq(mind.state, meander.wait_state, "a blocked walk should move on to the wait state")
	check(enemy.global_position.distance_to(destination) > WALK_DISTANCE * 0.5, "setup: the caged enemy should not have reached its destination")


func test_a_meander_walk_that_keeps_moving_is_never_cut_short() -> void:
	var enemy: Character = await _grounded_enemy(RANGED_SCENE)
	var mind: AIStateMachine = enemy.ai_state_machine
	var meander: AIMeander = mind.get_node("AIMeander") as AIMeander
	meander.blocked_time = TEST_BLOCKED_TIME
	meander.blocked_distance = TEST_BLOCKED_DISTANCE
	var destination: Vector3 = await _start_meander_walk(enemy, meander)
	var walk_frames: int = _frames_for(WALK_DISTANCE / maxf(enemy.attribute_component.get_current(AttributeComponent.STAT_SPEED), 0.1) * 3.0)
	if not await wait_until(func() -> bool: return mind.state != meander, "the walk should end", walk_frames):
		return
	var reach: float = enemy.navigation_agent_3d.target_desired_distance + TEST_BLOCKED_DISTANCE
	check(Vector2(enemy.global_position.x - destination.x, enemy.global_position.z - destination.z).length() <= reach, "a walk that keeps moving should only end at its destination")


func test_a_pursuer_steers_around_an_enemy_standing_at_the_player() -> void:
	await wait_for_navigation(_arena)
	var player: Character = _spawn_quiet_player(Vector3(0.0, 1.0, BLOCKER_GAP))
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, 1.0e9)
	player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, 1.0e9)
	player.knockback_component.max_knockback = 0.0
	var pursuer: Character = _spawn(MELEE_SCENE, Vector3(0.0, 1.0, -BLOCKER_GAP))
	disable_ai(pursuer)
	var pursue: AIPursue = pursuer.ai_state_machine.get_node("AIPursue") as AIPursue
	# Standing where an attacker stands: at attack range, straight between.
	var blocker: Character = _spawn(MELEE_SCENE, player.global_position + Vector3(0.0, 0.0, -pursue.attack_range))
	disable_ai(blocker)
	await wait_until(func() -> bool: return player.is_on_floor() and blocker.is_on_floor() and pursuer.is_on_floor(), "setup: everyone should land")
	if not check(pursuer.navigation_agent_3d.avoidance_enabled, "setup: enemies should use crowd avoidance"):
		return
	# Test-owned: the pursuer only walks (no attacks to stall it).
	pursue.attack_cooldown = LONG_COOLDOWN
	pursuer.ai_state_machine.process_mode = Node.PROCESS_MODE_INHERIT
	pursuer.ai_state_machine.request_state(pursue.name)
	var reach: float = pursue.attack_range + 0.5
	var walk_frames: int = _frames_for(BLOCKER_GAP * 3.0 / maxf(pursuer.attribute_component.get_current(AttributeComponent.STAT_SPEED), 0.1) * 3.0)
	await wait_until(func() -> bool: return pursuer.global_position.distance_to(player.global_position) <= reach, "the pursuer should get around the standing enemy and reach the player", walk_frames)


func test_a_pursuer_walks_through_a_row_of_corpses() -> void:
	await wait_for_navigation(_arena)
	var player: Character = _spawn_quiet_player(Vector3(0.0, 1.0, BLOCKER_GAP * 1.5))
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, 1.0e9)
	player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, 1.0e9)
	var pursuer: Character = _spawn(MELEE_SCENE, Vector3(0.0, 1.0, -BLOCKER_GAP * 1.5))
	disable_ai(pursuer)
	# A row of enemies shoulder to shoulder across the path, then killed.
	var spacing: float = float(pursuer.collision_shape_3d.shape.get("radius")) * 2.0 + 0.05
	var row: Array[Character] = []
	for index: int in CORPSE_ROW:
		var enemy: Character = _spawn(MELEE_SCENE, Vector3((index - (CORPSE_ROW - 1) * 0.5) * spacing, 1.0, 0.0))
		disable_ai(enemy)
		row.append(enemy)
	await wait_until(func() -> bool: return player.is_on_floor() and pursuer.is_on_floor(), "setup: everyone should land")
	for enemy: Character in row:
		enemy.hurtbox.receive_hit(enemy.attribute_component.get_current(AttributeComponent.POOL_HEALTH), Vector3.ZERO)
	var pursue: AIPursue = pursuer.ai_state_machine.get_node("AIPursue") as AIPursue
	pursue.attack_cooldown = LONG_COOLDOWN
	pursuer.ai_state_machine.process_mode = Node.PROCESS_MODE_INHERIT
	pursuer.ai_state_machine.request_state(pursue.name)
	# Straight through, in about the time walking the distance takes: no
	# stall in front of the row and no detour around it.
	var start_x: float = pursuer.global_position.x
	var widest: Array[float] = [0.0]
	var straight_time: float = (1.0 - pursuer.global_position.z) / maxf(pursuer.attribute_component.get_current(AttributeComponent.STAT_SPEED), 0.1)
	if not await wait_until(func() -> bool:
		widest[0] = maxf(widest[0], absf(pursuer.global_position.x - start_x))
		return pursuer.global_position.z > 1.0, "the pursuer should walk straight through the row of corpses", _frames_for(straight_time * 1.5)):
		return
	check(widest[0] < spacing, "the pursuer should not detour around the corpses (swerved %.2f m)" % widest[0])


func test_defeated_characters_stop_acting() -> void:
	var enemy: Character = await _grounded_enemy(MELEE_SCENE)
	var mind: AIStateMachine = enemy.ai_state_machine
	enemy.hurtbox.receive_hit(enemy.attribute_component.get_current(AttributeComponent.POOL_HEALTH), Vector3.ZERO)
	check(not enemy.is_alive(), "a character at zero health should not be alive")
	check_eq(enemy.state_machine.state, enemy.defeat_state, "the body should enter its defeat state")
	check(not mind.is_physics_processing(), "the mind should stop running on defeat")
	check(enemy.move_direction.is_zero_approx() and enemy.face_target.is_zero_approx(), "intents should be cleared on defeat")
	var rotation_before: Vector3 = enemy.mesh_mount.global_rotation
	enemy.look_at_target(enemy.global_position + Vector3(10.0, 0.0, 10.0), 1.0)
	enemy.look_toward_direction(Vector3(0.0, 0.0, -1.0), 1.0)
	check(enemy.mesh_mount.global_rotation.is_equal_approx(rotation_before), "a corpse must never turn")
	mind.command_move(Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	check(enemy.move_direction.is_zero_approx(), "the mind must not move a corpse")
	check(not mind.order_attack((mind.get_node("AIPursue") as AIPursue).body_state), "the mind must not order a corpse to attack")
	check_eq(enemy.state_machine.state, enemy.defeat_state, "a corpse should stay defeated")


func test_projectiles_outlive_their_shooter() -> void:
	var shooter: Character = _spawn(RANGED_SCENE, (_arena.get_node("EnemySpawn") as Node3D).global_position)
	disable_ai(shooter)
	await wait_physics_frames(1)
	var spawner: ProjectileSpawnerComponent = shooter.get_node("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	spawner.spawn_projectile()
	var projectile: Projectile = null
	for child: Node in get_children():
		if child is Projectile:
			projectile = child as Projectile
	if not check(projectile != null, "spawn_projectile() should put a projectile in the world"):
		return
	check(projectile.shooter == shooter, "the projectile should remember its shooter")
	shooter.free()
	await wait_physics_frames(1)
	check(is_instance_valid(projectile), "a projectile in flight must survive its shooter being removed")


# --- Ranged AI -----------------------------------------------------------------

func test_ranged_ai_attacks_a_player_in_range_then_moves_on() -> void:
	var enemy: Character = await _grounded_enemy(RANGED_SCENE)
	var mind: AIStateMachine = enemy.ai_state_machine
	var meander: AIMeander = mind.get_node("AIMeander") as AIMeander
	var attack: AIAttack = mind.get_node("AIAttack") as AIAttack
	var player: Character = _spawn_quiet_player(enemy.global_position + Vector3(meander.attack_range * 0.75, 0.0, 0.0))
	if not await wait_until(func() -> bool: return enemy.state_machine.state.name == attack.body_state.name, "a ranged enemy should attack a player within its attack range", DECISION_FRAMES):
		return
	check(_alignment(enemy, player) >= _cone_alignment(attack.desired_angle), "the attack should start with the target inside the aim cone")
	check(enemy.current_target == null, "enemies never use auto-aim targeting")
	await wait_until(func() -> bool: return mind.state != attack, "after attacking, the mind should leave AIAttack", DECISION_FRAMES)
	if not attack.next_states.is_empty():
		check(attack.next_states.has(mind.state), "after attacking, the mind should move to one of AIAttack.next_states (got %s)" % mind.state.name)


# --- Aim gates -----------------------------------------------------------------

func test_ai_attack_holds_fire_while_it_cannot_face_the_target() -> void:
	var setup: Array = await _ranged_facing_away()
	var enemy: Character = setup[0]
	var attack: AIAttack = setup[1]
	attack.desired_angle = 90.0
	_freeze_rotation(enemy)
	enemy.ai_state_machine.request_state("AIAttack")
	await wait_physics_frames(_hold_frames((attack.body_state as CharacterAttack).cooldown_timer))
	check(enemy.state_machine.state.name != attack.body_state.name, "AIAttack must not fire while the target is outside its cone")
	check(enemy.ai_state_machine.state == attack, "AIAttack should keep aiming instead of giving up")


func test_ai_attack_with_a_full_cone_fires_regardless_of_facing() -> void:
	var setup: Array = await _ranged_facing_away()
	var enemy: Character = setup[0]
	var attack: AIAttack = setup[1]
	attack.desired_angle = 360.0
	_freeze_rotation(enemy)
	await _order_until_attacking(enemy, "AIAttack", attack.body_state.name, "a 360-degree cone should fire even while facing away")


func test_ai_attack_with_a_zero_cone_fires_only_on_exact_alignment() -> void:
	var setup: Array = await _ranged_facing_away()
	var enemy: Character = setup[0]
	var attack: AIAttack = setup[1]
	var player: Character = setup[2]
	attack.desired_angle = 0.0
	var turn_speed: float = _freeze_rotation(enemy)
	enemy.ai_state_machine.request_state("AIAttack")
	await wait_physics_frames(_hold_frames((attack.body_state as CharacterAttack).cooldown_timer))
	check(enemy.state_machine.state.name != attack.body_state.name, "a zero cone must hold fire while misaligned")
	enemy.attribute_component.set_base(AttributeComponent.STAT_ROTATION_SPEED, turn_speed)
	if await _order_until_attacking(enemy, "AIAttack", attack.body_state.name, "a zero cone should fire once the AI has turned to face the target exactly"):
		check(_alignment(enemy, player) >= _cone_alignment(0.0), "a zero cone should only fire on (near) exact alignment")


func test_melee_pursue_turns_to_face_the_target_before_attacking() -> void:
	var enemy: Character = await _grounded_enemy(MELEE_SCENE)
	var pursue: AIPursue = enemy.ai_state_machine.get_node("AIPursue") as AIPursue
	pursue.desired_angle = 90.0
	var player: Character = _spawn_quiet_player(enemy.global_position + Vector3(pursue.attack_range * 0.5, 0.0, 0.0))
	await wait_until(func() -> bool: return player.is_on_floor(), "player should land")
	_turn_to_face(enemy, enemy.global_position - player.global_position)
	var turn_speed: float = _freeze_rotation(enemy)
	# The mind may start in another state (e.g. waiting); pursue explicitly so
	# the hold below really exercises the pursue aim gate.
	enemy.ai_state_machine.request_state("AIPursue")
	await wait_physics_frames(_hold_frames(maxf(pursue.cooldown_timer, pursue.attack_cooldown)))
	check(enemy.ai_state_machine.state == pursue, "setup: the mind should be pursuing during the hold")
	check(enemy.state_machine.state.name != pursue.body_state.name, "a melee enemy must not attack while facing away")
	enemy.attribute_component.set_base(AttributeComponent.STAT_ROTATION_SPEED, turn_speed)
	if await wait_until(func() -> bool: return enemy.state_machine.state.name == pursue.body_state.name, "the melee enemy should turn and attack", DECISION_FRAMES):
		check(_alignment(enemy, player) >= _cone_alignment(pursue.desired_angle), "the attack should start inside the pursue cone")


# --- Waves and progression -----------------------------------------------------

func test_wave_places_enemies_at_distinct_points_on_the_navmesh() -> void:
	var resource: EnemyResource = EnemyResource.new()
	resource.scene = MELEE_SCENE
	var wave: WaveObjective = WaveObjective.new()
	wave.boss_resources = [resource, resource, resource]
	wave.first_spawn_delay = 1000.0
	autofree(wave)
	_arena.add_child(wave)
	var nav_map: RID = _arena.get_world_3d().navigation_map
	if not await wait_for_navigation(_arena):
		return
	var planned: Array[Character] = wave.all_enemies.duplicate()
	for enemy: Character in planned:
		wave.spawn_enemy(enemy)
	for enemy: Character in planned:
		var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, enemy.global_position)
		check(Vector2(on_mesh.x, on_mesh.z).distance_to(Vector2(enemy.global_position.x, enemy.global_position.z)) < 0.5, "enemies should spawn on the navmesh")
	for i: int in range(planned.size()):
		for j: int in range(i + 1, planned.size()):
			check(planned[i].global_position.distance_to(planned[j].global_position) > 0.1, "enemies should spawn at distinct points, not stacked")


func test_difficulty_follows_the_progression_curve() -> void:
	ProgressionState.reset_run()
	check_eq(ProgressionState.dungeon_level, ProgressionState.base_dungeon_level, "a new run should start at the base dungeon level")
	check_eq(ProgressionState.difficulty_level, ProgressionState.calculate_difficulty(ProgressionState.dungeon_level), "difficulty should follow the curve at the start")
	var previous: int = ProgressionState.difficulty_level
	for i: int in range(6):
		var level_before: int = ProgressionState.dungeon_level
		ProgressionState.advance_level()
		check_eq(ProgressionState.dungeon_level, level_before + 1, "advance_level() should move to the next dungeon level")
		check_eq(ProgressionState.difficulty_level, ProgressionState.calculate_difficulty(ProgressionState.dungeon_level), "difficulty should follow the curve")
		check(ProgressionState.difficulty_level >= previous, "difficulty should never drop as the run advances")
		previous = ProgressionState.difficulty_level


func test_wave_budget_adds_up_with_two_tier_one_enemies_first() -> void:
	# Test-owned tiers: each tier uses its own scene so a generated enemy's
	# tier is known from its scene alone.
	var tiers: Dictionary[String, int] = {MELEE_SCENE.resource_path: 1, RANGED_SCENE.resource_path: 2, BRUTE_SCENE.resource_path: 3}
	var wave: WaveObjective = autofree(WaveObjective.new()) as WaveObjective
	for scene_path: String in tiers:
		var resource: EnemyResource = EnemyResource.new()
		resource.scene = load(scene_path) as PackedScene
		resource.difficulty_level = tiers[scene_path]
		wave.enemy_resources.append(resource)
	ProgressionState.current_planned_enemies.clear()
	ProgressionState.difficulty_level = TEST_BUDGET
	var saw_higher_tier: bool = false
	for sample: int in range(WAVE_SAMPLES):
		var enemies: Array[Character] = wave.generate_wave_enemies()
		var total: int = 0
		for index: int in range(enemies.size()):
			var tier: int = tiers.get(enemies[index].scene_file_path, 0)
			total += tier
			if index < 2:
				check_eq(tier, 1, "the first two enemies of a wave should be tier 1")
			saw_higher_tier = saw_higher_tier or tier > 1
			enemies[index].free()
		check_eq(total, TEST_BUDGET, "a wave's tiers should add up to the difficulty budget")
	check(saw_higher_tier, "a wave budget above two tier-1 enemies should sometimes use higher tiers")


func test_level_title_shows_the_level_number() -> void:
	var overlay: LevelTitleOverlay = UI.show_level_title(TITLE_LEVEL, 0.1)
	if check(overlay != null, "show_level_title() should display an overlay"):
		autofree(overlay)
		check(overlay.label.text.contains(str(TITLE_LEVEL)), "the level title should show the level number")


# --- helpers -------------------------------------------------------------------

func _spawn(scene: PackedScene, at: Vector3) -> Character:
	return spawn(scene, _arena, at) as Character


## Restarts enemy's meander walk toward a navmesh point WALK_DISTANCE away
## and returns that point.
func _start_meander_walk(enemy: Character, meander: AIMeander) -> Vector3:
	var mind: AIStateMachine = enemy.ai_state_machine
	mind.request_state(meander.wait_state.name)
	mind.request_state(meander.name)
	var nav_map: RID = enemy.get_world_3d().navigation_map
	var destination: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, enemy.global_position + Vector3(WALK_DISTANCE, 0.0, 0.0))
	check(destination.distance_to(enemy.global_position) > WALK_DISTANCE * 0.75, "setup: the destination should lie on the navmesh far from the enemy")
	enemy.navigation_agent_3d.target_position = destination
	await wait_physics_frames(1)
	return destination


## Walls the navmesh does not know, boxing character in with CAGE_GAP of room.
func _cage(character: Character) -> void:
	var radius: float = float(character.collision_shape_3d.shape.get("radius"))
	var reach: float = radius + CAGE_GAP + 0.5
	for side: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wall: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(1.0, 3.0, 1.0) + Vector3(absf(side.z), 0.0, absf(side.x)) * 2.0 * reach
		shape.shape = box
		wall.add_child(shape)
		wall.position = character.get_feet_position() + Vector3.UP * 1.5 + side * reach
		_arena.add_child(wall)


## Physics frames covering the given game time, plus a small margin.
func _frames_for(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 5


## A player whose live input is off, so only the test and physics move it.
func _spawn_quiet_player(at: Vector3) -> Character:
	var player: Character = _spawn(PLAYER_SCENE, at)
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	return player


## Spawns an enemy at EnemySpawn and waits until it stands in its home body state.
func _grounded_enemy(scene: PackedScene) -> Character:
	var enemy: Character = _spawn(scene, (_arena.get_node("EnemySpawn") as Node3D).global_position)
	await wait_until(func() -> bool: return enemy.is_on_floor() and enemy.state_machine.state == enemy.state_machine.initial_state, "the enemy should land and settle")
	return enemy


## A grounded ranged enemy facing directly away from a player inside its
## attack range. Returns [enemy, its AIAttack, player].
func _ranged_facing_away() -> Array:
	var enemy: Character = await _grounded_enemy(RANGED_SCENE)
	var meander: AIMeander = enemy.ai_state_machine.get_node("AIMeander") as AIMeander
	var player: Character = _spawn_quiet_player(enemy.global_position + Vector3(meander.attack_range * 0.75, 0.0, 0.0))
	await wait_until(func() -> bool: return player.is_on_floor(), "player should land")
	_turn_to_face(enemy, enemy.global_position - player.global_position)
	return [enemy, enemy.ai_state_machine.get_node("AIAttack") as AIAttack, player]


## Sets the character's rotation speed to zero so it cannot turn, and
## returns the previous speed for restoring.
func _freeze_rotation(character: Character) -> float:
	var speed: float = character.attribute_component.get_base(AttributeComponent.STAT_ROTATION_SPEED)
	character.attribute_component.set_base(AttributeComponent.STAT_ROTATION_SPEED, 0.0)
	return speed


## Keeps the mind in ai_state (re-requesting it if a refused order made it
## leave) until the body enters body_state. Returns whether it did.
func _order_until_attacking(enemy: Character, ai_state: String, body_state: String, message: String) -> bool:
	var mind: AIStateMachine = enemy.ai_state_machine
	return await wait_until(func() -> bool:
		if enemy.state_machine.state.name == body_state:
			return true
		if mind.state.name != ai_state:
			mind.request_state(ai_state)
		return false, message, DECISION_FRAMES)


## Frames an aim gate must hold fire: longer than any remaining attack
## cooldown, so a hold can never pass just because the cooldown was running.
func _hold_frames(remaining_cooldown: float) -> int:
	return HOLD_FRAMES + ceili(maxf(remaining_cooldown, 0.0) * Engine.physics_ticks_per_second)


## Cosine of the horizontal angle between the character's facing and the
## direction to the target (1.0 = facing it exactly).
func _alignment(character: Character, target: Character) -> float:
	var facing: Vector3 = character.mesh_mount.global_basis.z
	facing.y = 0.0
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	return facing.normalized().dot(to_target.normalized())


## Minimum alignment (cosine) inside a cone of cone_degrees, with a small
## tolerance for the final partial turn step.
func _cone_alignment(cone_degrees: float) -> float:
	return cos(deg_to_rad(minf(cone_degrees, 360.0) * 0.5 + 1.0))


## Turns the character's mount toward a direction with synchronous
## speed-limited steps (no frames elapse), for deterministic facings.
func _turn_to_face(character: Character, direction: Vector3) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.is_zero_approx():
		return
	flat = flat.normalized()
	for i: int in range(360):
		character.look_at_target(character.mesh_mount.global_position + flat * 5.0, 1.0 / 60.0)
		var facing: Vector3 = character.mesh_mount.global_basis.z
		facing.y = 0.0
		if facing.normalized().dot(flat) >= 0.999:
			return
