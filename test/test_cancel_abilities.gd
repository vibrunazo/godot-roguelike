## Character.cancel_movement_and_abilities() (run when the player is carried
## into a new level):
## - clears temporary status effects together with their visuals,
## - leaves every other node alone, whatever it is named.
## (Regression: it used to free any descendant whose name started with
## "Status" or contained "burning", e.g. a UI node called StatusBar.)
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const BURN_EFFECT: GameplayEffect = preload("res://Components/effect_fire_burn.tres")

var _player: Character


func before_each() -> void:
	var arena: Node3D = load_arena()
	_player = spawn(PLAYER_SCENE, arena, (arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	await wait_physics_frames(1)


func test_cancel_clears_status_effects_and_their_visuals() -> void:
	var attributes: AttributeComponent = _player.attribute_component
	var instance_id: StringName = attributes.apply_effect(BURN_EFFECT)
	if not check(instance_id != &"", "setup: the burn should apply"):
		return
	var visual_ref: WeakRef = weakref(_find_new_visual())
	if not check(visual_ref.get_ref() != null, "setup: the burn should show its status visual"):
		return
	_player.cancel_movement_and_abilities()
	var health_after_cancel: float = attributes.get_current(AttributeComponent.POOL_HEALTH)
	await wait_until(func() -> bool: return visual_ref.get_ref() == null, "cancelling should free the status visual")
	await wait_physics_frames(ceili(Engine.physics_ticks_per_second))
	check_approx(attributes.get_current(AttributeComponent.POOL_HEALTH), health_after_cancel, "a cancelled burn must stop dealing damage")


func test_cancel_leaves_unrelated_nodes_alone_whatever_their_name() -> void:
	var survivors: Array[Node3D] = []
	for node_name: String in ["StatusBar", "StatusIcon", "BurningTorch", "unburning_candle"]:
		var node: Node3D = Node3D.new()
		node.name = node_name
		_player.add_child(node)
		survivors.append(node)
	_player.cancel_movement_and_abilities()
	await wait_physics_frames(2)
	for node: Node3D in survivors:
		if check(is_instance_valid(node) and not node.is_queued_for_deletion(), "cancelling must not free an unrelated node just because of its name"):
			check(node.visible, "cancelling must not hide an unrelated node just because of its name (%s)" % node.name)


## The status visual the burn just added somewhere under the player.
func _find_new_visual() -> Node:
	for node: Node in _player.find_children("*", "StatusBurning", true, false):
		return node
	return null
