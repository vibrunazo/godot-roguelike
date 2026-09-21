## Unified base class for all characters (Player and Enemies).
## Distinguishes team and role via attached components and assigned groups ("player" vs "enemy").
class_name Character
extends CharacterBody3D

## Emitted when this character's health reaches zero.
signal defeat

## Emitted when this character's health changes.
signal health_changed(value: float)

## Emitted when the auto-aim target changes (including clearing to null).
signal target_changed(new_target: Node3D)

## Emitted when an attack belonging to this character lands a hit on a target.
signal hit_landed(target: Node, attack_component: AttackComponent)

## Emitted when this character is alerted into active combat.
signal alerted

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
## Primary collision shape of this character body.
@export var collision_shape_3d: CollisionShape3D
## Optional Area3D weapon hitbox for melee attacks.
@export var weapon_hitbox: Area3D
## Optional Hurtbox for taking damage.
@export var hurtbox: Hurtbox
## Optional CharacterColorComponent for palette recoloring and tints.
@export var color_component: CharacterColorComponent
## State entered when this character is damaged / stunned.
@export var stun_state: State
## State entered when this character is defeated.
@export var defeat_state: State
## Optional EquipmentComponent for inventory and gear management.
@export var equipment_component: EquipmentComponent
## Optional EnemyResource defining enemy archetype properties (such as gold drop).
@export var enemy_resource: EnemyResource
## Optional cooldown timer preventing dash spamming. Wired on the player;
## characters without one (enemies) are always ready and rely on AI gating.
@export var dash_cooldown: Timer
## Maximum distance in meters at which auto-aim acquires opposing characters.
## Values <= 0.0 disable auto-aim acquisition entirely (0.0 by default for AI enemies; enabled by PlayerInputComponent).
@export var auto_aim_range: float = 0.0
## Minimum interval in seconds between auto-aim target re-evaluations, so the
## target does not flicker every tick when candidates sit at similar distances.
@export var target_retarget_cooldown: float = 0.3


## Minimum outward drift speed enforced while the player is supported by an
## enemy head. Applied every contact frame as retry velocity and banked as
## distance, so neither standing still nor steering back onto the crown can
## balance on the apex. Normal top contacts keep their impact momentum
## untouched (wall-like); this only guarantees the slide-off.
@export var head_slide_speed: float = 1.5


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
## Current auto-aim target for attacks and the player reticle. Null when no
## valid target exists. Written by the auto-aim tick; read by attack states.
var current_target: Node3D = null
## True while the body StateMachine is inside an attack state. Set by
## CharacterAttack enter/exit; while true the auto-aim target never changes
## (a plain bool avoids a static CharacterAttack reference cycle here).
var is_attacking: bool = false

var _is_defeated: bool = false
## Time in seconds until the next allowed auto-aim re-evaluation.
var _retarget_timer: float = 0.0

## Whether this character has been alerted to player presence. Defaults to true.
var is_alerted: bool = true
## Home spawn area bounding idle patrol.
var home_spawn_area: Node3D = null
## Home world position where this character spawned.
var home_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	if attribute_component == null:
		attribute_component = get_node_or_null("AttributeComponent") as AttributeComponent
	if attribute_component == null:
		for child: Node in get_children():
			if child is AttributeComponent:
				attribute_component = child as AttributeComponent
				break
	if knockback_component == null:
		knockback_component = get_node_or_null("KnockbackComponent") as KnockbackComponent
	if state_machine == null:
		state_machine = get_node_or_null("StateMachine") as StateMachine
	if ai_state_machine == null:
		ai_state_machine = get_node_or_null("AIStateMachine") as AIStateMachine
	if navigation_agent_3d == null:
		navigation_agent_3d = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if collision_shape_3d == null:
		collision_shape_3d = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if hurtbox == null:
		hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if dash_cooldown == null:
		dash_cooldown = get_node_or_null("DashCooldown") as Timer
	if mesh_mount == null:
		mesh_mount = get_node_or_null("AnimationAnchor") as Node3D
		if mesh_mount == null:
			mesh_mount = get_node_or_null("GamedevTV_Mannequin_Medium") as Node3D
	if animation_tree == null:
		animation_tree = find_child("AnimationTree", true, false) as AnimationTree
	if equipment_component == null:
		equipment_component = get_node_or_null("EquipmentComponent") as EquipmentComponent
	if equipment_component == null:
		for child: Node in get_children():
			if child is EquipmentComponent:
				equipment_component = child as EquipmentComponent
				break
	if equipment_component != null:
		equipment_component.character = self
	if is_enemy():
		if stun_state == null:
			push_warning("Character '%s' in 'enemy' group has no stun_state assigned." % name)
		if defeat_state == null:
			push_warning("Character '%s' in 'enemy' group has no defeat_state assigned." % name)

	if attribute_component != null:
		if not attribute_component.defeat.is_connected(_on_attribute_defeat):
			attribute_component.defeat.connect(_on_attribute_defeat)
		if is_player() and not attribute_component.defeat.is_connected(reset_game_state):
			attribute_component.defeat.connect(reset_game_state)
	if hurtbox != null:
		if not hurtbox.struck.is_connected(_on_hurtbox_struck):
			hurtbox.struck.connect(_on_hurtbox_struck)

	if weapon_hitbox != null:
		var att_comp: AttackComponent = weapon_hitbox.get_node_or_null("AttackComponent") as AttackComponent
		if att_comp != null:
			att_comp.add_exception(self)
			if not att_comp.hit_landed.is_connected(_on_attack_component_hit_landed):
				att_comp.hit_landed.connect(_on_attack_component_hit_landed.bind(att_comp))
	for ac: AttackComponent in find_children("*", "AttackComponent"):
		ac.add_exception(self)
		if not ac.hit_landed.is_connected(_on_attack_component_hit_landed):
			ac.hit_landed.connect(_on_attack_component_hit_landed.bind(ac))


func _physics_process(delta: float) -> void:
	if auto_aim_range > 0.0:
		_update_auto_aim(delta)


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
	var start_transform: Transform3D = global_transform
	var intended_velocity: Vector3 = velocity
	var collided: bool = move_and_slide()
	if not is_player():
		return collided
	var enemy: Character = _get_enemy_head_support()
	if enemy == null:
		return collided
	var support_normal: Vector3 = get_floor_normal()
	if support_normal.is_zero_approx():
		support_normal = up_direction
	global_transform = start_transform
	# Lift out of margin contact first: starting the sweep while touching
	# makes move_and_slide spend its step on penetration recovery and skip
	# the actual motion, wedging the player against the surface.
	global_position += support_normal * 0.01
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
	velocity = Vector3(flat.x, minf(intended_velocity.y, -0.5), flat.z)
	var saved_mode: MotionMode = motion_mode
	motion_mode = MOTION_MODE_FLOATING
	move_and_slide()
	motion_mode = saved_mode
	# Bank the drift as distance: velocity is re-derived from input next frame,
	# so a velocity-only push would be erased before it ever moves the body.
	global_position += outward * head_slide_speed * get_physics_process_delta_time()
	if velocity.y > -0.5:
		velocity.y = -0.5
	return true


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


## Advances auto-aim: drops invalid targets. If no target is currently held,
## checks for a new target every tick to ensure immediate acquisition. Once a
## target is acquired, enforces target_retarget_cooldown before switching targets
## to prevent flicker between candidates at similar distances. Never changes the
## target while an attack is running (covers combo chains, which stay inside attack
## states), except clearing a freed node to avoid holding a dangling reference.
func _update_auto_aim(delta: float) -> void:
	if auto_aim_range <= 0.0 or not is_inside_tree() or not is_alive():
		return
	if is_attacking:
		if current_target != null and not is_instance_valid(current_target):
			_set_current_target(null)
		return
	if not _is_current_target_valid():
		_set_current_target(null)

	if current_target == null:
		var nearest: Character = get_nearest_target()
		if nearest != null and global_position.distance_to(nearest.global_position) <= auto_aim_range:
			_set_current_target(nearest)
			_retarget_timer = target_retarget_cooldown
		return

	_retarget_timer -= delta
	if _retarget_timer > 0.0:
		return
	_retarget_timer = target_retarget_cooldown
	var candidate: Character = get_nearest_target()
	if candidate != null and global_position.distance_to(candidate.global_position) <= auto_aim_range:
		_set_current_target(candidate)


## Returns true when the current target is still a usable aim point: a live
## node within auto-aim range (Characters must additionally be alive).
func _is_current_target_valid() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false
	if current_target is Character and not (current_target as Character).is_alive():
		return false
	if global_position.distance_to(current_target.global_position) > auto_aim_range:
		return false
	return true


## Resets the retarget cooldown so the next physics tick re-evaluates the
## target immediately. Used by tests and event-driven retarget triggers.
func force_retarget() -> void:
	_retarget_timer = 0.0


## Assigns the auto-aim target, emitting target_changed only on real changes.
## Tracks the new target's death (and untracks the old one) so a kill drops
## the corpse at once instead of lingering until the next tick.
func _set_current_target(new_target: Node3D) -> void:
	if new_target == current_target:
		return
	_disconnect_target_death()
	current_target = new_target
	_connect_target_death()
	if new_target == null:
		_retarget_timer = 0.0
	target_changed.emit(new_target)


## Watches the current target's death signal when it is a Character, so the
## kill clears synchronously. Non-Character targets have no death signal and
## stay covered by the per-tick validity check.
func _connect_target_death() -> void:
	if current_target != null and is_instance_valid(current_target) and current_target is Character:
		var target_char: Character = current_target as Character
		if not target_char.defeat.is_connected(_on_target_defeat):
			target_char.defeat.connect(_on_target_defeat)


## Stops watching the previous target. Safe against already-freed targets.
func _disconnect_target_death() -> void:
	if current_target != null and is_instance_valid(current_target) and current_target is Character:
		var target_char: Character = current_target as Character
		if target_char.defeat.is_connected(_on_target_defeat):
			target_char.defeat.disconnect(_on_target_defeat)


## Drops a killed target the same frame it dies and re-arms immediate
## re-evaluation, so the next tick outside an attack acquires a living
## replacement without waiting out the retarget cooldown. Dead nodes are
## never valid targets, even while still sitting in the level.
func _on_target_defeat() -> void:
	_set_current_target(null)
	_retarget_timer = 0.0


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


## Returns all currently active gameplay tags.
func get_tags() -> Array[StringName]:
	if attribute_component != null and is_instance_valid(attribute_component):
		return attribute_component.get_tags()
	return []


## Fallback rotation speed in degrees per second when no AttributeComponent is
## attached. Mirrors AttributeComponent.base_rotation_speed.
const DEFAULT_ROTATION_SPEED: float = 360.0


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


## Seconds between player defeat and the game-over screen, letting the death
## animation and corpse read before the menu takes over.
const DEFEAT_MENU_DELAY: float = 2.0


## Shows the game-over screen shortly after player defeat instead of
## reloading instantly. The run itself resets only when restart is chosen
## from the menu.
func reset_game_state() -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(DEFEAT_MENU_DELAY).timeout
	if not is_inside_tree():
		return
	UI.show_game_over()


## Returns true if this character is executing an uninterruptable attack or ability (hyper-armor).
func is_uninterruptable() -> bool:
	if state_machine != null and state_machine.state is CharacterAttack:
		return (state_machine.state as CharacterAttack).uninterruptable
	if state_machine != null and state_machine.state != null:
		var unintr: Variant = state_machine.state.get("uninterruptable")
		if unintr != null and bool(unintr):
			return true
	return false


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
## attack, footsteps), the damage vignette flash, camera shake trauma, and all
## temporary status effects (fire/burn DoTs, timed stat modifiers, status visual effects).
## Called when this character is carried into a new level so no dash, attack, sound,
## red flash, camera shake, or fire leak across the transition.
func cancel_movement_and_abilities() -> void:
	move_direction = Vector3.ZERO
	aim_direction = Vector3.ZERO
	face_target = Vector3.ZERO
	attack_requested = false
	dash_requested = false
	jump_requested = false
	is_attacking = false
	_set_current_target(null)
	velocity = Vector3.ZERO
	if knockback_component != null:
		knockback_component.magnitude = Vector3.ZERO
	if state_machine != null and state_machine.state != null:
		var home: State = state_machine.initial_state
		if home == null and state_machine.get_child_count() > 0:
			home = state_machine.get_child(0) as State
		if home != null and state_machine.state != home:
			state_machine.request_state(home.name)
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
	var input_comp: PlayerInputComponent = get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp != null:
		input_comp.cancel_damage_tint()
	else:
		var tint: ColorRect = get_node_or_null("DamageTint") as ColorRect
		if tint != null:
			tint.color = Color(Color.RED, 0.0)
	var camera: ShakeCamera3D = get_node_or_null("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	if camera != null:
		camera.trauma = 0.0
	if attribute_component != null:
		attribute_component.clear_temporary_effects()
	for child: Node in find_children("*", "Node3D", true, false):
		if child.name.begins_with("Status") or child.name.to_lower().contains("burning"):
			(child as Node3D).visible = false
			child.queue_free()



## Centralized idempotent defeat handler that halts motion, disables AI & input, and enters defeat state.
func on_defeat() -> void:
	if _is_defeated:
		return
	_is_defeated = true
	defeat.emit()

	if is_enemy() and ProgressionState != null:
		var gold: int = 5
		if enemy_resource != null:
			gold = enemy_resource.gold_drop
		elif GlobalVars != null and not scene_file_path.is_empty():
			for er: EnemyResource in GlobalVars.enemies:
				if er != null and er.scene != null and er.scene.resource_path == scene_file_path:
					gold = er.gold_drop
					break
		ProgressionState.add_gold(gold)
	move_direction = Vector3.ZERO
	aim_direction = Vector3.ZERO
	face_target = Vector3.ZERO
	jump_requested = false
	_set_current_target(null)
	is_attacking = false
	velocity = Vector3.ZERO
	if ai_state_machine != null:
		ai_state_machine.command_stop()
		ai_state_machine.set_physics_process(false)
		ai_state_machine.set_process_unhandled_input(false)
	var input_comp: PlayerInputComponent = get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp != null:
		input_comp.set_physics_process(false)
	if defeat_state != null and state_machine != null and state_machine.state != null:
		state_machine.state.finished.emit(defeat_state.name)
	# The body shape is shut off so corpses never block movement. They still
	# rest where they fell: the defeat states pin velocity to zero every frame.
	if collision_shape_3d != null:
		collision_shape_3d.set_deferred("disabled", true)
	if hurtbox != null:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
		var hurtbox_shape: CollisionShape3D = hurtbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if hurtbox_shape != null:
			hurtbox_shape.set_deferred("disabled", true)


func _on_attribute_defeat() -> void:
	on_defeat()


func _on_attack_component_hit_landed(target: Node, attack_comp: AttackComponent) -> void:
	hit_landed.emit(target, attack_comp)
