## Level 13: every table decoration physically blocks the real player
## capsule from both sides (a swept body motion, not a visual overlap check).
extends "res://test/lib/test_suite.gd"

const LEVEL_SCENE: PackedScene = preload("res://Levels/level_13.tscn")
const TABLES: Array[String] = ["LowerWorkTable", "LowerBanquetTable", "UpperFeastTable", "UpperLongTable"]
## How far to the side of a table the sweep starts, and how far it moves.
const SWEEP_START: float = 3.0
const SWEEP_LENGTH: float = 6.0
## Capsule bottom height above the table origin: clear of the floor, so only
## furniture can stop the sweep.
const SWEEP_HEIGHT: float = 1.05


func test_every_table_blocks_the_player_from_both_sides() -> void:
	var level: Node3D = spawn(LEVEL_SCENE) as Node3D
	(level.get_node("WaveObjective") as WaveObjective).stop_spawning()
	var player: Character = level.get_node("Player") as Character
	# Only the test moves the body: no states, AI or input.
	player.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_physics_frames(2)
	for table_name: String in TABLES:
		var table: StaticBody3D = level.get_node("NavigationRegion3D/Litter/" + table_name) as StaticBody3D
		for side: float in [-1.0, 1.0]:
			# Each table is yawed 90 degrees, so X crosses its short axis.
			player.global_position = table.global_position + Vector3(side * SWEEP_START, SWEEP_HEIGHT, 0.0)
			await wait_physics_frames(1)
			var collision: KinematicCollision3D = player.move_and_collide(Vector3(-side * SWEEP_LENGTH, 0.0, 0.0))
			var stopped_on_its_side: bool = (player.global_position.x - table.global_position.x) * side > 0.0
			check(collision != null and collision.get_collider() == table and stopped_on_its_side, "%s should block the player coming from side %d (stopped at %s)" % [table_name, side, player.global_position])
