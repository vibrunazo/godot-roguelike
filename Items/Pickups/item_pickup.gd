## An item lying in a level, for the player to walk over and take. Generic for
## every item: it shows the item's world_visual (an ItemDisplay) bobbing over
## a floor marker, and on contact applies the item through the player's
## EquipmentComponent (a book teaches its ability, gear equips, ...). An item
## the player cannot take yet (an ability already known, no free slot) stays
## on the floor with a short message. Every pickup in the tree is in GROUP,
## so droppers can tell whether an item already lies somewhere in the level
## (is_lying_in()).
class_name ItemPickup
extends Area3D

## Group of every ItemPickup in the tree.
const GROUP: StringName = &"item_pickups"

## Emitted when a character took the item.
signal picked_up(item: ItemResource, character: Character)

## The item lying here.
@export var item: ItemResource:
	set(value):
		item = value
		if is_node_ready():
			_show_item()
## Node the item's world visual is instanced under; it bobs.
@export var visual_root: Node3D
## Sound played when the item is taken.
@export var pickup_audio: AudioStreamPlayer3D
## Bob amplitude (meters) and frequency (cycles per second) of the visual.
@export var bob_height: float = 0.08
@export var bob_frequency: float = 0.5
## Height above the pickup the messages float up from, in meters.
@export var message_height: float = 1.6
## Seconds before a refused pickup may show its message again.
@export var refusal_message_interval: float = 2.0

var _display: ItemDisplay = null
var _taken: bool = false
var _visual_base_height: float = 0.0
var _bob_time: float = 0.0
var _last_refusal_time: float = -INF


## Whether a pickup of lying_item, not taken yet, lies anywhere in tree.
static func is_lying_in(tree: SceneTree, lying_item: ItemResource) -> bool:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var pickup: ItemPickup = node as ItemPickup
		if pickup != null and not pickup._taken and not pickup.is_queued_for_deletion() and pickup.item == lying_item:
			return true
	return false


## The floor surface under point (navmesh points lie a little above the
## floor), or point itself when no floor on floor_mask is hit within 2 m.
static func floor_below(world: World3D, point: Vector3, floor_mask: int) -> Vector3:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.DOWN * 2.0, floor_mask)
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit["position"] as Vector3 if not hit.is_empty() else point


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if visual_root == null:
		push_error("ItemPickup '%s': visual_root is not set." % name)
		return
	_visual_base_height = visual_root.position.y
	body_entered.connect(_on_body_entered)
	_show_item()


## The world visual showing the item (null before it is shown).
func get_display() -> ItemDisplay:
	return _display


## Gives the item to character when it can take it. Returns whether it did.
func try_pick_up(character: Character) -> bool:
	if _taken or item == null or character == null or character.equipment_component == null:
		return false
	if not character.equipment_component.apply_item(item):
		_show_refusal(character)
		return false
	_taken = true
	VfxManager.spawn_floating_text(global_position + Vector3.UP * message_height, _pickup_message())
	picked_up.emit(item, character)
	_play_detached_sound()
	queue_free()
	return true


func _process(delta: float) -> void:
	if visual_root == null:
		return
	_bob_time += delta
	visual_root.position.y = _visual_base_height + sin(_bob_time * TAU * bob_frequency) * bob_height


## Hands the pickup sound to the level, so it plays out after the pickup is
## gone, and frees it once the stream has had time to finish.
func _play_detached_sound() -> void:
	if pickup_audio == null or pickup_audio.stream == null or get_parent() == null:
		return
	var sound: AudioStreamPlayer3D = pickup_audio
	var at: Vector3 = sound.global_position
	sound.get_parent().remove_child(sound)
	get_parent().add_child(sound)
	sound.global_position = at
	sound.play()
	get_tree().create_timer(sound.stream.get_length()).timeout.connect(sound.queue_free)


func _show_item() -> void:
	if _display != null:
		_display.queue_free()
		_display = null
	if item == null or visual_root == null:
		return
	if item.world_visual == null:
		push_error("ItemPickup: item '%s' has no world_visual." % item.id)
		return
	_display = item.world_visual.instantiate() as ItemDisplay
	if _display == null:
		push_error("ItemPickup: world_visual of '%s' must have an ItemDisplay root." % item.id)
		return
	visual_root.add_child(_display)
	_display.show_item(item)


func _on_body_entered(body: Node3D) -> void:
	var character: Character = body as Character
	if character != null and character.is_player():
		try_pick_up(character)


## "Learned: Fireball" for an item teaching abilities or passives, else the
## item's name.
func _pickup_message() -> String:
	var names: Array[String] = item.get_taught_names()
	if not names.is_empty():
		return "Learned: %s" % ", ".join(names)
	return item.get_plain_title()


## Why character cannot take the item right now, shown at most once per
## refusal_message_interval.
func _show_refusal(character: Character) -> void:
	if _bob_time - _last_refusal_time < refusal_message_interval:
		return
	_last_refusal_time = _bob_time
	var message: String = "Can't take this now"
	var asc: AbilitySystemComponent = character.ability_system_component
	if item.teaches_anything() and asc != null:
		message = "Already learned" if asc.has_free_slot() or item.granted_abilities.is_empty() else "No free ability slot"
	VfxManager.spawn_floating_text(global_position + Vector3.UP * message_height, message)
