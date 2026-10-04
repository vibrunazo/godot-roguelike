## Data definition of one active ability (Fireball, Laser Eyes, ...): what it
## is, what it costs, how it is cast and what it releases. A character casts
## it from one of its ability slots (AbilityCastState), granted through its
## AbilitySystemComponent by a book, a piece of gear or its starting_abilities.
## Balance lives here and in the payload scene, never in code. The ability has
## no damage numbers of its own: damage lives in the payload scene (a
## projectile's or damage area's AttackComponent), tuned per ability through
## payload_overrides.
## Tool-enabled so item cards in the editor can read its display name.
@tool
class_name AbilityResource
extends Resource

## Where a cast releases its payload (see release_point).
enum ReleasePoint {
	CAST_ORIGIN, ## The slot's cast_origin (a hand, a chest-height marker): projectiles.
	CASTER_FEET, ## The floor under the caster: ground areas centered on it (a quake).
}

@export_group("Identity")
## Unique identifier for this ability.
@export var id: StringName = &""
## Name shown in the HUD, item cards and book covers (e.g. "Fireball").
@export var display_name: String = ""
## Flavor text only; numbers are never hand-written here.
@export_multiline var description: String = ""
## Icon shown in the HUD ability bar.
@export var icon: Texture2D
## Identity tags broadcast with the cast's lifecycle events (e.g.
## &"ability.spell.fire"), so granted passives can react to it.
@export var ability_tags: Array[StringName] = []

@export_group("Activation")
## Seconds before the ability can be cast again.
@export var cooldown: float = 1.0
## Cooldown applied when the ability is granted (0.0 = ready at once).
@export var starting_cooldown: float = 0.0
## Pool paid on each cast (AttributeComponent.POOL_MANA, ...). Ignored while
## cost_amount is 0.
@export var cost_pool: StringName = AttributeComponent.POOL_MANA
## Amount of cost_pool paid on each cast (0.0 = free).
@export var cost_amount: float = 0.0
## Gameplay tags the caster needs for the ability to be castable.
@export var required_tags: Array[StringName] = []
## Gameplay tags that stop the ability from being cast.
@export var blocked_tags: Array[StringName] = []

@export_group("Casting")
## AnimationTree state played by the cast (the caster's tree must have it).
@export var cast_animation: String = "CastSpell"
## Playback speed of cast_animation (2.0 plays it twice as fast, so the cast,
## which lasts as long as its animation, ends twice as soon). Needs the
## caster's AnimationTree state to be a BlendTree with a TimeScale node (as
## CastSpell and Rally are). release_time is not scaled: set it in cast
## seconds.
@export var cast_speed: float = 1.0
## Seconds into the cast when the payload is released (physics clock).
@export var release_time: float = 0.3
## Speed in m/s the caster can steer at while casting (0.0 = stand still).
@export var movement_speed: float = 0.0
## Whether a dash, jump or another ability may cancel the cast once it has
## released its payload (before release the cast is committed to anything
## but a dash).
@export var cancelable: bool = true
## Whether the cast shrugs off stuns (hits still hurt).
@export var uninterruptable: bool = false
## Whether the caster keeps its height while casting in the air.
@export var float_in_air: bool = false

@export_group("Release")
## Where the payload spawns: at the slot's cast_origin, or on the floor at
## the caster's feet.
@export var release_point: ReleasePoint = ReleasePoint.CAST_ORIGIN
## How the release is aimed at the cast's aim (CharacterAction.aim_mode:
## AIMED at what the caster sees at its cast height above the aimed floor,
## FLAT level at cast height, GROUND at the floor point, where a lob lands).
@export var aim_mode: CharacterAction.AimMode = CharacterAction.AimMode.AIMED
## Aim assist around the cursor, in meters: when the caster aims at a floor
## point (the player's cursor), the cast locks onto the foe closest to that
## point within this radius, ahead of the auto-aim target (nearest to the
## caster); with none, it falls back to auto-aim, then to the point itself.
## 0.0 turns it off.
@export var aim_assist_radius: float = 3.0
## Scene spawned at release through PayloadSpawner: a projectile, a damage
## area, a visual... Null releases no payload.
@export var payload_scene: PackedScene
## Property patches applied to the payload before it enters the tree (e.g. a
## projectile's damage or speed), so one payload scene serves many abilities.
@export var payload_overrides: Array[PayloadPropertyOverride] = []
## Multiplier on the payload's damage before attack scaling.
@export var damage_multiplier: float = 1.0
## Scale the payload's damage by the caster's attack stat (the formula melee
## attacks use).
@export var scale_with_attack: bool = true
## GameplayEffects applied to the caster at release (haste, shields, ...).
@export var caster_effects: Array[GameplayEffect] = []
