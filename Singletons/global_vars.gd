## Default global asset references, registered as the `GlobalVars` autoload (scene
## `Singletons/global_vars.tscn`) in `project.godot`. Access from anywhere via
## `GlobalVars`, e.g. `GlobalVars.items`.
##
## Unique responsibility: hold default global references to scenes and resources
## used elsewhere in the game. Individual nodes may override these locally via
## their own `@export`s (falling back to the registry when unset). Anything that
## is not a shared default reference — run state, difficulty math, input,
## display, spawning — belongs in another autoload (`ProgressionState`, `UI`,
## `VfxManager`, `SceneTransition`), never here.
extends Node

## Legacy difficulty scaling curve.
@export var difficulty_curve: Curve
## Base item card icon scene used to display item cards in the UpgradeShop.
@export var upgrade_icon_scene: PackedScene
## Item resources offered by the UpgradeShop (e.g. damage, health, speed, potion,
## wing boots). Add or remove entries here to change the shop's item pool.
@export var items: Array[ItemResource] = []

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
## HUD overlay scene displayed during gameplay levels.
@export var hud_scene: PackedScene
## Level title overlay scene displayed when entering a level.
@export var level_title_overlay_scene: PackedScene


## Finds the registered EnemyResource for a given PackedScene or null if not registered.
func get_enemy_resource(scene: PackedScene) -> EnemyResource:
	for res: EnemyResource in enemies:
		if res != null and res.scene == scene:
			return res
	return null
