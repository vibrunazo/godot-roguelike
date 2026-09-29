## Backpack rider controller for the Akira boss.
## Drives the two melee riders mounted on the boss waist: they idle in
## WalkSpace and side-slash with melee-equal swords when the player comes
## close, by switching their AnimationTree to its SideSlash state, which
## returns to WalkSpace on its own when the swing ends. The slash animation
## carries its own WeaponSlot:enabled track, opening a large hitbox zone
## around the rider so approaching is costly, while the slot's Slash
## attack_mode drives a player-style fire SlashVFX quad and fire-slash audio. Riders are visual
## AnimatedEnemy rigs (legs hidden, torso up out of primitive backpacks),
## not full Characters.
class_name AkiraBossRiders
extends Node

## Boss character carrying the riders. Used for liveness and target lookup.
@export var character: Character
## AnimationTree of the left backpack rider.
@export var left_rider_tree: MannequinAnimationTree
## AnimationTree of the right backpack rider.
@export var right_rider_tree: MannequinAnimationTree
## Rider AnimationTree state that plays the side-slash.
@export var slash_state: StringName = &"SideSlash"
## Node3D root of the left rider (for distance checks to the player).
@export var left_rider_root: Node3D
## Node3D root of the right rider (for distance checks to the player).
@export var right_rider_root: Node3D
## Distance in meters from a rider to the player that triggers a sword swing.
@export var attack_range: float = 2.8
## Cooldown in seconds between sword swings per rider.
@export var attack_cooldown: float = 1.6

var _left_cooldown: float = 0.0
var _right_cooldown: float = 0.0
var _has_riders: bool = true


func _ready() -> void:
	if character == null:
		character = get_parent() as Character
	_hide_rider_legs()
	for rider_tree: MannequinAnimationTree in [left_rider_tree, right_rider_tree]:
		if rider_tree != null:
			rider_tree.change_immediate("WalkSpace")
	if character != null and character.attribute_component != null:
		character.attribute_component.tag_added.connect(_on_tag_added)
		character.attribute_component.tag_removed.connect(_on_tag_removed)
		_has_riders = character.has_tag(&"has_riders")
		_apply_rider_presence()


func _on_tag_added(tag: StringName) -> void:
	if tag == &"has_riders":
		attach_riders()


func _on_tag_removed(tag: StringName) -> void:
	if tag == &"has_riders":
		detach_riders()


## Returns true if riders are currently attached to the boss backpack.
func has_riders() -> bool:
	return _has_riders


## Detaches riders: hides rider visuals and disables their melee defense.
func detach_riders() -> void:
	_has_riders = false
	_apply_rider_presence()


## Attaches riders: unhides rider visuals and restores their melee defense.
func attach_riders() -> void:
	_has_riders = true
	_apply_rider_presence()


func _apply_rider_presence() -> void:
	# A detached rider must not finish a swing (its slash keys the hitbox on).
	for rider_tree: MannequinAnimationTree in [left_rider_tree, right_rider_tree]:
		if rider_tree != null:
			rider_tree.change_immediate("WalkSpace")
	for root: Node3D in [left_rider_root, right_rider_root]:
		if root != null and is_instance_valid(root):
			root.visible = _has_riders
			var slot: WeaponSlot = root.find_child("WeaponSlot", true, false) as WeaponSlot
			if slot != null:
				slot.enabled = false


func _physics_process(delta: float) -> void:
	if _left_cooldown > 0.0:
		_left_cooldown = maxf(0.0, _left_cooldown - delta)
	if _right_cooldown > 0.0:
		_right_cooldown = maxf(0.0, _right_cooldown - delta)
	if not _has_riders:
		return
	if character == null or not is_instance_valid(character):
		return
	if not character.is_inside_tree() or not character.is_alive():
		return
	var player: Character = character.get_nearest_target("player")
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return
	_try_rider_attack(true, player)
	_try_rider_attack(false, player)


## Checks range and cooldown for one rider and triggers its sword swing.
func _try_rider_attack(is_left: bool, player: Character) -> void:
	if not _has_riders:
		return
	var rider_root: Node3D = left_rider_root if is_left else right_rider_root
	var rider_tree: MannequinAnimationTree = left_rider_tree if is_left else right_rider_tree
	var cooldown: float = _left_cooldown if is_left else _right_cooldown
	if rider_root == null or rider_tree == null:
		return
	if cooldown > 0.0 or is_rider_swinging(is_left):
		return
	if not rider_root.is_inside_tree():
		return
	var dist_sq: float = rider_root.global_position.distance_squared_to(player.global_position)
	if dist_sq > attack_range * attack_range:
		return
	_play_rider_attack(is_left)


## Switches the rider's tree to its side-slash state and starts its cooldown.
## The slash resource drives WeaponSlot:enabled itself (0.2s-0.4s window).
func _play_rider_attack(is_left: bool) -> void:
	var rider_tree: MannequinAnimationTree = left_rider_tree if is_left else right_rider_tree
	var rider_root: Node3D = left_rider_root if is_left else right_rider_root
	if rider_tree == null or rider_root == null or is_rider_swinging(is_left):
		return
	if not rider_tree.is_inside_tree():
		return
	# Fresh hit exceptions every swing: riders own no CharacterAttack state to
	# reset for them, so without this only the first swing could ever land.
	# The boss stays excluded as wielder (mask + ancestry check) regardless.
	var slot: WeaponSlot = rider_root.find_child("WeaponSlot", true, false) as WeaponSlot
	if slot != null and slot.hitbox != null:
		var att: AttackComponent = slot.hitbox.get_node_or_null("AttackComponent") as AttackComponent
		if att != null:
			att.reset_exceptions()
			if character != null and is_instance_valid(character):
				att.add_exception(character)
	rider_tree.change_immediate(slash_state)
	if is_left:
		_left_cooldown = attack_cooldown
	else:
		_right_cooldown = attack_cooldown


## Returns true while the given rider's tree is in its side-slash state
## (from the tree's next physics step after the swing starts).
func is_rider_swinging(is_left: bool) -> bool:
	var rider_tree: MannequinAnimationTree = left_rider_tree if is_left else right_rider_tree
	if rider_tree == null or rider_tree.playback == null:
		return false
	return rider_tree.playback.get_current_node() == slash_state


## Hides leg meshes on both riders so they read as torso-up in backpacks.
## Scene file already sets visible=false; this is a runtime fallback in case
## instanced overrides fail to apply on some import configurations.
func _hide_rider_legs() -> void:
	for rider_root: Node in [left_rider_root, right_rider_root]:
		if rider_root == null:
			continue
		for leg_name: String in ["Enemy_Medium_LegLeft", "Enemy_Medium_LegRight"]:
			var leg: MeshInstance3D = rider_root.find_child(leg_name, true, false) as MeshInstance3D
			if leg != null:
				leg.visible = false


## Returns true when the given rider is ready to swing (in range bookkeeping helper for tests).
func is_rider_ready(is_left: bool) -> bool:
	if not _has_riders:
		return false
	if is_left:
		return _left_cooldown <= 0.0
	return _right_cooldown <= 0.0


## Forces a rider swing regardless of range, used by tests and debug captures.
func force_rider_attack(is_left: bool) -> void:
	_play_rider_attack(is_left)
