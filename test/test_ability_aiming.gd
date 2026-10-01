## Aiming abilities at the mouse cursor (AimTarget, AbilityResource.aim_mode):
## - an aimed fireball's path on screen runs through the cursor, whichever
##   way the cursor is from the player,
## - the cursor's aim lands on the floor it is over and sees through
##   characters: the aimed point under an enemy's body is the floor,
## - an aimed fireball rises to hit a foe standing on a raised floor, aimed by
##   the cursor and by auto-aim alike, and a flat one stays at its cast height,
## - a fireball cast at the top of a jump angles down and hits a foe on the
##   ground under the cursor,
## - a ground-aimed lob lands on the floor point under the cursor, on the
##   ground and on a raised floor.
## Abilities, foes and the raised floor are built by the test; their numbers
## are test-owned.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const FIREBALL_SCENE: PackedScene = preload("res://Enemy/fireball_projectile.tscn")
const LOB_SCENE: PackedScene = preload("res://Enemy/firebomb_projectile.tscn")
const FIREBALL: AbilityResource = preload("res://Abilities/AbilityResources/ability_fireball.tres")
## Test-owned screen distance of the cursor from the player, in pixels.
const CURSOR_DISTANCE: float = 200.0
## How far a projectile's on-screen path may pass from the cursor, in pixels.
const PATH_TOLERANCE: float = 2.0
## Test-owned raised floor: height, and depth/width of its square top.
const PLATFORM_HEIGHT: float = 2.0
const PLATFORM_SIZE: float = 4.0
## Test-owned distances ahead of the player (up the screen), in meters: the
## raised floor's near edge, and the foe.
const PLATFORM_NEAR_EDGE: float = 4.5
const FOE_DISTANCE: float = 6.0
## Test-owned foe health, so no hit defeats it.
const FOE_HEALTH: float = 100000.0
## How close a lob's landing point must be to the aimed point, in meters.
const LANDING_TOLERANCE: float = 0.1
## Frame budget for a cast or a flight.
const ACTION_FRAMES: int = 600

var _arena: Node3D
var _floor_top: float
var _player: Character
var _input: PlayerInputComponent
var _spawned: Array[Projectile] = []


func before_each() -> void:
	_spawned.clear()
	get_tree().node_added.connect(_on_node_added)
	_arena = load_arena()
	_floor_top = arena_floor_top(_arena)
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	_input = _player.get_node("PlayerInputComponent") as PlayerInputComponent
	# The cursor aims, not auto-aim, unless a test turns it back on.
	(_player.get_node("TargetingComponent") as TargetingComponent).auto_aim_range = 0.0
	(_player.get_node("CameraRoot/ShakeCamera3D") as Camera3D).make_current()
	# The headless window is tiny, so the stretch transform would scale mouse
	# coordinates; a window at the project's base size maps them one to one.
	var base_size: Vector2i = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width") as int, ProjectSettings.get_setting("display/window/size/viewport_height") as int)
	get_window().size = base_size
	await wait_until(func() -> bool: return Vector2i(get_viewport().get_visible_rect().size) == base_size, "the viewport should take the window size", 30)
	await wait_until(func() -> bool: return _player.is_on_floor() and _player.state_machine.state.name == "PlayerRun", "the player should settle")
	# The camera's projection catches up with the new size on a later render
	# frame: wait until the player's screen position holds still.
	var last: Vector2 = Vector2.INF
	for frame: int in range(10):
		await get_tree().process_frame
		var now: Vector2 = _camera().unproject_position(_player.global_position)
		if now.is_equal_approx(last):
			return
		last = now
	fail("the player's screen position should settle")


func after_each() -> void:
	get_tree().node_added.disconnect(_on_node_added)


func test_an_aimed_fireball_flies_through_the_cursor_on_screen() -> void:
	var ability: AbilityResource = _ability(CharacterAction.AimMode.AIMED, FIREBALL_SCENE)
	_player.ability_system_component.grant_ability(ability, null, 0)
	for degrees: int in range(0, 360, 45):
		var center: Vector2 = _camera().unproject_position(_player.global_position)
		var cursor: Vector2 = center + Vector2.from_angle(deg_to_rad(degrees)) * CURSOR_DISTANCE
		var shot: Projectile = await _cast_at_screen(cursor)
		if shot == null:
			return
		cursor = _player.get_viewport().get_mouse_position()
		var start: Vector2 = _camera().unproject_position(shot.global_position)
		var ahead: Vector2 = _camera().unproject_position(shot.global_position + shot.global_basis.z * 5.0)
		var path: Vector2 = (ahead - start).normalized()
		var offset: float = absf(path.cross(cursor - start))
		check(offset <= PATH_TOLERANCE, "aimed %d° around the player, the fireball should pass through the cursor on screen (passes %.1f px off)" % [degrees, offset])
		check(path.dot(cursor - start) > 0.0, "aimed %d° around the player, the fireball should fly toward the cursor" % degrees)
		await _wait_ready()


func test_the_cursor_aims_at_the_floor_under_an_enemys_body() -> void:
	var foe: Character = _spawn_foe(_ahead(FOE_DISTANCE), _floor_top)
	await _move_mouse(_camera().unproject_position(foe.global_position))
	var aim: AimTarget = _input.get_aim_target()
	check_approx(aim.floor_point.y, _floor_top, "the aimed point should be on the floor behind the enemy's body, not on it", 0.01)


func test_an_aimed_fireball_hits_a_foe_on_a_raised_floor_by_cursor_and_auto_aim() -> void:
	_add_platform()
	var ability: AbilityResource = _ability(CharacterAction.AimMode.AIMED, FIREBALL_SCENE)
	_player.ability_system_component.grant_ability(ability, null, 0)
	var foe: Character = _spawn_foe(_ahead(FOE_DISTANCE), _floor_top + PLATFORM_HEIGHT)
	for auto_aim: bool in [false, true]:
		(_player.get_node("TargetingComponent") as TargetingComponent).auto_aim_range = 100.0 if auto_aim else 0.0
		if auto_aim and not await wait_until(func() -> bool: return _player.current_target == foe, "auto-aim should lock onto the foe"):
			return
		var health: float = _health(foe)
		if await _cast_at_screen(_camera().unproject_position(foe.get_feet_position())) == null:
			return
		await wait_until(func() -> bool: return _health(foe) < health, "a fireball aimed by %s should rise and hit the foe on the raised floor" % ("auto-aim" if auto_aim else "the cursor"), ACTION_FRAMES)
		await _wait_ready()


func test_a_flat_fireball_stays_at_its_cast_height() -> void:
	_add_platform()
	var ability: AbilityResource = _ability(CharacterAction.AimMode.FLAT, FIREBALL_SCENE)
	_player.ability_system_component.grant_ability(ability, null, 0)
	var shot: Projectile = await _cast_at_screen(_camera().unproject_position(_ahead(FOE_DISTANCE) + Vector3.UP * (_floor_top + PLATFORM_HEIGHT)))
	if shot == null:
		return
	check(absf(shot.global_basis.z.y) < 0.001, "a flat fireball aimed at a raised floor should fly level")


func test_a_fireball_cast_at_the_top_of_a_jump_hits_a_foe_under_the_cursor() -> void:
	var ability: AbilityResource = _ability(CharacterAction.AimMode.AIMED, FIREBALL_SCENE)
	_player.ability_system_component.grant_ability(ability, null, 0)
	var foe: Character = _spawn_foe(_ahead(FOE_DISTANCE), _floor_top)
	var health: float = _health(foe)
	_player.state_machine.request_state("PlayerJump")
	if not await wait_until(func() -> bool: return not _player.is_on_floor() and _player.velocity.y <= 0.5, "the jump should reach its top", ACTION_FRAMES):
		return
	if await _cast_at_screen(_camera().unproject_position(foe.get_feet_position())) == null:
		return
	await wait_until(func() -> bool: return _health(foe) < health, "a fireball cast at the top of a jump should angle down and hit the foe under the cursor", ACTION_FRAMES)


func test_a_ground_aimed_lob_lands_on_the_floor_under_the_cursor() -> void:
	_add_platform()
	var ability: AbilityResource = _ability(CharacterAction.AimMode.GROUND, LOB_SCENE)
	_player.ability_system_component.grant_ability(ability, null, 0)
	var on_ground: Vector3 = _ahead(PLATFORM_NEAR_EDGE * 0.5) + Vector3.UP * _floor_top
	var on_platform: Vector3 = _ahead(FOE_DISTANCE) + Vector3.UP * (_floor_top + PLATFORM_HEIGHT)
	for aimed: Vector3 in [on_ground, on_platform]:
		var lob: BallisticProjectile = await _cast_at_screen(_camera().unproject_position(aimed)) as BallisticProjectile
		if not check(lob != null, "the ground-aimed ability should lob a ballistic projectile"):
			return
		check(lob.target_position.distance_to(aimed) <= LANDING_TOLERANCE, "the lob should land on the floor point under the cursor (aimed %s, lands %s)" % [aimed, lob.target_position])
		await _wait_ready()


## Moves the cursor to screen_position, casts slot 1 and returns the payload
## it releases (null after a recorded failure).
func _cast_at_screen(screen_position: Vector2) -> Projectile:
	await _move_mouse(screen_position)
	_spawned.clear()
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return not _spawned.is_empty(), "the cast should release its payload", ACTION_FRAMES):
		return null
	return _spawned[0]


## Waits until the player runs again and slot 1 is off cooldown.
func _wait_ready() -> void:
	await wait_until(func() -> bool: return _player.is_on_floor() and _player.state_machine.state.name == "PlayerRun" and _player.ability_system_component.get_cooldown_fraction(0) == 0.0, "the player should be ready to cast again", ACTION_FRAMES)


## A test-owned ability releasing scene, aimed by aim_mode, castable again at
## once.
func _ability(aim_mode: CharacterAction.AimMode, scene: PackedScene) -> AbilityResource:
	var ability: AbilityResource = AbilityResource.new()
	ability.id = StringName("test_aim_%d" % randi())
	ability.cooldown = 0.0
	ability.release_time = 0.1
	ability.cast_animation = FIREBALL.cast_animation
	ability.aim_mode = aim_mode
	ability.payload_scene = scene
	return ability


## The point distance meters up the screen from the player, on the ground plane.
func _ahead(distance: float) -> Vector3:
	var forward: Vector3 = -_camera().global_basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var at: Vector3 = _player.global_position + forward * distance
	return Vector3(at.x, 0.0, at.z)


## A solid raised floor up the screen from the player (on the World layer).
func _add_platform() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(PLATFORM_SIZE, PLATFORM_HEIGHT, PLATFORM_SIZE)
	shape.shape = box
	body.add_child(shape)
	var center: Vector3 = _ahead(PLATFORM_NEAR_EDGE + PLATFORM_SIZE * 0.5)
	body.position = Vector3(center.x, _floor_top + PLATFORM_HEIGHT * 0.5, center.z)
	_arena.add_child(body)
	body.look_at(body.global_position + (_ahead(1.0) - Vector3(_player.global_position.x, 0.0, _player.global_position.z)), Vector3.UP)


## A foe that neither thinks nor dies, standing at ground_point (x, z) on a
## floor whose top is at floor_y.
func _spawn_foe(ground_point: Vector3, floor_y: float) -> Character:
	var foe: Character = MELEE_SCENE.instantiate() as Character
	autofree(foe)
	foe.position = Vector3(ground_point.x, floor_y + 0.1, ground_point.z) + Vector3.UP * foe.get_origin_height()
	_arena.add_child(foe)
	disable_ai(foe)
	foe.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, FOE_HEALTH)
	foe.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, FOE_HEALTH)
	foe.knockback_component.max_knockback = 0.0
	return foe


func _camera() -> Camera3D:
	return _player.get_viewport().get_camera_3d()


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Moves the mouse and waits until the viewport reports the new position
## (input is flushed per render frame, so at a low frame rate several physics
## ticks can pass before the mouse position updates).
func _move_mouse(screen_position: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = screen_position
	motion.global_position = screen_position
	Input.parse_input_event(motion)
	_player.get_viewport().warp_mouse(screen_position)
	await wait_until(func() -> bool: return _player.get_viewport().get_mouse_position().distance_to(screen_position) < 1.0, "the mouse should move to %s" % screen_position, 30)


func _on_node_added(node: Node) -> void:
	if node is Projectile:
		_spawned.append(node as Projectile)
