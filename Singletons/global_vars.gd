## Default global asset references, registered as the `GlobalVars` autoload (scene
## `Singletons/global_vars.tscn`) in `project.godot`. Access from anywhere via
## `GlobalVars`, e.g. `GlobalVars.upgrade_damage`.
##
## Unique responsibility: hold default global references to scenes and resources
## used elsewhere in the game. Individual nodes may override these locally via
## their own `@export`s (falling back to the registry when unset). Anything that
## is not a shared default reference — run state, difficulty math, input,
## display, spawning — belongs in another autoload (`ProgressionState`, `UI`,
## `VfxManager`, `SceneTransition`), never here.
extends Node

const ItemResource = preload("res://Items/item_resource.gd")
const EnemyResource = preload("res://Enemy/enemy_resource.gd")

## Legacy difficulty scaling curve.
@export var difficulty_curve: Curve
## Base item card icon scene used to display item cards in the UpgradeShop.
@export var upgrade_icon_scene: PackedScene
## Damage gear item resource offered by the UpgradeShop.
@export var item_damage: ItemResource
## Health gear item resource offered by the UpgradeShop.
@export var item_health: ItemResource
## Speed gear item resource offered by the UpgradeShop.
@export var item_speed: ItemResource
## Health potion consumable item resource offered by the UpgradeShop.
@export var item_potion: ItemResource

## Convenience aliases for item exports
var upgrade_damage: ItemResource:
	get: return item_damage
	set(val): item_damage = val
var upgrade_health: ItemResource:
	get: return item_health
	set(val): item_health = val
var upgrade_speed: ItemResource:
	get: return item_speed
	set(val): item_speed = val
var upgrade_potion: ItemResource:
	get: return item_potion
	set(val): item_potion = val

## Enemy resources available for spawning, each defining an enemy scene and difficulty level.
@export var enemies: Array[EnemyResource] = []
## Dungeon resources available for progression, each defining a level scene and eligibility constraints.
@export var dungeons: Array[DungeonResource] = []
## Projectile scene spawned by ProjectileSpawnerComponent.
@export var enemy_projectile_scene: PackedScene
## Firebomb projectile scene spawned by ProjectileSpawnerComponent.
@export var firebomb_projectile_scene: PackedScene
## Lightning bolt projectile scene spawned by ProjectileSpawnerComponent.
@export var lightning_bolt_scene: PackedScene
## Impact effect spawned by EnemyProjectile on collision.
@export var fireball_hit_scene: PackedScene
## Impact effect spawned by LightningBoltProjectile on collision.
@export var lightning_hit_scene: PackedScene
## Floating combat text spawned by VfxManager on damage.
@export var damage_number_scene: PackedScene
## Player-only target reticle spawned once by VfxManager. Enemies never spawn it.
@export var target_reticle_scene: PackedScene
## Shop scene opened by ExitPoint when no explicit next scene is set.
@export var upgrade_shop_scene: PackedScene
## Pause menu overlay scene displayed when the game is paused.
@export var pause_menu_scene: PackedScene

## Item resources offered by the UpgradeShop, built from the exported item resources.
var items: Array[ItemResource] = []

## Array of items offered by the shop (alias for items).
var upgrades: Array[ItemResource]:
	get: return items
	set(val): items = val


func _ready() -> void:
	items = [item_damage, item_health, item_speed, item_potion]


## Finds the registered EnemyResource for a given PackedScene or null if not registered.
func get_enemy_resource(scene: PackedScene) -> EnemyResource:
	for res: EnemyResource in enemies:
		if res != null and res.scene == scene:
			return res
	return null
