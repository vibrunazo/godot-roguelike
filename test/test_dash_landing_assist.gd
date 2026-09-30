## The dash's landing assist (LandingAssist on PlayerDash), at the arena's
## floor edge (a sheer drop):
## - a dash grazing the edge, whose landing would be over the drop, is steered
##   back onto the floor by no more than the assist's max_correction_angle and
##   the player does not fall,
## - a dash straight off the edge, which no rotation within the limit can
##   save, keeps its direction and the player falls,
## - a dash across a gap that lands on floor keeps its direction,
## - a dash that ends on floor but whose braking slide would carry the player
##   over the edge is steered,
## - a dash that ends on floor but would walk the player off the edge within
##   reaction_time of still holding the direction is steered.
## The assist's settings and the player's braking are test-owned (instant
## stop and no reaction time unless a test sets them); the dash distance and
## slide are read live.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned assist settings.
const MAX_CORRECTION_DEGREES: float = 30.0
const ANGLE_STEP_DEGREES: float = 5.0
## Test-owned braking for the slide test: slow enough that the slide after a
## dash is several meters long.
const SLIDE_STOP_TIME: float = 0.03
## Test-owned reaction time for the holding test.
const REACTION_TIME: float = 0.5
## How far outward, in degrees, the grazing dash points past running along
## the edge: well within MAX_CORRECTION_DEGREES.
const GRAZE_DEGREES: float = 20.0
## Width of the gap in the gap-crossing test, as a fraction of the dash
## distance: the grazing dash starts this far inside the edge and still lands
## past the gap.
const GAP_RATIO: float = 0.1
## Physics ticks the player must stay grounded after a saved dash.
const SETTLE_FRAMES: int = 30
## Height under the floor top below which the player counts as fallen.
const FALLEN_DEPTH: float = 1.0
## Frame budget for one dash and its aftermath.
const ACTION_FRAMES: int = 300
## Direction tolerance, in degrees.
const ANGLE_TOLERANCE: float = 0.5

var _arena: Node3D
var _player: Character
var _dash: PlayerDash
var _floor_top: float
## World x of the arena floor's +x edge.
var _edge_x: float


func before_each() -> void:
	_arena = load_arena()
	_floor_top = arena_floor_top(_arena)
	var floor_shape: CollisionShape3D = _arena.get_node("NavigationRegion3D/Floor/CollisionShape3D") as CollisionShape3D
	_edge_x = floor_shape.global_position.x + (floor_shape.shape as BoxShape3D).size.x * 0.5
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	# Live input polling and auto-aim off: the test sets move_direction, and
	# out of combat the jump button always dashes.
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	(_player.get_node("TargetingComponent") as TargetingComponent).auto_aim_range = 0.0
	_player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, 100000.0)
	_dash = (_player.state_machine.get_node("PlayerRun") as CharacterState).dash_state as PlayerDash
	var assist: LandingAssist = LandingAssist.new()
	assist.max_correction_angle = MAX_CORRECTION_DEGREES
	assist.angle_step = ANGLE_STEP_DEGREES
	assist.reaction_time = 0.0
	_dash.landing_assist = assist
	_player.stop_time = 0.0
	await wait_until(func() -> bool: return _player.is_on_floor(), "the player should land on the arena floor")


func after_each() -> void:
	UI.resume_game()


func test_a_dash_grazing_the_edge_is_steered_back_onto_the_floor() -> void:
	var distance: float = _dash.get_dash_distance()
	# The landing sits half the outward travel past the edge.
	var ordered: Vector3 = _grazing_direction()
	var outward: float = ordered.x * distance
	await _place(_edge_x - outward * 0.5)
	if not await _dash_along(ordered):
		return
	var turned: float = rad_to_deg(ordered.angle_to(_dash.direction))
	check(turned > ANGLE_TOLERANCE, "the dash should be steered away from the drop")
	check(turned <= MAX_CORRECTION_DEGREES + ANGLE_TOLERANCE, "the steering should stay within max_correction_angle (turned %.1f degrees)" % turned)
	check(_dash.direction.x < ordered.x, "the dash should be steered inward, away from the edge")
	var grounded_frames: Array[int] = [0]
	var settled: bool = await wait_until(func() -> bool:
		if _fallen():
			return true
		grounded_frames[0] = grounded_frames[0] + 1 if _state() == "PlayerRun" and _player.is_on_floor() else 0
		return grounded_frames[0] >= SETTLE_FRAMES, "the player should settle after the dash", ACTION_FRAMES)
	if settled:
		check(not _fallen(), "the steered dash should not drop the player off the edge")


func test_a_dash_straight_off_the_edge_keeps_its_direction_and_falls() -> void:
	await _place(_edge_x - _dash.get_dash_distance() * 0.5)
	if not await _dash_along(Vector3.RIGHT):
		return
	check(rad_to_deg(Vector3.RIGHT.angle_to(_dash.direction)) <= ANGLE_TOLERANCE, "a dash no allowed rotation can save should keep its direction")
	await wait_until(_fallen, "a deliberate dash off the edge should drop the player", ACTION_FRAMES)


func test_a_dash_across_a_gap_that_lands_on_floor_keeps_its_direction() -> void:
	var distance: float = _dash.get_dash_distance()
	var ordered: Vector3 = _grazing_direction()
	var gap: float = distance * GAP_RATIO
	# A test-owned slab past a narrow gap catches the grazing landing. Turning
	# the dash back inward would also land on floor, so an assist that
	# (wrongly) feared the gap under the path would steer.
	var slab: StaticBody3D = autofree(StaticBody3D.new()) as StaticBody3D
	slab.collision_layer = 1
	slab.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(distance * 2.0, 1.0, distance * 4.0)
	shape.shape = box
	slab.add_child(shape)
	_arena.add_child(slab)
	slab.global_position = Vector3(_edge_x + gap + box.size.x * 0.5, _floor_top - box.size.y * 0.5, 0.0)
	await _place(_edge_x - gap)
	if not await _dash_along(ordered):
		return
	check(rad_to_deg(ordered.angle_to(_dash.direction)) <= ANGLE_TOLERANCE, "a dash that clears the gap should keep its direction")
	if not await wait_until(func() -> bool: return _fallen() or (_state() == "PlayerRun" and _player.is_on_floor()), "the dash should end", ACTION_FRAMES):
		return
	check(not _fallen() and _player.global_position.x > _edge_x + gap, "the player should land on the far side of the gap")


func test_a_dash_whose_slide_would_cross_the_edge_is_steered() -> void:
	_player.stop_time = SLIDE_STOP_TIME
	var ordered: Vector3 = _grazing_direction()
	var slide: float = _player.get_braking_distance(ordered * _dash.dash_speed, _player.attribute_component.get_current(AttributeComponent.STAT_SPEED))
	if not check(slide > 1.0, "setup: the test-owned braking should slide the player on after a dash"):
		return
	# The dash itself ends inside the edge; the slide ends as far past it.
	await _place(_edge_x - (_dash.get_dash_distance() + slide * 0.5) * ordered.x, _dash.get_dash_distance() + slide)
	await _check_saved(ordered, "the braking slide")


func test_a_dash_that_would_walk_off_the_edge_while_still_held_is_steered() -> void:
	(_dash.landing_assist as LandingAssist).reaction_time = REACTION_TIME
	var ordered: Vector3 = _grazing_direction()
	var moving_on: float = _player.attribute_component.get_current(AttributeComponent.STAT_SPEED) * REACTION_TIME
	# The dash ends inside the edge; holding the direction for REACTION_TIME
	# carries the player as far past it.
	await _place(_edge_x - (_dash.get_dash_distance() + moving_on * 0.5) * ordered.x, _dash.get_dash_distance() + moving_on)
	await _check_saved(ordered, "moving on")


## Dashes along ordered and checks the assist steered it inward (within
## max_correction_angle) and the player never falls off the edge, while the
## movement stays held for the assist's reaction_time after the dash. what
## names the hazard for messages.
func _check_saved(ordered: Vector3, what: String) -> void:
	if not await _dash_along(ordered, true):
		return
	var turned: float = rad_to_deg(ordered.angle_to(_dash.direction))
	check(turned > ANGLE_TOLERANCE and _dash.direction.x < ordered.x, "the dash should be steered inward, away from the edge %s would cross" % what)
	check(turned <= MAX_CORRECTION_DEGREES + ANGLE_TOLERANCE, "the steering should stay within max_correction_angle (turned %.1f degrees)" % turned)
	await wait_until(func() -> bool: return _state() != _dash.name, "the dash should end", ACTION_FRAMES)
	var held_until: int = Engine.get_physics_frames() + floori((_dash.landing_assist as LandingAssist).reaction_time * Engine.physics_ticks_per_second)
	var grounded_frames: Array[int] = [0]
	var settled: bool = await wait_until(func() -> bool:
		if Engine.get_physics_frames() >= held_until:
			_player.move_direction = Vector3.ZERO
		if _fallen():
			return true
		grounded_frames[0] = grounded_frames[0] + 1 if _player.is_on_floor() and _player.velocity.is_zero_approx() else 0
		return grounded_frames[0] >= SETTLE_FRAMES, "the player should settle after the dash", ACTION_FRAMES)
	if settled:
		check(not _fallen(), "the steered dash should not let %s drop the player off the edge" % what)


## Running along the +x edge (-z), turned GRAZE_DEGREES outward.
func _grazing_direction() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-GRAZE_DEGREES))


## Moves the grounded player to x = at, with run meters of floor ahead of it
## along -z, and lets it settle.
func _place(at: float, run: float = 0.0) -> void:
	_player.global_position = Vector3(at, _player.global_position.y, run * 0.5)
	_player.velocity = Vector3.ZERO
	await wait_until(func() -> bool: return _player.is_on_floor(), "the placed player should stand on the floor")


## Presses the jump button (a dash, out of combat) while moving along
## direction. Unless hold, releases the movement once the dash starts so the
## run after it does not carry the player on. Returns whether the dash started.
func _dash_along(direction: Vector3, hold: bool = false) -> bool:
	_player.move_direction = direction
	press_action(&"jump")
	var started: bool = await wait_until(func() -> bool: return _state() == _dash.name, "the jump button should dash")
	if not hold:
		_player.move_direction = Vector3.ZERO
	return started


func _fallen() -> bool:
	return _player.global_position.y < _floor_top - FALLEN_DEPTH


func _state() -> String:
	return String(_player.state_machine.state.name)
