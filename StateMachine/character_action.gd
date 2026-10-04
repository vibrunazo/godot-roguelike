## Shared base of every timed body action: melee attacks (CharacterAttack)
## and ability casts (AbilityCastState). It owns what they have in common: the
## cooldown and tag gates, the animation and the return to next_states when it
## finishes, the aim snapshot (toward the auto-aim target when one is locked),
## the aimed release of payloads (release_payload(), by aim_mode), the lunge
## along the aim (begin_lunge(): a melee step, a charge), the cancel window
## for dash, jump and ability intents, gravity, and the STARTED/ENDED
## lifecycle events. Subclasses add what they do while running.
class_name CharacterAction
extends CharacterState

## How a release is aimed at the action's aim (see aim_mode).
enum AimMode { AIMED, FLAT, GROUND }

## Below this horizontal distance, in meters, between the release origin and
## the aimed point (aiming at the caster itself) the point gives no reliable
## heading: the release goes along aim_direction instead.
const MIN_AIM_DISTANCE: float = 0.3

## Speed in m/s the character can steer at while this action runs (0.0 = stationary).
@export var movement_speed: float = 0.0
## Whether dash, jump and ability intents may cancel this action early. When
## off, those intents are consumed and dropped while it runs.
@export var cancelable: bool = false
## Whether the character keeps its height while this action runs in the air
## (for air combos). Off, gravity applies and the character falls.
@export var float_in_air: bool = false
## States to transition to when the action animation finishes (random pick;
## single-element arrays behave deterministically for ordered chains).
@export var next_states: Array[CharacterState]
## Name of the animation tree state played by this action.
@export var animation_name: String = "SlashAttack"
## Whether this action is uninterruptable (immune to stun interruption while active).
@export var uninterruptable: bool = false
## Cooldown time in seconds between executions (0.0 = ready immediately).
@export var cooldown: float = 0.0
## Initial cooldown in seconds applied when entering the scene (0.0 = ready immediately).
@export var starting_cooldown: float = 0.0
## Gameplay tags required on the character for this action to activate.
@export var required_tags: Array[StringName] = []
## Gameplay tags that block this action from activating if present on the character.
@export var blocked_tags: Array[StringName] = []
## If true, starts the cooldown timer when tag requirements transition from unmet to met.
@export var start_cooldown_on_enabled: bool = false
## How payloads this action releases (release_payload()) are aimed at its aim:
## AIMED: straight at the point the caster sees at its release height above
##   the aimed floor: level on flat ground, up or down to another floor, down
##   from a jump.
## FLAT: level at the release height, turned toward what the caster sees at
##   that height.
## GROUND: at the aimed floor point itself; a lobbed payload lands there.
@export var aim_mode: AimMode = AimMode.AIMED
## Speed in m/s of the lunge this action can make along its aim
## (begin_lunge(): a melee attack steps at its strike, a cast charges at its
## release). 0.0 = no lunge.
@export var dash_speed: float = 0.0
## Duration in seconds of the lunge (physics clock). 0.0 = no lunge.
@export var dash_duration: float = 0.0
## Steers the lunge away from ending over a pit when that looks like a
## mistake (see LandingAssist). Null lunges exactly along the aim.
@export var lunge_landing_assist: LandingAssist

## Remaining cooldown time in seconds before this action can be executed again.
var cooldown_timer: float = 0.0
## True while the lunge runs (begin_lunge() until end_lunge()).
var lunging: bool = false
## Horizontal direction of the lunge.
var lunge_direction: Vector3 = Vector3.ZERO
## Horizontal velocity the character had when the lunge began, kept under it.
var _lunge_base_velocity: Vector3 = Vector3.ZERO
var lunge_timer: SceneTreeTimer
## Horizontal direction this action is aimed at, snapshotted on entry.
var aim_direction: Vector3 = Vector3.ZERO
## What this action is aimed at, snapshotted on entry (see _resolve_aim()).
var aim_target: AimTarget = null
var _was_tag_enabled: bool = false
## True once this action pointed character.aim_direction at its target, so
## exit() clears exactly that.
var _wrote_character_aim: bool = false


func _ready() -> void:
	cooldown_timer = starting_cooldown
	_was_tag_enabled = _check_tags()


## Returns true if this action is currently on cooldown.
func is_on_cooldown() -> bool:
	return cooldown_timer > 0.0


## Checks whether all required tags are present and no blocked tags are present.
func _check_tags() -> bool:
	if character == null:
		return true
	for tag: StringName in required_tags:
		if not character.has_tag(tag):
			return false
	for tag: StringName in blocked_tags:
		if character.has_tag(tag):
			return false
	return true


## Updates tag enablement and starts cooldown on transition if configured.
func _update_tag_enablement() -> void:
	var currently_enabled: bool = _check_tags()
	if currently_enabled and not _was_tag_enabled:
		if start_cooldown_on_enabled:
			cooldown_timer = cooldown
	_was_tag_enabled = currently_enabled


func is_uninterruptable() -> bool:
	return uninterruptable


## Returns true if both cooldown and tag requirements allow activation.
func can_activate() -> bool:
	_update_tag_enablement()
	if is_on_cooldown():
		return false
	return _check_tags()


## The action owns its cooldown and ticks it itself, every physics frame,
## whoever controls the body: controllers only read it (is_on_cooldown(),
## can_activate()), so nothing can tick it twice.
func _physics_process(delta: float) -> void:
	_update_tag_enablement()
	if cooldown_timer > 0.0:
		cooldown_timer = maxf(0.0, cooldown_timer - delta)


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	# Dash and jump intents cancel the action only inside its cancel window
	# (see cancelable); attack intents go to check_attack().
	if check_dash():
		return
	if check_jump():
		return
	if check_ability():
		return
	check_attack()
	_before_motion(delta)
	var planar: Vector3 = _planar_velocity()
	character.velocity.x = planar.x
	character.velocity.z = planar.z
	_apply_gravity(delta)
	if _can_turn():
		character.look_toward_direction(aim_direction, delta)
	character.move_character()
	if lunging and _lunge_hit_wall():
		end_lunge()


## Virtual: per-frame bookkeeping before the motion is computed (hitstop).
func _before_motion(_delta: float) -> void:
	pass


## Virtual: the horizontal velocity for this frame: the lunge while it runs,
## the steered movement otherwise.
func _planar_velocity() -> Vector3:
	if lunging:
		return _lunge_base_velocity + lunge_direction * dash_speed
	return character.move_direction * movement_speed


## Whether this action lunges at all (dash_speed and dash_duration set).
func has_lunge() -> bool:
	return dash_speed > 0.0 and dash_duration > 0.0


## Starts the lunge along the aim direction (the facing when there is none)
## at dash_speed for dash_duration seconds; it ends early against a wall.
## Subclasses decide when: a melee attack at its strike, a cast at its
## release.
func begin_lunge() -> void:
	if not has_lunge() or character == null or not character.is_inside_tree():
		return
	lunge_direction = aim_direction
	if lunge_direction.is_zero_approx() and character.mesh_mount != null:
		lunge_direction = character.mesh_mount.global_basis.z.normalized()
	if lunge_direction.is_zero_approx():
		lunge_direction = Vector3.FORWARD
	lunge_direction = lunge_direction.normalized()
	if lunge_landing_assist != null:
		lunge_direction = lunge_landing_assist.steer(character, lunge_direction, dash_speed * dash_duration)
	_lunge_base_velocity = Vector3(character.velocity.x, 0.0, character.velocity.z)
	lunging = true
	lunge_timer = get_tree().create_timer(dash_duration, true, true)
	lunge_timer.timeout.connect(end_lunge)


## Ends the lunge; the action's normal motion resumes.
func end_lunge() -> void:
	lunging = false


## Whether the lunge just ran head-on into something that is not a character
## (a wall, a prop): it stops there instead of pressing on. Characters in the
## way are shoved through (the lunge's hits knock them back).
func _lunge_hit_wall() -> bool:
	for index: int in character.get_slide_collision_count():
		var collision: KinematicCollision3D = character.get_slide_collision(index)
		if collision.get_collider() is Character:
			continue
		if collision.get_normal().dot(lunge_direction) < -0.5:
			return true
	return false


## Clears the lunge: motion flag, base velocity and timer wiring.
func _clear_lunge() -> void:
	lunging = false
	_lunge_base_velocity = Vector3.ZERO
	if lunge_timer != null:
		disconnect_safe(lunge_timer.timeout, end_lunge)
		lunge_timer = null


## Virtual: whether the character may turn toward the aim this frame.
func _can_turn() -> bool:
	return true


## Falls under gravity while airborne unless float_in_air holds the height.
func _apply_gravity(delta: float) -> void:
	if float_in_air or character.is_on_floor():
		if character.velocity.y < 0.0 or float_in_air:
			character.velocity.y = 0.0
		return
	character.velocity += character.get_gravity() * delta


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	cooldown_timer = cooldown
	if character == null:
		return
	if uninterruptable and character.knockback_component != null:
		character.knockback_component.magnitude = Vector3.ZERO
	if character.animation_tree != null:
		character.animation_tree.change_immediate(animation_name)
		connect_one_shot(character.animation_tree.animation_finished, finish_action)
	character.is_attacking = true
	aim_target = _resolve_aim(_data)
	aim_direction = aim_target.flat_direction_from(character.global_position)
	if aim_direction.is_zero_approx() and character.mesh_mount != null:
		# Aimed right at the character's own spot: keep the facing.
		aim_direction = Vector3(character.mesh_mount.global_basis.z.x, 0.0, character.mesh_mount.global_basis.z.z).normalized()
	_aim_at_locked_target()
	broadcast_ability_event(AbilityEvent.Phase.STARTED, {}, aim_direction)


## What this action is aimed at, snapshotted on entry: the character's aim
## target (the player's controller keeps it on the mouse cursor), else the
## order's "aim_target" (AI orders aim at their target). Without either, it
## aims along a direction: the character's aim_direction, the order's "aim",
## the movement direction or the facing, in that order.
func _resolve_aim(data: Dictionary) -> AimTarget:
	if character.aim_target != null:
		return character.aim_target
	if data.get("aim_target") is AimTarget:
		return data["aim_target"]
	var feet: Vector3 = character.get_feet_position()
	if not character.aim_direction.is_zero_approx():
		return AimTarget.toward(feet, character.aim_direction)
	if data.get("aim") is Vector3:
		return AimTarget.toward(feet, data["aim"])
	if not character.move_direction.is_zero_approx():
		return AimTarget.toward(feet, character.move_direction)
	if character.mesh_mount != null:
		return AimTarget.toward(feet, character.mesh_mount.global_basis.z)
	return AimTarget.toward(feet, Vector3.BACK)


## The node this action locks its aim on, or null to aim where the
## controller aims: the character's auto-aim target (current_target; for the
## player, an enemy near the cursor first, see TargetingComponent).
func get_locked_target() -> Node3D:
	var target: Node3D = character.current_target
	return target if is_instance_valid(target) else null


## Overrides the snapshotted aim with the locked target (get_locked_target())
## when there is one, so actions aim at it instead of the mouse aim. Writes
## the direction back to character.aim_direction so snapshot and intent stay
## consistent for the rest of the action.
func _aim_at_locked_target() -> void:
	var target: Node3D = get_locked_target()
	if target == null:
		return
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	if to_target.is_zero_approx():
		return
	aim_target = AimTarget.at_node(target)
	aim_direction = to_target.normalized()
	character.aim_direction = aim_direction
	_wrote_character_aim = true


## Spawns scene from origin through PayloadSpawner, aimed by aim_mode at
## release_aim() (release_direction(); a GROUND release gives a lob the aimed
## floor point to land on). Every payload an action releases goes through
## here: an ability's cast, a ranged attack's shot. With parent, the payload
## is parented there instead of the world (attached to the caster, it moves
## with it). Returns the payload, or null when it could not spawn.
func release_payload(scene: PackedScene, origin: Vector3, overrides: Array[PayloadPropertyOverride] = [], damage_multiplier: float = 1.0, scale_with_attack: bool = false, parent: Node3D = null) -> Node3D:
	var aim: AimTarget = release_aim()
	var landing: Vector3 = PayloadSpawner.NO_LANDING_POINT
	if aim_mode == AimMode.GROUND and aim.has_point:
		landing = aim.floor_point
	return PayloadSpawner.spawn(scene, character, origin, release_direction(origin), overrides, damage_multiplier, scale_with_attack, landing, parent)


## What a release now aims at: the locked target (get_locked_target(); it may
## have moved since the action started), else the aim snapshotted on entry.
func release_aim() -> AimTarget:
	var target: Node3D = get_locked_target()
	if target != null:
		return AimTarget.at_node(target)
	return aim_target


## The direction to release along from origin at release_aim(), by aim_mode:
## AIMED straight at what the caster sees at origin's height above its feet,
## measured above the aimed floor; FLAT level toward what it sees at origin's
## height; GROUND level toward the aimed floor point.
func release_direction(origin: Vector3) -> Vector3:
	var aim: AimTarget = release_aim()
	var point: Vector3
	match aim_mode:
		AimMode.FLAT:
			point = aim.point_at_y(origin.y)
		AimMode.GROUND:
			point = aim.floor_point
		_:
			point = aim.point_at_height(origin.y - character.get_feet_position().y)
	var to_point: Vector3 = point - origin
	var flat: Vector3 = Vector3(to_point.x, 0.0, to_point.z)
	if flat.length() < MIN_AIM_DISTANCE:
		if not aim_direction.is_zero_approx():
			return aim_direction
		return character.mesh_mount.global_basis.z.normalized() if character.mesh_mount != null else Vector3.BACK
	if aim_mode == AimMode.AIMED:
		return to_point.normalized()
	return flat.normalized()


## Dash-cancel gate: only cancelable actions can be interrupted.
## The intent is still consumed when gated off so the press never leaks into a
## later state. Cancelling runs exit(), which cleans everything up.
func check_dash() -> bool:
	if not cancelable:
		if character != null:
			character.consume_dash_request()
		return false
	return super.check_dash()


## Jump-cancel gate: only cancelable actions can be jump-cancelled.
## The intent is consumed when gated off so the press never leaks into a later state.
func check_jump(launch_ratio: float = -1.0) -> bool:
	if not cancelable:
		if character != null:
			character.consume_jump_request()
		return false
	return super.check_jump(launch_ratio)


## Ability-cancel gate: only cancelable actions can be cancelled into a cast.
func _allows_ability() -> bool:
	return cancelable


## Attack presses are consumed and dropped while an action runs; attacks
## override this to queue their combo follow-up.
func check_attack() -> bool:
	if character != null:
		character.consume_attack_request()
	return false


## Virtual: whether the action ran to completion, reported with ENDED.
func _is_completed() -> bool:
	return true


func exit() -> void:
	_clear_lunge()
	if character != null:
		character.is_attacking = false
		# Undo only the aim this action set (toward its target); a
		# controller's own aim is its business.
		if _wrote_character_aim:
			character.aim_direction = Vector3.ZERO
		if character.animation_tree != null:
			disconnect_safe(character.animation_tree.animation_finished, finish_action)
	_wrote_character_aim = false
	broadcast_ability_event(AbilityEvent.Phase.ENDED, {"completed": _is_completed()}, aim_direction)


## Transitions to a random pick of next_states when the action animation finishes.
func finish_action(_animation_name: String) -> void:
	if character == null or character.state_machine == null or next_states.is_empty():
		return
	var next: CharacterState = next_states.pick_random()
	if next != null:
		character.state_machine.request_state(next.name)
