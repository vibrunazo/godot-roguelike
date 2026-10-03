## HUD row of the player's active ability slots (one AbilitySlotWidget per
## slot, always built for every slot), bound to each level's fresh player by
## the HUD. Shows each slot's ability, its cooldown and the key that casts it,
## read from the InputMap so rebinding updates the bar by itself. Only slots
## holding an ability show (the bar hides while none does) unless
## show_empty_slots is on, so a screen that arranges abilities can show the
## empty ones too. When the bound player leaves the tree
## (its level unloads, e.g. for the shop) the bar keeps showing the run's slots,
## all ready: each level's fresh player starts with every ability off cooldown.
## Purely visual (render clock).
class_name AbilityBar
extends HBoxContainer

## Widget scene instanced once per ability slot.
@export var slot_widget_scene: PackedScene
## Whether empty slots show (as empty frames with their key). Off: only
## filled slots show, and the bar hides itself while every slot is empty.
@export var show_empty_slots: bool = false:
	set(value):
		show_empty_slots = value
		_update_visibility()

var _abilities: AbilitySystemComponent = null
var _widgets: Array[AbilitySlotWidget] = []
## The slot-change listeners, kept so a re-bind disconnects exactly them.
var _on_granted: Callable = _on_slot_granted
var _on_revoked: Callable = _on_slot_revoked
var _on_exiting: Callable = _on_abilities_exiting


func _ready() -> void:
	if slot_widget_scene == null:
		push_error("AbilityBar: slot_widget_scene is not set.")
	visible = false


## Shows player's ability slots (see show_empty_slots). Binding again
## (the same player or a new one) replaces the previous binding.
func bind(player: Character) -> void:
	_unbind()
	_abilities = player.ability_system_component if player != null else null
	for widget: AbilitySlotWidget in _widgets:
		widget.queue_free()
	_widgets.clear()
	if _abilities == null or slot_widget_scene == null:
		visible = false
		return
	var actions: Array[StringName] = _ability_actions(player)
	for slot: int in _abilities.get_slot_count():
		var widget: AbilitySlotWidget = slot_widget_scene.instantiate() as AbilitySlotWidget
		add_child(widget)
		widget.set_key_text(_key_text(actions[slot]) if slot < actions.size() else "")
		widget.set_ability(_abilities.get_ability(slot))
		_widgets.append(widget)
	_abilities.ability_granted.connect(_on_granted)
	_abilities.ability_revoked.connect(_on_revoked)
	_abilities.tree_exiting.connect(_on_exiting)
	_update_visibility()


## Stops listening to the previously bound slots.
func _unbind() -> void:
	if _abilities != null and is_instance_valid(_abilities):
		if _abilities.ability_granted.is_connected(_on_granted):
			_abilities.ability_granted.disconnect(_on_granted)
		if _abilities.ability_revoked.is_connected(_on_revoked):
			_abilities.ability_revoked.disconnect(_on_revoked)
		if _abilities.tree_exiting.is_connected(_on_exiting):
			_abilities.tree_exiting.disconnect(_on_exiting)
	_abilities = null


## Number of slot widgets (one per slot, shown or not).
func get_slot_count() -> int:
	return _widgets.size()


## The widget showing slot.
func get_widget(slot: int) -> AbilitySlotWidget:
	return _widgets[slot]


func _process(_delta: float) -> void:
	if _abilities == null or not is_instance_valid(_abilities):
		return
	for slot: int in _widgets.size():
		_widgets[slot].set_cooldown(_abilities.get_cooldown_fraction(slot), _abilities.is_ready(slot))


func _on_slot_granted(slot: int, _ability: AbilityResource, _source: Object) -> void:
	_refresh_slot(slot)


func _on_slot_revoked(slot: int, _ability: AbilityResource) -> void:
	_refresh_slot(slot)


## The bound player is leaving with its level: stop following it and show
## every slot ready, as the next level's player will have them.
func _on_abilities_exiting() -> void:
	_unbind()
	for widget: AbilitySlotWidget in _widgets:
		widget.set_cooldown(0.0, true)


func _refresh_slot(slot: int) -> void:
	if slot < _widgets.size():
		_widgets[slot].set_ability(_abilities.get_ability(slot))
	_update_visibility()


## Shows the widgets of filled slots (every one with show_empty_slots), and
## the bar while any widget shows.
func _update_visibility() -> void:
	var any_shown: bool = false
	for widget: AbilitySlotWidget in _widgets:
		widget.visible = show_empty_slots or widget.is_filled()
		any_shown = any_shown or widget.visible
	visible = any_shown


## The InputMap actions the player's controller casts slots with.
func _ability_actions(player: Character) -> Array[StringName]:
	for child: Node in player.find_children("*", "PlayerInputComponent", false):
		return (child as PlayerInputComponent).ability_actions
	return []


## Display text of the first key bound to action ("" when none).
func _key_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			return OS.get_keycode_string(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
	return ""
