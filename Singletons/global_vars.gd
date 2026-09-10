# TODO: Autoloads should be separated into different global systems with different names and responsibilities, instead of a generic GlobalVars autoload with multiple responsibilities.
extends Node

## Difficulty scaling curve sampled by get_enemy_count().
@export var difficulty_curve: Curve
## Upgrade scenes offered by the UpgradeShop.
@export var upgrade_damage: PackedScene
## Upgrade scenes offered by the UpgradeShop.
@export var upgrade_health: PackedScene
## Upgrade scenes offered by the UpgradeShop.
@export var upgrade_speed: PackedScene
## Enemy scenes spawned by WaveObjective.
@export var enemy_melee_scene: PackedScene
## Enemy scenes spawned by WaveObjective.
@export var enemy_ranged_scene: PackedScene
## Projectile scene spawned by ProjectileSpawnerComponent.
@export var enemy_projectile_scene: PackedScene
## Impact effect spawned by EnemyProjectile on collision.
@export var fireball_hit_scene: PackedScene
## Floating combat text spawned by VfxManager on damage.
@export var damage_number_scene: PackedScene
## Shop scene opened by ExitPoint when no explicit next scene is set.
@export var upgrade_shop_scene: PackedScene

## Upgrade scenes offered by the UpgradeShop, built from the exported upgrade scenes.
var upgrades: Array[PackedScene] = []

var level: int = 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	upgrades = [upgrade_damage, upgrade_health, upgrade_speed]


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_toggle_fullscreen"):
		toggle_fullscreen()


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN \
		or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func go_fullscreen() -> void:
	if Engine.is_embedded_in_editor() or get_window().is_embedded():
		print("Cannot toggle fullscreen while game is embedded in the editor. Disable 'Game Embed Mode' in Editor Settings -> Run -> Window Placement.")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func toggle_fullscreen() -> void:
	if Engine.is_embedded_in_editor() or get_window().is_embedded():
		print("Cannot toggle fullscreen while game is embedded in the editor. Disable 'Game Embed Mode' in Editor Settings -> Run -> Window Placement.")
		return
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		go_fullscreen()


func finish_level() -> void:
	level += 1


func get_enemy_count() -> int:
	return int(floor(difficulty_curve.sample(float(level))))
