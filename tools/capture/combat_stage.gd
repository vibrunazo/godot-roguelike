## Staging scene for combat captures: a lit arena floor and camera, a player
## and an enemy, and actions scheduled on exact physics frames (states,
## attacks, hits, callbacks, extra named screenshots). It only stages:
## `kit.py capture scene` takes the main screenshot, sheet or video and ends
## the run (--at, --duration).
##
##   python addons/godot_kit/kit.py capture scene tools/capture/combat_stage.tscn --scene-camera --video --duration 3 -- --player --enemy=brute --action=enemy:state:EnemyPunch@15
##
## Arguments after `--` (read after the kit's --scene-args marker): --player,
## --enemy=<registry name or scene path>, --action=target:type:param@frame
## (repeatable), --enable-ai, --freeze (hold the combatants in place),
## --player-pos=, --enemy-pos=, --cam-pos=, --cam-target= (X,Y,Z) and --cam-fov=.
## A saved scenario extends this script and overrides _setup_scenario().
class_name CombatStage
extends Node3D

const CaptureImage: GDScript = preload("res://addons/godot_kit/capture/capture_image.gd")
## Enemy scene registry mapping friendly names to scene paths.
const ENEMY_REGISTRY: Dictionary = {
	"brute": "res://Enemy/enemy_brute.tscn",
	"melee": "res://Enemy/melee_enemy.tscn",
	"ranged": "res://Enemy/ranged_enemy.tscn",
	"firebomber": "res://Enemy/firebomber_enemy.tscn",
	"thunder_mage": "res://Enemy/enemy_thunder_mage.tscn",
	"headless_daemon": "res://Enemy/enemy_headless_daemon.tscn",
	"backface_knight": "res://Enemy/enemy_backface_knight.tscn",
}

class ScheduledAction:
	var target: Node
	var action_type: String # "state", "attack", "damage", "screenshot", "callback", "custom"
	var param_value: Variant
	var frame: int

	func _init(p_target: Node, p_type: String, p_param: Variant, p_frame: int) -> void:
		target = p_target
		action_type = p_type
		param_value = p_param
		frame = p_frame

var camera: Camera3D
var player_instance: Character
var enemy_instance: Character
var all_combatants: Array[Character] = []
var scheduled_actions: Array[ScheduledAction] = []

var frame_count: int = 0
## Health bars are hidden unless the capture keeps the UI (--show-ui).
var hide_ui: bool = true

var custom_cam_pos: Vector3 = Vector3.ZERO
var custom_cam_target: Vector3 = Vector3.ZERO
var has_custom_cam_pos: bool = false
var has_custom_cam_target: bool = false
var cam_fov: float = 50.0
var cli_enable_ai: bool = false
var cli_freeze_actors: bool = false

var custom_player_pos: Vector3 = Vector3.ZERO
var custom_enemy_pos: Vector3 = Vector3.ZERO
var has_custom_player_pos: bool = false
var has_custom_enemy_pos: bool = false

# CLI arguments
var cli_spawn_player: bool = false
var cli_enemy_type: String = ""
var cli_actions: PackedStringArray = []


func _ready() -> void:
	_parse_arguments()
	_setup_environment()
	_setup_camera()
	_setup_scenario()
	_apply_cli_scenario()


func _physics_process(_delta: float) -> void:
	frame_count += 1
	_hide_health_bars()

	if camera != null and not camera.is_current():
		camera.make_current()
		print("[CombatStage] Note: Re-asserted ArenaCamera as active viewport camera.")

	# Process scheduled actions for current frame
	for action: ScheduledAction in scheduled_actions:
		if action.frame == frame_count:
			_execute_action(action)

	# Auto camera tracking if not using custom camera
	if not has_custom_cam_pos and not has_custom_cam_target:
		_update_camera_tracking()


## Virtual method for custom scenario subclasses to configure combatants and actions.
func _setup_scenario() -> void:
	pass


## Spawns the Player character at the specified position facing a direction.
func spawn_player(pos: Vector3 = Vector3(0.0, 1.0, 1.0), facing_dir: Vector3 = Vector3(0.0, 0.0, -1.0)) -> Character:
	var scn: PackedScene = load("res://Player/player.tscn") as PackedScene
	var player: Character = scn.instantiate() as Character
	player.position = pos
	add_child(player)

	var tint: CanvasItem = player.find_child("DamageTint", true, false) as CanvasItem
	if tint != null:
		tint.visible = false

	if facing_dir.length_squared() > 0.001:
		player.look_at(player.global_position + facing_dir, Vector3.UP)

	_suppress_actor_cameras(player)

	player_instance = player
	all_combatants.append(player)
	print("[CombatStage] Spawned Player at: ", pos)
	return player


## Spawns an enemy by friendly name ("brute", "melee", "firebomber", etc.) or scene path.
func spawn_enemy(enemy_identifier: String = "brute", pos: Vector3 = Vector3(0.0, 1.0, -1.5), facing_dir: Vector3 = Vector3(0.0, 0.0, 1.0)) -> Character:
	var path: String = enemy_identifier
	if ENEMY_REGISTRY.has(enemy_identifier.to_lower()):
		path = ENEMY_REGISTRY[enemy_identifier.to_lower()] as String
	elif not path.begins_with("res://"):
		path = "res://" + path.trim_prefix("./")

	if not ResourceLoader.exists(path):
		printerr("[CombatStage] ERROR: Enemy scene does not exist: ", path)
		return null

	var scn: PackedScene = load(path) as PackedScene
	var enemy: Character = scn.instantiate() as Character
	enemy.position = pos
	add_child(enemy)

	if facing_dir.length_squared() > 0.001:
		enemy.look_at(enemy.global_position + facing_dir, Vector3.UP)

	if not cli_enable_ai and enemy.ai_state_machine != null:
		enemy.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED

	_suppress_actor_cameras(enemy)

	enemy_instance = enemy
	all_combatants.append(enemy)
	print("[CombatStage] Spawned Enemy (%s) at: %s" % [enemy_identifier, pos])
	return enemy


## Spawns an inert target dummy (melee enemy with AI disabled) at the given position.
func spawn_dummy(pos: Vector3 = Vector3(0.0, 1.0, 1.0)) -> Character:
	var dummy: Character = spawn_enemy("melee", pos, Vector3(0.0, 0.0, -1.0))
	if dummy != null and dummy.ai_state_machine != null:
		dummy.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	return dummy


## Orders a character to transition to a specific StateMachine state at a given frame.
func order_state(character: Character, state_to_request: String, at_frame: int) -> void:
	scheduled_actions.append(ScheduledAction.new(character, "state", state_to_request, at_frame))


## Orders the player to trigger an attack combo (1, 2, or 3) at a given frame.
func order_player_attack(player: Character, combo_index: int, at_frame: int) -> void:
	var state_req: String = "PlayerAttack"
	if combo_index == 2:
		state_req = "PlayerAttack2"
	elif combo_index == 3:
		state_req = "PlayerAttack3"
	order_state(player, state_req, at_frame)


## Orders a character to take a hit of the given damage at a given frame,
## through its Hurtbox (so it flashes, staggers and shows a damage number).
func order_damage(character: Character, amount: float, at_frame: int) -> void:
	scheduled_actions.append(ScheduledAction.new(character, "damage", amount, at_frame))


## Schedules a screenshot to be saved to file_path at a given frame.
func order_screenshot(p_output_path: String, at_frame: int) -> void:
	scheduled_actions.append(ScheduledAction.new(null, "screenshot", p_output_path, at_frame))


## Schedules a zero-argument method call on any node at a given frame
## (e.g. a boss controller's custom trigger). No-op if the method is missing.
func order_callback(target: Node, method: StringName, at_frame: int) -> void:
	scheduled_actions.append(ScheduledAction.new(target, "callback", String(method), at_frame))


## Instantly faces a character's mount at a position for staging setup only.
## Gameplay auto-aim must go through Character.look_at_target (which respects
## the rotation speed limit); captures need deterministic initial facing
## before frame 0, so this setup helper bypasses the limit while preserving
## mount scale and origin.
func _snap_face(c: Character, pos: Vector3) -> void:
	if c == null or c.mesh_mount == null:
		return
	var to: Vector3 = pos - c.mesh_mount.global_position
	to.y = 0.0
	if to.is_zero_approx():
		return
	var keep_scale: Vector3 = c.mesh_mount.global_transform.basis.get_scale()
	var yaw: float = atan2(to.x, to.z)
	c.mesh_mount.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(keep_scale), c.mesh_mount.global_transform.origin)


func _execute_action(action: ScheduledAction) -> void:
	match action.action_type:
		"state":
			var c: Character = action.target as Character
			if c != null and c.state_machine != null:
				var s_name: String = str(action.param_value)
				if c == enemy_instance and player_instance != null:
					c.current_target = player_instance
					_snap_face(c, player_instance.global_position)
					c.aim_direction = (player_instance.global_position - c.global_position).normalized()
				c.state_machine.request_state(s_name)
				print("[CombatStage @ frame %d] Requested state '%s' on %s" % [frame_count, s_name, c.name])
		"damage":
			var c: Character = action.target as Character
			if c != null and c.hurtbox != null:
				var dmg: float = float(action.param_value)
				c.hurtbox.receive_hit(dmg, Vector3.ZERO)
				print("[CombatStage @ frame %d] Applied %.1f damage to %s" % [frame_count, dmg, c.name])
		"screenshot":
			var path_str: String = str(action.param_value)
			_save_screenshot(path_str)
		"callback":
			var target: Node = action.target as Node
			var method: StringName = StringName(str(action.param_value))
			if target != null and is_instance_valid(target) and target.has_method(method):
				target.call(method)
				print("[CombatStage @ frame %d] Called %s() on %s" % [frame_count, String(method), target.name])
			else:
				printerr("[CombatStage @ frame %d] Cannot call '%s' (missing node or method)." % [frame_count, String(method)])


func _update_camera_tracking() -> void:
	if all_combatants.is_empty() or camera == null:
		return

	# Frame all active combatants
	var sum_pos: Vector3 = Vector3.ZERO
	var count: int = 0
	for c: Character in all_combatants:
		if is_instance_valid(c):
			sum_pos += c.global_position
			count += 1

	if count > 0:
		var mid_point: Vector3 = sum_pos / float(count)
		# Smoothly frame combatants
		var look_target: Vector3 = Vector3(mid_point.x, mid_point.y + 1.0, mid_point.z)
		camera.look_at(look_target, Vector3.UP)


func _setup_environment() -> void:
	# Key light
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	key_light.light_energy = 1.2
	key_light.shadow_enabled = true
	add_child(key_light)

	# Fill light
	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-25.0, -135.0, 0.0)
	fill_light.light_energy = 0.5
	fill_light.shadow_enabled = false
	add_child(fill_light)

	# Arena Floor
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(40.0, 1.0, 40.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)

	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0.0, 0.5, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.26, 1.0)
	mat.roughness = 0.85
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	add_child(floor_body)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "ArenaCamera"
	camera.current = true
	camera.fov = cam_fov
	add_child(camera)
	if has_custom_cam_pos:
		camera.position = custom_cam_pos
	else:
		# Side 3/4 angle framing combatants at Z=-1.5 and Z=+1.0
		camera.position = Vector3(5.8, 2.0, -0.25)

	if has_custom_cam_target:
		camera.look_at(custom_cam_target, Vector3.UP)
	else:
		camera.look_at(Vector3(0.0, 1.0, -0.25), Vector3.UP)


func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	hide_ui = args.has("--hide-ui")
	for arg: String in args.slice(args.find("--scene-args") + 1):
		var key: String = arg.get_slice("=", 0)
		var value: String = arg.get_slice("=", 1).strip_edges() if arg.contains("=") else ""
		match key:
			"--player":
				cli_spawn_player = true
			"--enemy":
				cli_enemy_type = value
			"--action":
				cli_actions.append(value)
			"--enable-ai":
				cli_enable_ai = true
			"--freeze":
				cli_freeze_actors = true
			"--cam-fov":
				cam_fov = value.to_float()
			"--player-pos":
				has_custom_player_pos = _parse_vector(value, func(v: Vector3) -> void: custom_player_pos = v)
			"--enemy-pos":
				has_custom_enemy_pos = _parse_vector(value, func(v: Vector3) -> void: custom_enemy_pos = v)
			"--cam-pos":
				has_custom_cam_pos = _parse_vector(value, func(v: Vector3) -> void: custom_cam_pos = v)
			"--cam-target":
				has_custom_cam_target = _parse_vector(value, func(v: Vector3) -> void: custom_cam_target = v)


## Parses "X,Y,Z" and hands the vector to apply; false when the text is not three numbers.
func _parse_vector(text: String, apply: Callable) -> bool:
	var parts: PackedStringArray = text.split(",")
	if parts.size() != 3:
		return false
	apply.call(Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()))
	return true


func _apply_cli_scenario() -> void:
	if cli_spawn_player and player_instance == null:
		var p_pos: Vector3 = custom_player_pos if has_custom_player_pos else Vector3(0.0, 1.0, 1.0)
		spawn_player(p_pos)

	if not cli_enemy_type.is_empty() and enemy_instance == null:
		var e_pos: Vector3 = custom_enemy_pos if has_custom_enemy_pos else Vector3(0.0, 1.0, -1.5)
		spawn_enemy(cli_enemy_type, e_pos)

	if player_instance != null and enemy_instance != null:
		enemy_instance.current_target = player_instance
		_snap_face(enemy_instance, player_instance.global_position)
		enemy_instance.aim_direction = (player_instance.global_position - enemy_instance.global_position).normalized()
		_snap_face(player_instance, enemy_instance.global_position)

	for action_str: String in cli_actions:
		# Format: target:type:param@frame (e.g. "enemy:state:EnemyPunch@15", "player:attack:1@20", "snap:movies/test.png@30")
		var at_frame: int = 15
		var cmd: String = action_str
		if action_str.contains("@"):
			var split_at: PackedStringArray = action_str.split("@")
			cmd = split_at[0]
			at_frame = split_at[1].to_int()

		var parts: PackedStringArray = cmd.split(":")
		if parts.size() >= 2:
			var target_str: String = parts[0].to_lower()
			if target_str == "screenshot" or target_str == "snap":
				var snap_path: String = cmd.substr(parts[0].length() + 1).strip_edges()
				if snap_path.is_empty():
					snap_path = "movies/combat_frame_%d.png" % at_frame
				order_screenshot(snap_path, at_frame)
				continue

			var act_type: String = parts[1]
			var param: String = ""
			if parts.size() >= 3:
				param = parts[2]

			var target_node: Character = null
			if target_str == "player":
				target_node = player_instance
			elif target_str == "enemy":
				target_node = enemy_instance

			if act_type == "state" and target_node != null:
				order_state(target_node, param, at_frame)
			elif act_type == "callback" and target_node != null:
				order_callback(target_node, StringName(param), at_frame)
			elif act_type == "damage" and target_node != null:
				order_damage(target_node, param.to_float(), at_frame)
			elif act_type == "attack" and target_node != null:
				order_player_attack(target_node, param.to_int(), at_frame)
			elif act_type == "screenshot":
				var snap_path: String = param
				if snap_path.is_empty():
					snap_path = "movies/combat_frame_%d.png" % at_frame
				order_screenshot(snap_path, at_frame)

	if cli_freeze_actors:
		_freeze_combatants()


## Holds staged combatants in place: zeroes velocity and pauses physics, state
## machines, and AI. Companion nodes without physics (e.g. boss rider
## controllers) keep running, so scripted attacks can still fire at frozen
## targets. Frozen actors keep their spawn position, so spawning at rest
## height is recommended for grounded stills.
func _freeze_combatants() -> void:
	for c: Character in all_combatants:
		if not is_instance_valid(c):
			continue
		c.set_physics_process(false)
		c.velocity = Vector3.ZERO
		if c.state_machine != null:
			c.state_machine.set_physics_process(false)
		if c.ai_state_machine != null:
			c.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	print("[CombatStage] Froze %d combatant(s) in place." % all_combatants.size())


func _hide_health_bars() -> void:
	if not hide_ui:
		return
	for bar: Node in get_tree().root.find_children("*", "HealthBar", true, false):
		if "visible" in bar:
			bar.set("visible", false)


func _save_screenshot(file_path: String) -> void:
	if not file_path.to_lower().ends_with(".png"):
		file_path += ".png"
	CaptureImage.save(CaptureImage.grab(get_viewport()), file_path, "CombatStage")


## Recursively suppresses any active Camera3D nodes inside spawned actors to avoid viewport conflicts.
func _suppress_actor_cameras(actor: Node) -> void:
	if actor == null:
		return
	var actor_cams: Array[Node] = actor.find_children("*", "Camera3D", true, false)
	for cam_node: Node in actor_cams:
		var c: Camera3D = cam_node as Camera3D
		if c != null:
			if c.current:
				print("[Capture] Note: Suppressed active actor camera '%s' on %s to preserve studio camera." % [c.name, actor.name])
			c.current = false
	var cam_root: Node = actor.find_child("CameraRoot", true, false)
	if cam_root != null:
		cam_root.queue_free()
	if camera != null and not camera.is_current():
		camera.make_current()
