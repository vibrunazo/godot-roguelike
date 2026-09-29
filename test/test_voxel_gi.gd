## The level template's global illumination:
## - its VoxelGI has baked data, and its volume encloses the player spawn and
##   the exit,
## - characters placed in the level when GI is baked (the player) never bake
##   into it: none of their meshes is included in GI baking, or a moving body
##   would leave a permanent shadow where it stood during the bake.
## - no registered enemy bakes into GI either, so one placed in a level when
##   GI is baked cannot leave a permanent shadow.
## (Every level in the rotation is checked for baked GI and floor coverage by
## test_level_rotation_nav.)
extends "res://test/lib/test_suite.gd"

const LEVEL_TEMPLATE_SCENE: PackedScene = preload("res://Levels/level_template.tscn")

var _level: Node3D


func before_each() -> void:
	_level = spawn(LEVEL_TEMPLATE_SCENE) as Node3D
	(_level.get_node("WaveObjective") as WaveObjective).stop_spawning()
	await wait_physics_frames(1)


func test_the_template_gi_is_baked_and_encloses_the_spawn_and_the_exit() -> void:
	var gi: VoxelGI = _level.get_node("VoxelGI") as VoxelGI
	if not check(gi.data != null and gi.data.get_bounds().size != Vector3.ZERO, "the template VoxelGI should have baked data"):
		return
	var volume: AABB = gi.global_transform * AABB(-gi.size * 0.5, gi.size)
	for node_name: String in ["Player", "ExitPoint"]:
		var point: Vector3 = (_level.get_node(node_name) as Node3D).global_position
		check(volume.has_point(point), "the GI volume should enclose the %s (at %s)" % [node_name, point])


func test_characters_present_at_bake_time_never_bake_into_gi() -> void:
	var characters: Array[Node] = _level.find_children("*", "Character", true, false)
	if not check(not characters.is_empty(), "setup: the template should place a character (the player)"):
		return
	for character: Node in characters:
		_check_never_bakes_into_gi(character)


func test_registered_enemies_never_bake_into_gi() -> void:
	if not check(not GlobalVars.enemies.is_empty(), "setup: GlobalVars should register enemies"):
		return
	for enemy_resource: EnemyResource in GlobalVars.enemies:
		_check_never_bakes_into_gi(autofree(enemy_resource.scene.instantiate()))


## Checks that none of [param root]'s geometry is included in GI baking.
func _check_never_bakes_into_gi(root: Node) -> void:
	for geometry: Node in root.find_children("*", "GeometryInstance3D", true, false):
		check_eq((geometry as GeometryInstance3D).gi_mode, GeometryInstance3D.GI_MODE_DISABLED, "%s/%s must not bake into GI" % [root.name, root.get_path_to(geometry)])
