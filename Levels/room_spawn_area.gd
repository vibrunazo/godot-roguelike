## Trigger and spawn volume bounding enemy encounters to a specific room or zone.
class_name RoomSpawnArea
extends Area3D

## Optional identifier for this room (e.g. "Start Vestibule", "Center Nexus", "Eastern Chamber").
@export var room_name: String = ""

## Maximum radius to search for navmesh points if bounds sampling needs a radius fallback.
@export var spawn_radius: float = 6.0

## Enemies assigned to spawn or patrol in this room.
var assigned_enemies: Array[Character] = []

## Whether the player has entered this room and triggered the encounter.
var is_triggered: bool = false

signal player_entered(area: RoomSpawnArea)


func _ready() -> void:
	collision_layer = 0
	set_collision_mask_value(1, true)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Associates an enemy with this room.
func assign_enemy(enemy: Character) -> void:
	if enemy == null or assigned_enemies.has(enemy):
		return
	assigned_enemies.append(enemy)
	enemy.home_spawn_area = self
	enemy.is_alerted = is_triggered
	if not enemy.defeat.is_connected(_on_enemy_defeat):
		enemy.defeat.connect(_on_enemy_defeat.bind(enemy))


func _on_enemy_defeat(enemy: Character) -> void:
	assigned_enemies.erase(enemy)


## Returns a valid spawn position on the navmesh within this room area.
func get_random_spawn_point() -> Vector3:
	var nav_map: RID = get_world_3d().navigation_map
	var col_shape: CollisionShape3D = null
	for child: Node in get_children():
		if child is CollisionShape3D and child.shape != null:
			col_shape = child as CollisionShape3D
			break

	var sample_pos: Vector3 = global_position
	if col_shape != null and col_shape.shape is BoxShape3D:
		var box: BoxShape3D = col_shape.shape as BoxShape3D
		var hx: float = box.size.x * 0.45
		var hz: float = box.size.z * 0.45
		var local_offset: Vector3 = Vector3(randf_range(-hx, hx), 0.0, randf_range(-hz, hz))
		sample_pos = col_shape.global_position + col_shape.global_transform.basis * local_offset
	else:
		var r: float = spawn_radius * 0.8
		sample_pos = global_position + Vector3(randf_range(-r, r), 0.0, randf_range(-r, r))

	var nav_point: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, sample_pos)
	return nav_point


func _on_body_entered(body: Node3D) -> void:
	if is_triggered:
		return
	var is_player_body: bool = false
	if body is Character:
		is_player_body = (body as Character).is_player()
	elif body != null:
		is_player_body = body.is_in_group("player")

	if is_player_body:
		alert_enemies()


## Alerts all assigned enemies in this room to pursue the player.
func alert_enemies() -> void:
	is_triggered = true
	player_entered.emit(self)
	for enemy: Character in assigned_enemies:
		if enemy != null and is_instance_valid(enemy) and enemy.is_alive():
			enemy.alert()
