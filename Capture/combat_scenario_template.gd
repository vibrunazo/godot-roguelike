## Base template scene and script for staging and capturing combat scenarios, attacks, and abilities.
##
## Allows agents to easily spawn any Player or Enemy characters, order them to perform
## specific actions, abilities, or state transitions at exact frames, and capture the
## interaction as screenshots or video to the movies/ folder.
##
## Usage:
## 1. Inherit or extend this script, overriding _setup_scenario()
## 2. Or run directly with CLI arguments:
##    --player --enemy=brute --action=enemy:state:EnemyPunch --video
class_name CombatScenarioTemplate
extends Node3D

## Enemy scene registry mapping friendly names to scene paths.
const ENEMY_REGISTRY: Dictionary = {
	"brute": "res://Enemy/enemy_brute.tscn",
	"melee": "res://Enemy/melee_enemy.tscn",
	"ranged": "res://Enemy/ranged_enemy.tscn",
	"firebomber": "res://Enemy/firebomber_enemy.tscn",
	"thunder_mage": "res://Enemy/enemy_thunder_mage.tscn",
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
var finish_frame: int = 180
var is_video: bool = false
var debug_collisions: bool = true
var output_path: String = ""

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
	_hide_transition_overlay()

	# Process scheduled actions for current frame
	for action: ScheduledAction in scheduled_actions:
		if action.frame == frame_count:
			_execute_action(action)

	# Auto camera tracking if enabled
	_update_camera_tracking()

	if frame_count >= finish_frame:
		print("[CombatScenario] Scenario reached finish frame (%d). Quitting." % frame_count)
		get_tree().quit(0)


## Virtual method for custom scenario subclasses to configure combatants and actions.
func _setup_scenario() -> void:
	pass


## Spawns the Player character at the specified position facing a direction.
func spawn_player(pos: Vector3 = Vector3(0.0, 0.0, 2.0), facing_dir: Vector3 = Vector3(0.0, 0.0, -1.0)) -> Character:
	var scn: PackedScene = load("res://Player/player.tscn") as PackedScene
	var player: Character = scn.instantiate() as Character
	player.position = pos
	add_child(player)

	var tint: CanvasItem = player.find_child("DamageTint", true, false) as CanvasItem
	if tint != null:
		tint.visible = false

	if facing_dir.length_squared() > 0.001:
		player.look_at(player.global_position + facing_dir, Vector3.UP)

	player_instance = player
	all_combatants.append(player)
	print("[CombatScenario] Spawned Player at: ", pos)
	return player


## Spawns an enemy by friendly name ("brute", "melee", "firebomber", etc.) or scene path.
func spawn_enemy(enemy_identifier: String = "brute", pos: Vector3 = Vector3(0.0, 0.0, 0.0), facing_dir: Vector3 = Vector3(0.0, 0.0, 1.0)) -> Character:
	var path: String = enemy_identifier
	if ENEMY_REGISTRY.has(enemy_identifier.to_lower()):
		path = ENEMY_REGISTRY[enemy_identifier.to_lower()] as String
	elif not path.begins_with("res://"):
		path = "res://" + path.trim_prefix("./")

	if not ResourceLoader.exists(path):
		printerr("[CombatScenario] ERROR: Enemy scene does not exist: ", path)
		return null

	var scn: PackedScene = load(path) as PackedScene
	var enemy: Character = scn.instantiate() as Character
	enemy.position = pos
	add_child(enemy)

	if facing_dir.length_squared() > 0.001:
		enemy.look_at(enemy.global_position + facing_dir, Vector3.UP)

	enemy_instance = enemy
	all_combatants.append(enemy)
	print("[CombatScenario] Spawned Enemy (%s) at: %s" % [enemy_identifier, pos])
	return enemy


## Spawns an inert target dummy (melee enemy with AI disabled) at the given position.
func spawn_dummy(pos: Vector3 = Vector3(0.0, 0.0, 0.0)) -> Character:
	var dummy: Character = spawn_enemy("melee", pos, Vector3(0.0, 0.0, 1.0))
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


## Orders a character to take a specific amount of damage at a given frame.
func order_damage(character: Character, amount: float, at_frame: int) -> void:
	scheduled_actions.append(ScheduledAction.new(character, "damage", amount, at_frame))


## Schedules a screenshot to be saved to file_path at a given frame.
func order_screenshot(p_output_path: String, at_frame: int) -> void:
	scheduled_actions.append(ScheduledAction.new(null, "screenshot", p_output_path, at_frame))


## Schedules the scenario to end and Godot to exit at a given frame.
func order_finish(at_frame: int) -> void:
	finish_frame = at_frame


func _execute_action(action: ScheduledAction) -> void:
	match action.action_type:
		"state":
			var c: Character = action.target as Character
			if c != null and c.state_machine != null:
				var s_name: String = str(action.param_value)
				c.state_machine.request_state(s_name)
				print("[CombatScenario @ frame %d] Requested state '%s' on %s" % [frame_count, s_name, c.name])
		"damage":
			var c: Character = action.target as Character
			if c != null and c.health_component != null:
				var dmg: float = float(action.param_value)
				c.health_component.take_damage(dmg)
				print("[CombatScenario @ frame %d] Applied %.1f damage to %s" % [frame_count, dmg, c.name])
		"screenshot":
			var path_str: String = str(action.param_value)
			_save_screenshot(path_str)


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
	if debug_collisions:
		get_tree().debug_collisions_hint = true

	_hide_transition_overlay()

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
	camera.fov = 45.0
	add_child(camera)
	camera.position = Vector3(4.5, 3.2, 5.8)
	camera.look_at(Vector3(0.0, 1.0, 0.8), Vector3.UP)


func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg == "--player":
			cli_spawn_player = true
		elif arg.begins_with("--enemy="):
			cli_enemy_type = arg.trim_prefix("--enemy=").strip_edges()
		elif arg.begins_with("--action="):
			cli_actions.append(arg.trim_prefix("--action=").strip_edges())
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=").strip_edges()
		elif arg.begins_with("--frames="):
			finish_frame = arg.trim_prefix("--frames=").to_int()
		elif arg.begins_with("--duration="):
			var dur: float = arg.trim_prefix("--duration=").to_float()
			finish_frame = int(dur * 60.0)
		elif arg == "--video":
			is_video = true
		elif arg == "--no-debug-collisions":
			debug_collisions = false


func _apply_cli_scenario() -> void:
	if cli_spawn_player and player_instance == null:
		spawn_player(Vector3(0.0, 0.0, 2.0))

	if not cli_enemy_type.is_empty() and enemy_instance == null:
		spawn_enemy(cli_enemy_type, Vector3(0.0, 0.0, 0.0))

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
					snap_path = output_path
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
			elif act_type == "damage" and target_node != null:
				order_damage(target_node, param.to_float(), at_frame)
			elif act_type == "attack" and target_node != null:
				order_player_attack(target_node, param.to_int(), at_frame)
			elif act_type == "screenshot":
				var snap_path: String = param
				if snap_path.is_empty():
					snap_path = output_path
				if snap_path.is_empty():
					snap_path = "movies/combat_frame_%d.png" % at_frame
				order_screenshot(snap_path, at_frame)

	if not output_path.is_empty() and not is_video:
		# Schedule final screenshot before exit
		order_screenshot(output_path, maxi(finish_frame - 5, 20))


func _hide_transition_overlay() -> void:
	var st: CanvasLayer = get_node_or_null("/root/SceneTransition") as CanvasLayer
	if st != null:
		st.visible = false
		var cr: ColorRect = st.get_node_or_null("ColorRect") as ColorRect
		if cr != null:
			cr.visible = false


func _save_screenshot(file_path: String) -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var tex: ViewportTexture = viewport.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return

	var base_dir: String = file_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)

	var err: Error = img.save_png(file_path)
	if err == OK:
		print("[CombatScenario] Screenshot saved successfully: ", file_path, " (", img.get_width(), "x", img.get_height(), ")")
	else:
		printerr("[CombatScenario] Failed to save screenshot: ", file_path, " error: ", err)
