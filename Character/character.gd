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

## Base movement speed in meters per second.
@export var movement_speed: float = 8.0
## Exponential decay rate for orientation smoothing.
@export var decay: float = 12.0
## Overall damage percentage stat (default 100.0 = 100%).
@export var damage_stat: float = 100.0
## The visual mount node rotated to face movement or aim directions.
@export var mesh_mount: Node3D
## Reference to the character's HealthComponent.
@export var health_component: HealthComponent
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
## Optional cooldown timer preventing dash spamming. Wired on the player;
## characters without one (enemies) are always ready and rely on AI gating.
@export var dash_cooldown: Timer
## Maximum distance in meters at which auto-aim acquires opposing characters.
## Values <= 0.0 disable auto-aim acquisition entirely (0.0 by default for AI enemies; enabled by PlayerInputComponent).
@export var auto_aim_range: float = 0.0
## Minimum interval in seconds between auto-aim target re-evaluations, so the
## target does not flicker every tick when candidates sit at similar distances.
@export var target_retarget_cooldown: float = 0.3

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


func _ready() -> void:
	if health_component == null:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
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
	if is_enemy():
		if stun_state == null:
			push_warning("Character '%s' in 'enemy' group has no stun_state assigned." % name)
		if defeat_state == null:
			push_warning("Character '%s' in 'enemy' group has no defeat_state assigned." % name)

	if health_component != null:
		if not health_component.health_changed.is_connected(_on_health_component_health_changed):
			health_component.health_changed.connect(_on_health_component_health_changed)
		if not health_component.defeat.is_connected(_on_health_component_defeat):
			health_component.defeat.connect(_on_health_component_defeat)
		if is_player() and not health_component.defeat.is_connected(reset_game_state):
			health_component.defeat.connect(reset_game_state)

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


## Advances auto-aim: drops invalid targets, then re-evaluates the nearest
## opposing character within auto_aim_range at most every
## target_retarget_cooldown seconds. Never changes the target while an attack
## is running (covers combo chains, which stay inside attack states), except
## clearing a freed node to avoid holding a dangling reference.
func _update_auto_aim(delta: float) -> void:
	if auto_aim_range <= 0.0 or not is_inside_tree() or not is_alive():
		return
	if is_attacking:
		if current_target != null and not is_instance_valid(current_target):
			_set_current_target(null)
		return
	if not _is_current_target_valid():
		_set_current_target(null)
	_retarget_timer -= delta
	if _retarget_timer > 0.0:
		return
	_retarget_timer = target_retarget_cooldown
	var nearest: Character = get_nearest_target()
	if nearest != null and global_position.distance_to(nearest.global_position) <= auto_aim_range:
		_set_current_target(nearest)


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


## Returns true if the character is alive (current_health > 0 and not defeated).
func is_alive() -> bool:
	if _is_defeated:
		return false
	if health_component != null:
		return health_component.current_health > 0.0
	return true


## Smoothly rotates the mesh_mount towards the given direction using exponential decay.
func look_toward_direction(direction: Vector3, delta: float) -> void:
	if not is_alive() or direction.is_zero_approx() or mesh_mount == null:
		return
	var target_transform: Transform3D = mesh_mount.global_transform
	target_transform = target_transform.looking_at(mesh_mount.global_position + direction, Vector3.UP, true)
	mesh_mount.global_transform = mesh_mount.global_transform.interpolate_with(
		target_transform,
		1.0 - exp(-decay * delta)
	)


## Instantly points the mesh_mount towards the target position on the XZ plane.
func look_at_target(target: Vector3) -> void:
	if not is_alive() or mesh_mount == null:
		return
	var target_pos: Vector3 = target
	target_pos.y = mesh_mount.global_position.y
	if mesh_mount.global_position.is_equal_approx(target_pos):
		return
	mesh_mount.look_at(target_pos, Vector3.UP, true)


## Returns the damage scaling modifier (damage_stat / 100.0).
func get_damage_modifier() -> float:
	return damage_stat / 100.0


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
		if target_char.health_component != null and target_char.health_component.current_health <= 0.0:
			continue
		var dist_sq: float = global_position.distance_squared_to(target_char.global_position)
		if dist_sq < min_distance_sq:
			min_distance_sq = dist_sq
			closest_char = target_char
	return closest_char


## Resets game state and reloads level on player defeat.
func reset_game_state() -> void:
	ProgressionState.reset_run()
	if is_inside_tree():
		get_tree().reload_current_scene.call_deferred()


## Returns true if this character is executing an uninterruptable attack or ability (hyper-armor).
func is_uninterruptable() -> bool:
	if state_machine != null and state_machine.state is CharacterAttack:
		return (state_machine.state as CharacterAttack).uninterruptable
	if state_machine != null and state_machine.state != null:
		var unintr: Variant = state_machine.state.get("uninterruptable")
		if unintr != null and bool(unintr):
			return true
	return false


func _on_health_component_health_changed(value: float) -> void:
	health_changed.emit(value)
	if is_uninterruptable():
		return
	if stun_state != null and state_machine != null and state_machine.state != null:
		state_machine.state.finished.emit(stun_state.name)


## Centralized idempotent defeat handler that halts motion, disables AI & input, and enters defeat state.
func on_defeat() -> void:
	if _is_defeated:
		return
	_is_defeated = true
	defeat.emit()
	move_direction = Vector3.ZERO
	aim_direction = Vector3.ZERO
	face_target = Vector3.ZERO
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
	if collision_shape_3d != null:
		collision_shape_3d.set_deferred("disabled", true)
	if hurtbox != null:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
		var hurtbox_shape: CollisionShape3D = hurtbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if hurtbox_shape != null:
			hurtbox_shape.set_deferred("disabled", true)


func _on_health_component_defeat() -> void:
	on_defeat()


func _on_attack_component_hit_landed(target: Node, attack_comp: AttackComponent) -> void:
	hit_landed.emit(target, attack_comp)
