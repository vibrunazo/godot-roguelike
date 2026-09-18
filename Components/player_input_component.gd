## Component that listens to user inputs and translates them into Character intents and actions.
class_name PlayerInputComponent
extends Node

## The Character controlled by this input component.
@export var character: Character
## Cooldown timer preventing dash spamming.
@export var dash_cooldown: Timer
## Sound effect player for dashing.
@export var dash_audio: AudioStreamPlayer3D
## Fullscreen damage vignette/tint ColorRect.
@export var damage_tint: ColorRect
## Range in meters for auto-aim target acquisition (<= 0.0 disables auto-aim).
@export var auto_aim_range: float = 5.0
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

## Active damage vignette tween, tracked so a scene transition (or any other
## cancel source) can kill a mid-flash tween instead of letting it resume later.
var _damage_tint_tween: Tween = null


func _ready() -> void:
	# Input translates intents before physical StateMachine ticks (priority -1 vs 0).
	process_physics_priority = -1
	if character == null:
		character = get_parent() as Character
	if character != null:
		character.auto_aim_range = auto_aim_range
		character.health_changed.connect(_on_character_health_changed)


func _physics_process(_delta: float) -> void:
	if character == null or not is_inside_tree() or not character.is_alive():
		return
	update_movement_intent()
	update_aim_intent()


## Computes camera-relative movement direction from input axes.
func update_movement_intent() -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input_3d: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y)
	var camera: Camera3D = character.get_viewport().get_camera_3d()
	if camera != null:
		input_3d = input_3d.rotated(Vector3.UP, camera.global_rotation.y)
	character.move_direction = input_3d.normalized()


## Returns the 2D viewport coordinates of the character's 3D global position.
func get_character_position_2d() -> Vector2:
	if character == null:
		return Vector2.ZERO
	var camera: Camera3D = character.get_viewport().get_camera_3d()
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(character.global_position)


## Returns the 2D screen vector pointing from the character to the mouse cursor.
func get_mouse_direction() -> Vector2:
	if character == null:
		return Vector2.ZERO
	return character.get_viewport().get_mouse_position() - get_character_position_2d()


## Returns the 3D ground direction vector pointing towards the mouse cursor, aligned with camera rotation.
func get_aim_direction() -> Vector3:
	if character == null:
		return Vector3.ZERO
	var direction: Vector2 = get_mouse_direction()
	var direction_3d: Vector3 = Vector3(direction.x, 0.0, direction.y)
	var camera: Camera3D = character.get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	return direction_3d.rotated(Vector3.UP, camera.global_rotation.y)


## Computes camera-relative aim direction towards mouse cursor and assigns it to the character.
func update_aim_intent() -> void:
	character.aim_direction = get_aim_direction()


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
	command_attack()
	var body_state: CharacterState = character.state_machine.state as CharacterState
	if body_state == null:
		character.attack_requested = false
		return false
	return body_state.check_attack()


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
	var jump_height: float = 0.0
	if body_state.jump_state.get("jump_height") != null:
		jump_height = float(body_state.jump_state.get("jump_height"))
	if jump_height <= 0.0:
		return -1.0
	var speed: float = character.attribute_component.get_current(AttributeComponent.STAT_SPEED) if character.attribute_component != null else 8.0
	if speed <= 0.0:
		return -1.0
	var gravity_mag: float = character.get_gravity().length()
	if is_zero_approx(gravity_mag):
		gravity_mag = 9.8
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
		_damage_tint_tween.tween_property(damage_tint, "color", Color(Color.RED, 0.0), 0.2).from(Color(Color.RED, 0.5))


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
