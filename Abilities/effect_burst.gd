## A payload that applies GameplayEffects, once, to every living character on
## one side within radius of where it spawns, then shows its ring expanding to
## that radius and frees itself. The side is relative to its wielder (the
## caster, set by PayloadSpawner): its allies, its foes, or everyone. It deals
## no damage and lands no hit (no stun, flash or hit sound), so buffs, heals
## and debuffs from abilities any character casts all use it: an enemy's
## burst reaches enemies, the same ability cast by the player reaches the
## player.
class_name EffectBurst
extends Node3D

## Which characters a burst reaches, relative to its wielder.
enum TeamFilter {
	ALLIES, ## The wielder's team (players for a player, enemies for an enemy).
	FOES, ## The other team.
	ALL, ## Both teams.
}

## Emitted once the effects were applied, with every character they reached.
signal burst(characters: Array[Character])

## Effects applied to each character reached.
@export var effects: Array[GameplayEffect] = []
## Which side the burst reaches.
@export var affects: TeamFilter = TeamFilter.ALLIES
## Whether the wielder itself is reached (when it is on the affected side).
@export var include_wielder: bool = true
## Horizontal reach in meters from the burst's center.
@export var radius: float = 6.0
## Vertical reach in meters above and below the burst's center.
@export var height: float = 2.5
## Ring scaled out to radius while the burst shows (unit radius mesh).
@export var ring: GeometryInstance3D
## Seconds the ring takes to expand and fade before the burst frees itself
## (render clock: purely visual).
@export var visual_duration: float = 0.6

## The character that cast the burst; null reaches nobody unless affects is
## ALL.
var wielder: Character = null


func _ready() -> void:
	# Deferred: the spawner places the burst in world space after adding it.
	_apply.call_deferred()
	_show_ring()


## The characters the burst reaches from where it stands now.
func get_reached_characters() -> Array[Character]:
	var reached: Array[Character] = []
	for group: String in _affected_groups():
		for node: Node in get_tree().get_nodes_in_group(group):
			var character: Character = node as Character
			if character == null or not character.is_alive() or (character == wielder and not include_wielder):
				continue
			var offset: Vector3 = character.global_position - global_position
			if Vector2(offset.x, offset.z).length() <= radius and absf(offset.y) <= height:
				reached.append(character)
	return reached


func _apply() -> void:
	if not is_inside_tree():
		return
	var reached: Array[Character] = get_reached_characters()
	for character: Character in reached:
		if character.attribute_component == null:
			continue
		for effect: GameplayEffect in effects:
			if effect != null:
				character.attribute_component.apply_effect(effect)
	burst.emit(reached)


## The team groups on the affected side.
func _affected_groups() -> Array[String]:
	if affects == TeamFilter.ALL:
		return ["player", "enemy"]
	if wielder == null:
		push_warning("EffectBurst: no wielder, so no allies or foes to reach.")
		return []
	var own: String = "enemy" if wielder.is_enemy() else "player"
	if affects == TeamFilter.ALLIES:
		return [own]
	return [wielder.get_opposing_group()]


func _show_ring() -> void:
	get_tree().create_timer(visual_duration).timeout.connect(queue_free)
	if ring == null:
		return
	ring.scale = Vector3.ONE * 0.1
	ring.transparency = 0.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), visual_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ring, "transparency", 1.0, visual_duration).set_ease(Tween.EASE_IN)
