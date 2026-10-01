## Component that listens to user inputs and translates them into Character intents and actions.
class_name PlayerInputComponent
extends Node

## Most characters the mouse aim ray looks through before it gives up.
const AIM_RAY_MAX_CHARACTERS: int = 8

## The Character controlled by this input component.
@export var character: Character
## Fullscreen damage vignette/tint ColorRect.
@export var damage_tint: ColorRect
## Minimum dot product between the held movement direction and the direction
## towards the locked auto-aim target for a jump order to stay a jump. Lower
## alignment (sideways or backwards movement) turns the order into a dash.
@export var jump_dash_alignment: float = 0.5
## Desired landing offset in front of the locked target, in meters. The input
## controller sizes a forward jump's movement speed ratio so the leap lands
## this far short of the target, leaving room for the striking kick.
@export var jump_landing_gap: float = 1.0
## Minimum clamped movement speed ratio applied by the dynamic forward-jump
## sizing below (the jump always drifts at least this fast).
@export var min_forward_jump_ratio: float = 0.2
## Maximum clamped movement speed ratio applied by the dynamic forward-jump
## sizing below (the jump never exceeds full walk speed horizontally).
@export var max_forward_jump_ratio: float = 1.0
## Peak opacity of the red damage vignette when the character is hurt.
@export var damage_tint_alpha: float = 0.5
## Seconds the damage vignette takes to fade back out.
@export var damage_tint_duration: float = 0.2
## Collision layers the mouse aim ray lands on: the level's floors and walls
## (World). Characters share the layer and are looked through.
@export_flags_3d_physics var aim_floor_mask: int = 1
## InputMap actions casting the active ability slots, by slot (index 0 casts
## the character's first slot). Rebinding keys is done on the actions.
@export var ability_actions: Array[StringName] = [&"ability_1", &"ability_2", &"ability_3", &"ability_4"]

## Active damage vignette tween, tracked so a scene transition (or any other
## cancel source) can kill a mid-flash tween instead of letting it resume later.
var _damage_tint_tween: Tween = null


func _ready() -> void:
	# Input translates intents before physical StateMachine ticks (priority -1 vs 0).
	process_physics_priority = -1
	if character == null:
		character = get_parent() as Character
	if character != null:
		character.health_changed.connect(_on_character_health_changed)
		character.transient_state_cancelled.connect(cancel_damage_tint)
		var asc: AbilitySystemComponent = character.ability_system_component
		if asc != null and asc.get_slot_count() > ability_actions.size():
			push_warning("PlayerInputComponent: %d ability slots but only %d ability actions; the extra slots have no key." % [asc.get_slot_count(), ability_actions.size()])


func _physics_process(_delta: float) -> void:
	if character == null or not is_inside_tree() or not character.is_alive():
		return
	update_movement_intent()
	update_aim_intent()


## Routes the attack button and the shared jump/dash button to their orders,
## which drive the current body state's checks at once, so a press transitions
## synchronously. States also consume intents in physics_update, which covers
## AI-raised flags. order_jump() picks between jump and dash from the combat
## lock-on and the held movement direction.
func _unhandled_input(event: InputEvent) -> void:
	if character == null or not character.is_alive():
		return
	if event.is_action_pressed("click"):
		order_attack()
	elif event.is_action_pressed("jump"):
		order_jump()
	else:
		for slot: int in ability_actions.size():
			if event.is_action_pressed(ability_actions[slot]):
				order_ability(slot)
				return


## Computes camera-relative movement direction from input axes.
func update_movement_intent() -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input_3d: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y)
	var camera: Camera3D = character.get_viewport().get_camera_3d()
	if camera != null:
		input_3d = input_3d.rotated(Vector3.UP, camera.global_rotation.y)
	character.move_direction = input_3d.normalized()


## Where the mouse cursor points: the camera ray through the cursor and the
## point where it first hits the level (aim_floor_mask), on whichever floor
## that is. Characters on those layers are looked through. When the ray hits
## nothing (over a pit), the point is where it crosses the height of the
## character's feet. Null without a camera, or when the ray never comes down
## to that height.
func get_aim_target() -> AimTarget:
	if character == null:
		return null
	var viewport: Viewport = character.get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return null
	var mouse: Vector2 = viewport.get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse)
	var direction: Vector3 = camera.project_ray_normal(mouse)
	var hit: Variant = _cast_floor_ray(origin, origin + direction * camera.far)
	if hit == null:
		hit = Plane(Vector3.UP, character.get_feet_position().y).intersects_ray(origin, direction)
	if hit == null:
		return null
	return AimTarget.from_sight(origin, direction, hit as Vector3)


## The first point of the level (aim_floor_mask) between from and to, seeing
## through characters; null when there is none.
func _cast_floor_ray(from: Vector3, to: Vector3) -> Variant:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, aim_floor_mask)
	var space: PhysicsDirectSpaceState3D = character.get_world_3d().direct_space_state
	var seen_through: Array[RID] = []
	for attempt: int in AIM_RAY_MAX_CHARACTERS + 1:
		query.exclude = seen_through
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return null
		if not (result["collider"] is Character):
			return result["position"] as Vector3
		seen_through.append(result["rid"] as RID)
	return null


## Points the character's aim at the mouse cursor (aim_target, and the
## horizontal aim_direction toward it). Keeps the last aim when the cursor
## points at nothing.
func update_aim_intent() -> void:
	var aim: AimTarget = get_aim_target()
	if aim == null:
		return
	character.aim_target = aim
	character.aim_direction = aim.flat_direction_from(character.global_position)


## Returns true if the dash ability is currently off cooldown (delegates to Character).
func can_dash() -> bool:
	return character != null and character.can_dash()


## Raises an edge-triggered attack intent on the character for body states to consume.
## PlayerController counterpart to AIStateMachine.command_attack (same interface).
func command_attack() -> void:
	if character != null:
		character.attack_requested = true


## Raises an edge-triggered dash intent on the character for body states to consume.
## PlayerController counterpart to AIStateMachine.command_dash (same interface).
func command_dash() -> void:
	if character != null:
		character.dash_requested = true


## PlayerController counterpart to AIStateMachine.order_attack(): raises an attack
## intent and immediately drives the current body state's shared check, so
## event-driven orders transition synchronously (same timing raw input had).
func order_attack() -> bool:
	if character == null or character.state_machine == null:
		return false
	# The attack snapshots the character's aim on entry: make it current,
	# while live aiming runs (it is part of this component's physics tick).
	if is_physics_processing():
		update_aim_intent()
	command_attack()
	var body_state: CharacterState = character.state_machine.state as CharacterState
	if body_state == null:
		character.attack_requested = false
		return false
	return body_state.check_attack()


## Raises an edge-triggered ability intent for slot on the character for body
## states to consume (CharacterState.check_ability()).
func command_ability(slot: int) -> void:
	if character != null:
		character.ability_requested = slot


## PlayerController ability order: raises an ability intent for slot and
## immediately drives the current body state's check, so a press casts
## synchronously where the state allows casting (running, jumping, falling,
## a cancelable attack) and is dropped where it does not (dashing).
func order_ability(slot: int) -> bool:
	if character == null or character.state_machine == null:
		return false
	# The cast snapshots the character's aim on entry: make it current.
	if is_physics_processing():
		update_aim_intent()
	command_ability(slot)
	var body_state: CharacterState = character.state_machine.state as CharacterState
	if body_state == null:
		character.ability_requested = -1
		return false
	return body_state.check_ability()


## PlayerController dash order: raises a dash intent and immediately drives the
## current body state's shared check (cooldown-gated there, like check_dash).
func order_dash() -> bool:
	if character == null or character.state_machine == null:
		return false
	command_dash()
	var body_state: CharacterState = character.state_machine.state as CharacterState
	if body_state == null:
		character.dash_requested = false
		return false
	return body_state.check_dash()


## Raises an edge-triggered jump intent on the character for body states to consume.
## PlayerController jump order: the jump button is context-sensitive. Out of
## combat (no auto-aim target locked) it always commands a dash; in combat it
## commands a jump when the held movement is neutral or towards the locked
## target, and a dash when strafing sideways or retreating backwards. Raises
## the chosen intent and immediately drives the current body state's shared
## check, so event-driven orders transition synchronously.
func order_jump() -> bool:
	if character == null or character.state_machine == null:
		return false
	if _should_jump_command_dash():
		return order_dash()
	command_jump()
	var body_state: CharacterState = character.state_machine.state as CharacterState
	if body_state == null:
		character.jump_requested = false
		return false
	return body_state.check_jump(get_forward_jump_ratio())


## Returns true when a jump order must be routed to the dash command instead:
## always while out of combat (no locked auto-aim target), or in combat when
## the held movement direction is not aligned with the direction towards the
## locked target (sideways/backwards dodge). Neutral combat input stays a jump.
func _should_jump_command_dash() -> bool:
	if character == null:
		return false
	var target: Node3D = character.current_target
	if target == null or not is_instance_valid(target):
		return true
	if character.move_direction.is_zero_approx():
		return false
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	if to_target.is_zero_approx():
		return false
	return character.move_direction.normalized().dot(to_target.normalized()) < jump_dash_alignment


## Raises an edge-triggered jump intent on the character for body states to consume.
func command_jump() -> void:
	if character != null:
		character.jump_requested = true


## Computes the dynamic movement speed ratio for a combat forward jump so the
## leap lands jump_landing_gap meters short of the locked auto-aim target.
## Derives the ballistic air time from the state's jump_height (same launch
## speed/impulse/gravity), predicts the landing distance at full walk speed,
## then scales down to stop at (target distance - gap), clamped between
## min/max_forward_jump_ratio. Returns -1.0 when no ratio should apply: no
## locked target, neutral input, or a backward dodge (those keep the state's
## default ratio).
func get_forward_jump_ratio() -> float:
	if character == null or character.state_machine == null:
		return -1.0
	if character.move_direction.is_zero_approx():
		return -1.0
	var target: Node3D = character.current_target
	if target == null or not is_instance_valid(target):
		return -1.0
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if is_zero_approx(distance):
		return -1.0
	if character.move_direction.normalized().dot(to_target / distance) < jump_dash_alignment:
		return -1.0
	var body_state: CharacterState = character.state_machine.state as CharacterState
	if body_state == null or body_state.jump_state == null:
		return -1.0
	var jump: PlayerJump = body_state.jump_state as PlayerJump
	if jump == null or jump.jump_height <= 0.0:
		return -1.0
	var jump_height: float = jump.jump_height
	var speed: float = character.attribute_component.get_current(AttributeComponent.STAT_SPEED)
	var gravity_mag: float = character.get_gravity().length()
	if speed <= 0.0 or is_zero_approx(gravity_mag):
		return -1.0
	var air_time: float = 2.0 * sqrt(2.0 * jump_height / gravity_mag)
	var full_range: float = speed * air_time
	if full_range <= 0.0:
		return -1.0
	var desired_range: float = distance - jump_landing_gap
	return clampf(desired_range / full_range, min_forward_jump_ratio, max_forward_jump_ratio)


## Flashes the red damage vignette when the character takes damage.
func _on_character_health_changed(_value: float) -> void:
	if damage_tint != null and is_inside_tree():
		if _damage_tint_tween != null and _damage_tint_tween.is_valid():
			_damage_tint_tween.kill()
		_damage_tint_tween = create_tween()
		_damage_tint_tween.tween_property(damage_tint, "color", Color(Color.RED, 0.0), damage_tint_duration).from(Color(Color.RED, damage_tint_alpha))


## Cancels any in-flight damage vignette flash and resets the tint to fully
## transparent. Called on scene transitions so a red flash never bleeds into
## the next level (a tween bound to this node would otherwise pause while the
## player is process-disabled and resume red in the new level).
func cancel_damage_tint() -> void:
	if _damage_tint_tween != null and _damage_tint_tween.is_valid():
		_damage_tint_tween.kill()
	_damage_tint_tween = null
	if damage_tint != null and is_instance_valid(damage_tint):
		damage_tint.color = Color(Color.RED, 0.0)
