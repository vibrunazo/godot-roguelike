## Unified base class for all characters (Player and Enemies).
## Distinguishes team and role via attached components and assigned groups ("player" vs "enemy").
class_name Character
extends CharacterBody3D

## Emitted when this character's health reaches zero.
signal defeat

## Emitted when this character's health changes.
signal health_changed(value: float)

## Emitted when current_target changes (including clearing to null).
signal target_changed(new_target: Node3D)

## Emitted when an attack belonging to this character lands a hit on a target.
signal hit_landed(target: Node, attack_component: AttackComponent)

## Emitted when this character is alerted into active combat.
signal alerted

## Emitted by cancel_movement_and_abilities(): components holding transient
## feedback (damage tint, camera shake, ...) reset it.
signal transient_state_cancelled

## Fallback rotation speed in degrees per second when no AttributeComponent is
## attached. Mirrors AttributeComponent.base_rotation_speed.
const DEFAULT_ROTATION_SPEED: float = 360.0
## Navigation auto-configuration (see _auto_configure_navigation()): the
## navmesh surface is baked this far above the floor geometry, in meters.
const NAV_SURFACE_ELEVATION: float = 0.35
## Waypoints count as reached within the agent radius plus this margin,
## clamped to [PATH_DISTANCE_MIN, PATH_DISTANCE_MAX], so corners round cleanly.
const PATH_DISTANCE_MARGIN: float = 0.3
const PATH_DISTANCE_MIN: float = 0.6
const PATH_DISTANCE_MAX: float = 1.5
## The final target counts as reached within the agent radius plus this
## margin, and never closer than TARGET_DISTANCE_MIN.
const TARGET_DISTANCE_MARGIN: float = 0.8
const TARGET_DISTANCE_MIN: float = 1.5
## Head slide (see _slide_off_enemy_head()): the lift out of margin contact
## before the retried step, and the minimum fall speed kept while sliding off,
## so landing checks stay airborne.
const HEAD_SLIDE_LIFT: float = 0.01
const HEAD_SLIDE_FALL_SPEED: float = 0.5

## The visual mount node rotated to face movement or aim directions.
@export var mesh_mount: Node3D
## Reference to the character's AttributeComponent (stat store). Owns movement
## speed, attack scaling, and all health numbers; states and upgrades read and
## write it directly.
@export var attribute_component: AttributeComponent
## Reference to the character's KnockbackComponent.
@export var knockback_component: KnockbackComponent
## Reference to the character's AnimationTree.
@export var animation_tree: AnimationTree
## Physical body StateMachine.
@export var state_machine: StateMachine
## Optional AI StateMachine (Mind) for AI-controlled characters.
@export var ai_state_machine: AIStateMachine
## Optional NavigationAgent3D for pathfinding.
@export var navigation_agent_3d: NavigationAgent3D
## Automatically configures NavigationAgent3D height offset and waypoint distances
## based on the character's collision shape dimensions.
@export var auto_configure_navigation: bool = true
## Primary collision shape of this character body.
@export var collision_shape_3d: CollisionShape3D
## Optional Area3D weapon hitbox for melee attacks.
@export var weapon_hitbox: Area3D
## The Hurtbox that takes this character's hits (required).
@export var hurtbox: Hurtbox
## Optional CharacterColorComponent for palette recoloring and tints.
@export var color_component: CharacterColorComponent
## State entered when this character is damaged / stunned.
@export var stun_state: State
## State entered when this character is defeated.
@export var defeat_state: State
## Optional EquipmentComponent for inventory and gear management.
@export var equipment_component: EquipmentComponent
## Optional AbilitySystemComponent (ASC) holding every ability this character
## has: its active ability slots and its granted passives. Ability states
## broadcast lifecycle events to it via broadcast_ability_event.
@export var ability_system_component: AbilitySystemComponent
## The EnemyResource this enemy was spawned from (gold drop, archetype data).
## Waves set it; an enemy spawned any other way is looked up in
## GlobalVars.enemies by its scene.
@export var enemy_resource: EnemyResource
## Optional cooldown timer preventing dash spamming. Wired on the player;
## characters without one (enemies) are always ready and rely on AI gating.
@export var dash_cooldown: Timer

## Minimum outward drift speed enforced while the player is supported by an
## enemy head. Applied every contact frame as retry velocity and banked as
## distance, so neither standing still nor steering back onto the crown can
## balance on the apex. Normal top contacts keep their impact momentum
## untouched (wall-like); this only guarantees the slide-off.
@export var head_slide_speed: float = 1.5
## Seconds this character takes to brake from full movement speed to a stop
## once it has no movement intent (0.0 = instant). Faster leftover motion
## (e.g. after a dash) brakes at the same rate. Time-based, so braking is the
## same at any physics tick rate; the default matches one 60 Hz tick.
@export var stop_time: float = 1.0 / 60.0


## Desired movement direction vector (normalized), provided by PlayerInputComponent or AIStateMachine.
var move_direction: Vector3 = Vector3.ZERO
## Aim direction vector in 3D world space.
var aim_direction: Vector3 = Vector3.ZERO
## Target position in 3D world space for facing orientation (used when idle).
var face_target: Vector3 = Vector3.ZERO
## Edge-triggered attack request, raised by either controller (PlayerInputComponent
## polling or AIStateMachine commands) and consumed exactly once by body states.
var attack_requested: bool = false
## Edge-triggered dash request, raised by either controller (PlayerInputComponent
## polling or AIStateMachine commands) and consumed exactly once by body states.
var dash_requested: bool = false
## Edge-triggered jump request, raised by PlayerInputComponent (or AI) and consumed exactly once by body states.
var jump_requested: bool = false
## Edge-triggered ability request: the slot index to cast, -1 for none. Raised
## by PlayerInputComponent and consumed exactly once by body states
## (CharacterState.check_ability()).
var ability_requested: int = -1
## Current target for attacks and the player reticle. Null when no valid
## target exists. Written through set_current_target() (by the player's
## TargetingComponent); read by attack states and projectiles.
var current_target: Node3D = null
## True while the body StateMachine is inside an attack state. Set by
## CharacterAction enter/exit (attacks and ability casts); while true the
## auto-aim target never changes (a plain bool avoids a static CharacterAction
## reference cycle here).
var is_attacking: bool = false

var _is_defeated: bool = false
## True once move_character() has slid the body, so floor state is real (see
## has_moved()).
var _movement_updated: bool = false

## Whether this character has been alerted to player presence. Defaults to true.
var is_alerted: bool = true
## Home spawn area bounding idle patrol.
var home_spawn_area: RoomSpawnArea = null
## Home world position where this character spawned.
var home_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_check_wiring()
	if equipment_component != null:
		equipment_component.character = self
	if ability_system_component != null:
		ability_system_component.character = self
	_auto_configure_navigation()
	_connect_combat_signals()


## Reports every required reference the scene left unwired, so a
## misconfigured character fails loudly instead of limping along. Enemies
## also need a stun and a defeat state to react to hits.
func _check_wiring() -> void:
	var required: Dictionary[String, Object] = {
		"state_machine": state_machine,
		"attribute_component": attribute_component,
		"knockback_component": knockback_component,
		"collision_shape_3d": collision_shape_3d,
		"hurtbox": hurtbox,
		"mesh_mount": mesh_mount,
		"animation_tree": animation_tree,
	}
	if is_enemy():
		required["stun_state"] = stun_state
		required["defeat_state"] = defeat_state
	for export_name: String in required:
		if required[export_name] == null:
			push_error("Character '%s': %s is not set." % [name, export_name])


## Wires defeat, hit reactions, and every attack component this character
## owns.
func _connect_combat_signals() -> void:
	if attribute_component != null:
		if not attribute_component.defeat.is_connected(_on_attribute_defeat):
			attribute_component.defeat.connect(_on_attribute_defeat)
	if hurtbox != null and not hurtbox.struck.is_connected(_on_hurtbox_struck):
		hurtbox.struck.connect(_on_hurtbox_struck)
	# Every attack component this character owns (the weapon's included)
	# reports its hits as this character's hit_landed. Its own hurtbox is
	# never a target: AttackComponent skips its wielder's hurtbox.
	for component: AttackComponent in find_children("*", "AttackComponent"):
		component.hit_landed.connect(_on_attack_component_hit_landed.bind(component))


## Calibrates NavigationAgent3D parameters to match this character's collision shape.
## Offsets waypoints vertically to cancel 3D Euclidean distance inflation for tall agents,
## and scales path desired distance to the character's radius for clean corner rounding.
func _auto_configure_navigation() -> void:
	if not auto_configure_navigation or navigation_agent_3d == null:
		return
	var size: Vector2 = get_body_size()
	if size.is_zero_approx():
		return
	var radius: float = size.x
	var origin_height: float = get_origin_height()
	navigation_agent_3d.radius = radius
	navigation_agent_3d.path_height_offset = -maxf(0.0, origin_height - NAV_SURFACE_ELEVATION)
	navigation_agent_3d.path_desired_distance = clampf(radius + PATH_DISTANCE_MARGIN, PATH_DISTANCE_MIN, PATH_DISTANCE_MAX)
	navigation_agent_3d.target_desired_distance = maxf(TARGET_DISTANCE_MIN, radius + TARGET_DISTANCE_MARGIN)


## This body's collision size as (radius, height), read from
## collision_shape_3d (capsule, cylinder or box). Vector2.ZERO when the shape
## is missing or of another type.
func get_body_size() -> Vector2:
	if collision_shape_3d == null or collision_shape_3d.shape == null:
		return Vector2.ZERO
	var shape: Shape3D = collision_shape_3d.shape
	if shape is CapsuleShape3D:
		var cap: CapsuleShape3D = shape as CapsuleShape3D
		return Vector2(cap.radius, cap.height)
	if shape is CylinderShape3D:
		var cyl: CylinderShape3D = shape as CylinderShape3D
		return Vector2(cyl.radius, cyl.height)
	if shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		return Vector2(maxf(box.size.x, box.size.z) * 0.5, box.size.y)
	return Vector2.ZERO


## Height of this body's origin above the bottom of its collision shape (its
## feet), in meters. 0.0 when get_body_size() does not know the shape.
func get_origin_height() -> float:
	var size: Vector2 = get_body_size()
	if size.is_zero_approx():
		return 0.0
	return size.y * 0.5 - collision_shape_3d.position.y


## Speed, in m/s, this character sheds per second (on each horizontal axis)
## while braking with no movement intent at movement speed move_speed: it
## stops from move_speed in stop_time. INF when stop_time is 0 (instant stop).
func get_braking_rate(move_speed: float) -> float:
	return INF if stop_time <= 0.0 else move_speed / stop_time


## Horizontal distance, in meters, this character slides while braking from
## from_velocity to a stop at movement speed move_speed, integrated per
## physics tick exactly as CharacterState.core_movement() brakes (each axis
## on its own). 0.0 when the braking is instant or never slows it down.
func get_braking_distance(from_velocity: Vector3, move_speed: float) -> float:
	var rate: float = get_braking_rate(move_speed)
	if is_inf(rate) or rate <= 0.0:
		return 0.0
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	var slide: Vector2 = Vector2(from_velocity.x, from_velocity.z)
	var distance: float = 0.0
	while not slide.is_zero_approx():
		slide = Vector2(move_toward(slide.x, 0.0, rate * delta), move_toward(slide.y, 0.0, rate * delta))
		distance += slide.length() * delta
	return distance


## Moves normally, except enemy tops are never usable floors for the player.
## A top contact behaves like hitting a wall: the impact momentum is kept
## as-is (no bounce, no launch), and the step is retried in floating mode so
## Godot clears its floor flag while the surface still blocks the fall. The
## retry strips any steering back onto the crown and enforces a minimum
## outward drift (also banked as distance, since next frame's input re-derives
## velocity), so the apex is an unstable perch the player always slides off,
## whether dropping neutrally, parked with zero momentum, or steering inward.
## Side collisions and terrain slopes are untouched.
func move_character() -> bool:
	_movement_updated = true
	var start_transform: Transform3D = global_transform
	var intended_velocity: Vector3 = velocity
	var collided: bool = move_and_slide()
	if not is_player():
		return collided
	var enemy: Character = _get_enemy_head_support()
	if enemy == null:
		return collided
	_slide_off_enemy_head(enemy, start_transform, intended_velocity)
	return true


## Redoes this frame's step from start_transform as if the enemy's head were a
## wall: floating mode, no steering back onto the crown, and a minimum outward
## drift (see move_character).
func _slide_off_enemy_head(enemy: Character, start_transform: Transform3D, intended_velocity: Vector3) -> void:
	var support_normal: Vector3 = get_floor_normal()
	if support_normal.is_zero_approx():
		support_normal = up_direction
	global_transform = start_transform
	# Lift out of margin contact first: starting the sweep while touching
	# makes move_and_slide spend its step on penetration recovery and skip
	# the actual motion, wedging the player against the surface.
	global_position += support_normal * HEAD_SLIDE_LIFT
	var outward: Vector3 = (global_position - enemy.global_position).slide(up_direction)
	if outward.is_zero_approx():
		outward = intended_velocity.slide(up_direction)
	if outward.is_zero_approx():
		outward = Vector3.RIGHT
	outward = outward.normalized()
	# Strip steering back onto the crown and enforce minimum outward drift, so
	# holding toward the head cannot balance on the apex from frame to frame.
	var flat: Vector3 = Vector3(intended_velocity.x, 0.0, intended_velocity.z)
	flat += outward * maxf(0.0, flat.dot(outward * -1.0))
	flat += outward * maxf(0.0, head_slide_speed - flat.dot(outward))
	# Keep falling (never rest or launch) so landing checks stay airborne.
	velocity = Vector3(flat.x, minf(intended_velocity.y, -HEAD_SLIDE_FALL_SPEED), flat.z)
	var saved_mode: MotionMode = motion_mode
	motion_mode = MOTION_MODE_FLOATING
	move_and_slide()
	motion_mode = saved_mode
	# Bank the drift as distance: velocity is re-derived from input next frame,
	# so a velocity-only push would be erased before it ever moves the body.
	global_position += outward * head_slide_speed * get_physics_process_delta_time()
	if velocity.y > -HEAD_SLIDE_FALL_SPEED:
		velocity.y = -HEAD_SLIDE_FALL_SPEED


## Returns the enemy currently supporting the player from below, or null.
## Checks top-like slide contacts first, then a short downward probe that
## covers snap-held rests with no fresh slide.
func _get_enemy_head_support() -> Character:
	if not is_on_floor():
		return null
	for index: int in range(get_slide_collision_count()):
		var contact: KinematicCollision3D = get_slide_collision(index)
		var contact_enemy: Character = contact.get_collider() as Character
		if contact_enemy == null or not contact_enemy.is_enemy():
			continue
		if contact.get_normal().dot(up_direction) < cos(floor_max_angle):
			continue
		return contact_enemy
	var probe: KinematicCollision3D = KinematicCollision3D.new()
	if test_move(global_transform, Vector3.DOWN * 0.12, probe):
		var under: Character = probe.get_collider() as Character
		if under != null and under.is_enemy() and probe.get_normal().dot(up_direction) >= cos(floor_max_angle):
			return under
	return null


## Sets current_target, emitting target_changed only on a real change.
func set_current_target(new_target: Node3D) -> void:
	if new_target == current_target:
		return
	current_target = new_target
	target_changed.emit(new_target)


## True once move_character() has slid the body at least once, so its floor
## state is real: is_on_floor() is false before the first move_and_slide.
func has_moved() -> bool:
	return _movement_updated


## Returns true if the character is alive (attribute health pool above zero and
## not defeated). Health values live in the AttributeComponent alone.
func is_alive() -> bool:
	if _is_defeated:
		return false
	if attribute_component != null and is_instance_valid(attribute_component):
		return attribute_component.is_alive()
	return true


## Returns true if this character has the specified gameplay tag.
func has_tag(tag: StringName) -> bool:
	if attribute_component != null and is_instance_valid(attribute_component):
		return attribute_component.has_tag(tag)
	return false


## Returns true if this character has all specified gameplay tags.
func has_all_tags(tags: Array[StringName]) -> bool:
	if attribute_component != null and is_instance_valid(attribute_component):
		return attribute_component.has_all_tags(tags)
	return tags.is_empty()


## Returns true if this character has any of the specified gameplay tags.
func has_any_tag(tags: Array[StringName]) -> bool:
	if attribute_component != null and is_instance_valid(attribute_component):
		return attribute_component.has_any_tag(tags)
	return false


## Adds one count of the specified gameplay tag.
func add_tag(tag: StringName) -> void:
	if attribute_component != null and is_instance_valid(attribute_component):
		attribute_component.add_tag(tag)


## Removes one count of the specified gameplay tag.
func remove_tag(tag: StringName) -> void:
	if attribute_component != null and is_instance_valid(attribute_component):
		attribute_component.remove_tag(tag)


## Forwards an ability lifecycle event to this character's
## AbilitySystemComponent so granted passives can react to tagged abilities.
## No-op when no component is attached.
func broadcast_ability_event(event: AbilityEvent) -> void:
	if ability_system_component != null and is_instance_valid(ability_system_component):
		ability_system_component.notify_ability_event(event)


## Returns all currently active gameplay tags.
func get_tags() -> Array[StringName]:
	if attribute_component != null and is_instance_valid(attribute_component):
		return attribute_component.get_tags()
	return []


## Requests facing toward the given desired direction. The actual rotation only
## ever advances toward it by at most get_rotation_speed() * delta, so every
## caller (movement, AI auto-aim, attack aiming) merely sets intent while this
## function enforces the speed limit. Dead characters never rotate.
func look_toward_direction(direction: Vector3, delta: float) -> void:
	if not is_alive() or mesh_mount == null:
		return
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.is_zero_approx():
		return
	_rotate_mount_toward(flat.normalized(), delta)


## Requests facing toward the given target position on the XZ plane. Like
## look_toward_direction this never snaps: one call advances the actual
## rotation by the speed limit for delta only, so single calls from state
## enter() paths or timer callbacks turn by a single step while per-frame
## callers converge over successive frames. Dead characters never rotate.
func look_at_target(target: Vector3, delta: float) -> void:
	if not is_alive() or mesh_mount == null:
		return
	var to_target: Vector3 = target - mesh_mount.global_position
	to_target.y = 0.0
	if to_target.is_zero_approx():
		return
	_rotate_mount_toward(to_target.normalized(), delta)


## Returns the rotation speed limit in degrees per second (360.0 = one full
## turn per second). Reads the rotation_speed stat live so modifiers apply;
## clamps at zero so stacked slow effects hold facing instead of reversing it.
func get_rotation_speed() -> float:
	if attribute_component != null and is_instance_valid(attribute_component):
		return maxf(0.0, attribute_component.get_current(AttributeComponent.STAT_ROTATION_SPEED))
	return DEFAULT_ROTATION_SPEED


## Yaw-rotates the mesh_mount toward the normalized XZ desired direction by at
## most the speed limit for delta, taking the shortest arc. Rotating the
## existing basis (instead of rebuilding it via looking_at) preserves the
## mount scale and origin by construction.
func _rotate_mount_toward(desired: Vector3, delta: float) -> void:
	var mount_basis: Basis = mesh_mount.global_transform.basis
	var forward: Vector3 = Vector3(mount_basis.z.x, 0.0, mount_basis.z.z)
	if forward.is_zero_approx():
		return
	forward = forward.normalized()
	var signed_angle: float = atan2(forward.cross(desired).y, forward.dot(desired))
	var max_step: float = deg_to_rad(get_rotation_speed()) * maxf(delta, 0.0)
	var step: float = clampf(signed_angle, -max_step, max_step)
	if is_zero_approx(step):
		return
	var keep_scale: Vector3 = mount_basis.get_scale()
	var turned: Basis = (Basis(Vector3.UP, step) * mount_basis).orthonormalized().scaled(keep_scale)
	mesh_mount.global_transform = Transform3D(turned, mesh_mount.global_transform.origin)


## Returns the damage scaling modifier (attack stat / 100.0).
func get_damage_modifier() -> float:
	if attribute_component != null and is_instance_valid(attribute_component):
		return attribute_component.get_current(AttributeComponent.STAT_ATTACK) / 100.0
	return 1.0


## Returns true if the dash ability is currently off cooldown.
## A null timer means always ready (enemies rely on AI gating instead).
func can_dash() -> bool:
	return dash_cooldown == null or dash_cooldown.is_stopped()


## Whether a controller may order the body into target_state now: never while
## dead, already in target_state, or in a state that refuses orders (see
## CharacterState.accepts_orders()); out of stun_state only when
## can_break_stun.
func can_accept_order(target_state: CharacterState, can_break_stun: bool = false) -> bool:
	if target_state == null or not is_alive() or state_machine == null or state_machine.state == null:
		return false
	var current: State = state_machine.state
	if current == target_state:
		return false
	if current is CharacterState and not (current as CharacterState).accepts_orders():
		return false
	return can_break_stun or current != stun_state


## Consumes a pending attack request, returning true exactly once per request.
func consume_attack_request() -> bool:
	if not attack_requested:
		return false
	attack_requested = false
	return true


## Consumes a pending dash request, returning true exactly once per request.
func consume_dash_request() -> bool:
	if not dash_requested:
		return false
	dash_requested = false
	return true


## Consumes a pending ability request, returning its slot exactly once per
## request (-1 when none is pending).
func consume_ability_request() -> int:
	var slot: int = ability_requested
	ability_requested = -1
	return slot


## Consumes a pending jump request, returning true exactly once per request.
func consume_jump_request() -> bool:
	if not jump_requested:
		return false
	jump_requested = false
	return true


## Returns true if this character is in the "player" group.
func is_player() -> bool:
	return is_in_group("player")


## Returns true if this character is in the "enemy" group.
func is_enemy() -> bool:
	return is_in_group("enemy")


## Returns the opposing team group name ("enemy" for player, "player" for enemy).
func get_opposing_group() -> String:
	return "enemy" if is_player() else "player"


## Finds the nearest alive Character in the specified group (or opposing group by default).
func get_nearest_target(group_name: String = "") -> Character:
	var target_group: String = group_name if not group_name.is_empty() else get_opposing_group()
	var nodes: Array[Node] = get_tree().get_nodes_in_group(target_group)
	var closest_char: Character = null
	var min_distance_sq: float = INF
	for node: Node in nodes:
		if node == self or not (node is Character):
			continue
		var target_char: Character = node as Character
		if not target_char.is_alive():
			continue
		var dist_sq: float = global_position.distance_squared_to(target_char.global_position)
		if dist_sq < min_distance_sq:
			min_distance_sq = dist_sq
			closest_char = target_char
	return closest_char


## Returns true if this character is executing an uninterruptable attack or ability (hyper-armor).
func is_uninterruptable() -> bool:
	return state_machine != null and state_machine.state is CharacterState and (state_machine.state as CharacterState).is_uninterruptable()


## Reacts to being struck: forwards the current health pool as health_changed
## (drives the damage flash and hurt shake) and enters the stun state. Fires
## once per landed hit because only Hurtbox.receive_hit() emits struck;
## damage-over-time ticks drain the pool silently, so a burn can never
## re-stun its victim or pin the damage flash on for its whole duration.
func _on_hurtbox_struck(_damage: float) -> void:
	# A lethal hit reports defeat (via damage_pool) before struck reaches here;
	# the dead must ignore reactions or stun would override the defeat state.
	if not is_alive():
		return
	alert()
	if attribute_component != null:
		health_changed.emit(attribute_component.get_current(AttributeComponent.POOL_HEALTH))
	if is_uninterruptable():
		return
	if stun_state != null and state_machine != null and state_machine.state != null:
		state_machine.state.finished.emit(stun_state.name)


## Alerts this character into active combat pursuit.
func alert() -> void:
	if is_alerted:
		return
	is_alerted = true
	alerted.emit()
	if ai_state_machine != null:
		ai_state_machine.alert()


## Cancels all transient movement, ability, and combat status state: motion vectors,
## pending intents, knockback momentum, the auto-aim lock, the attacking flag, live
## weapon hitboxes, active weapon VFX modes, any active dash/attack/fall body state
## (returned to the machine's home state via its normal exit path, so attack timers,
## lunges, and hitstop are cleaned up), all in-flight character SFX (dash, damage,
## attack, footsteps), and all temporary status effects (fire/burn DoTs, timed stat
## modifiers, status visual effects). Components holding other transient
## feedback (the damage vignette, camera shake trauma) reset it on
## transient_state_cancelled.
## Called when this character is carried into a new level so no dash, attack, sound,
## red flash, camera shake, or fire leak across the transition.
func cancel_movement_and_abilities() -> void:
	_clear_intents_and_motion()
	if knockback_component != null:
		knockback_component.magnitude = Vector3.ZERO
	if state_machine != null and state_machine.state != null:
		var home: State = state_machine.initial_state
		if home == null and state_machine.get_child_count() > 0:
			home = state_machine.get_child(0) as State
		if home != null and state_machine.state != home:
			state_machine.request_state(home.name)
	_silence_weapons_and_sounds()
	if attribute_component != null:
		# Also frees every status visual (burning fire, ...): the component
		# tracks the visual of each effect it applied.
		attribute_component.clear_temporary_effects()
	transient_state_cancelled.emit()


## Drops every pending intent, the aim and facing requests, the auto-aim
## target and the attacking flag, and stops the body.
func _clear_intents_and_motion() -> void:
	move_direction = Vector3.ZERO
	aim_direction = Vector3.ZERO
	face_target = Vector3.ZERO
	attack_requested = false
	dash_requested = false
	jump_requested = false
	ability_requested = -1
	is_attacking = false
	set_current_target(null)
	velocity = Vector3.ZERO


## Closes every weapon hit window and trail and stops every character sound.
func _silence_weapons_and_sounds() -> void:
	for slot: Node in find_children("*", "WeaponSlot"):
		if slot is WeaponSlot:
			var ws: WeaponSlot = slot as WeaponSlot
			ws.enabled = false
			ws.attack_mode = WeaponSlot.mode.NONE
			ws.vfx_threshold = 1.0
	for audio_3d: Node in find_children("*", "AudioStreamPlayer3D"):
		(audio_3d as AudioStreamPlayer3D).stop()
	for audio_2d: Node in find_children("*", "AudioStreamPlayer"):
		(audio_2d as AudioStreamPlayer).stop()


## Centralized idempotent defeat handler: emits defeat (components react to it:
## the player's input stops, an enemy's loot is awarded, the game-over flow
## starts), halts motion and the AI, and enters the defeat state.
func on_defeat() -> void:
	if _is_defeated:
		return
	_is_defeated = true
	defeat.emit()
	_clear_intents_and_motion()
	if ai_state_machine != null:
		ai_state_machine.command_stop()
		ai_state_machine.set_physics_process(false)
	if defeat_state != null and state_machine != null and state_machine.state != null:
		state_machine.state.finished.emit(defeat_state.name)
	_switch_corpse_off()


## Shuts off the body shape, so the corpse never blocks movement (the hurtbox
## switches itself off on defeat, see Hurtbox). It still rests where it fell:
## the defeat states pin velocity to zero every frame.
func _switch_corpse_off() -> void:
	if collision_shape_3d != null:
		collision_shape_3d.set_deferred("disabled", true)


func _on_attribute_defeat() -> void:
	on_defeat()


func _on_attack_component_hit_landed(target: Node, attack_comp: AttackComponent) -> void:
	hit_landed.emit(target, attack_comp)
