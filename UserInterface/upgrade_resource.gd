## Data resource defining a shop upgrade's metadata, text formatting, and gameplay effect.
class_name UpgradeResource
extends Resource

enum UpgradeType {
	STAT,         ## Applies bonus to a Character property via Character.set()
	MAX_HEALTH,   ## Raises the AttributeComponent max_health base and heals the pool by the bonus
	HEAL_PERCENT, ## Restores the AttributeComponent health pool by a percentage of max_health
}

## Display title of the upgrade, e.g. "[wave]Damage[/wave]".
@export var title: String = ""

## BBCode text template for the upgrade description with format specifiers for current and new values.
## e.g. "%d%% -> [color='7fffd4']%d%%[/color] damage" or "%.1f -> [color=\"7fffd4\"]%.1f[/color] m/s"
@export_multiline var text_template: String = ""

## Type of upgrade behavior.
@export var upgrade_type: UpgradeType = UpgradeType.STAT

## Target stat property name on Character when upgrade_type is STAT (e.g. "damage_stat", "movement_speed").
@export var stat_name: String = ""

## Numeric bonus added to the stat or health (e.g. 50.0 for 50% heal or +50 damage stat).
@export var stat_bonus: float = 0.0

## Optional icon texture if icons are displayed in the UI.
@export var icon: Texture2D


## Returns the player's current value for this upgrade's target stat or health.
## Health values read from the player's AttributeComponent, the single home
## for health numbers.
func get_current_value(player: Character) -> float:
	if player == null:
		return 0.0
	match upgrade_type:
		UpgradeType.STAT:
			var val: Variant = player.get(stat_name)
			return float(val) if val != null else 0.0
		UpgradeType.MAX_HEALTH:
			if player.attribute_component != null:
				return player.attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
		UpgradeType.HEAL_PERCENT:
			if player.attribute_component != null:
				return player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	return 0.0


## Returns the projected value after taking this upgrade.
func get_upgraded_value(player: Character) -> float:
	if player == null:
		return 0.0
	match upgrade_type:
		UpgradeType.STAT, UpgradeType.MAX_HEALTH:
			return get_current_value(player) + stat_bonus
		UpgradeType.HEAL_PERCENT:
			if player.attribute_component != null:
				var attrs: AttributeComponent = player.attribute_component
				var ratio: float = stat_bonus / 100.0 if stat_bonus > 1.0 else stat_bonus
				var heal_amount: float = attrs.get_current(AttributeComponent.STAT_MAX_HEALTH) * ratio
				return minf(attrs.get_current(AttributeComponent.STAT_MAX_HEALTH), attrs.get_current(AttributeComponent.POOL_HEALTH) + heal_amount)
	return get_current_value(player) + stat_bonus


## Formats the description text for display in the UI.
func format_description(player: Character) -> String:
	if text_template.is_empty():
		return ""
	if player == null or text_template.find("%") == -1:
		return text_template
	var current_val: float = get_current_value(player)
	var next_val: float = get_upgraded_value(player)
	return text_template % [current_val, next_val]


## Applies this upgrade to the given player Character. Health upgrades write
## the AttributeComponent directly: MAX_HEALTH raises the max base and heals
## the pool by the bonus, HEAL_PERCENT restores the pool by a max fraction.
func apply(player: Character) -> void:
	if player == null:
		return
	match upgrade_type:
		UpgradeType.STAT:
			if not stat_name.is_empty():
				player.set(stat_name, get_current_value(player) + stat_bonus)
		UpgradeType.MAX_HEALTH:
			if player.attribute_component != null:
				var attrs: AttributeComponent = player.attribute_component
				attrs.set_base(AttributeComponent.STAT_MAX_HEALTH, attrs.get_base(AttributeComponent.STAT_MAX_HEALTH) + stat_bonus)
				attrs.restore_pool(AttributeComponent.POOL_HEALTH, stat_bonus)
		UpgradeType.HEAL_PERCENT:
			if player.attribute_component != null:
				var attrs_heal: AttributeComponent = player.attribute_component
				var ratio: float = stat_bonus / 100.0 if stat_bonus > 1.0 else stat_bonus
				attrs_heal.restore_pool(AttributeComponent.POOL_HEALTH, attrs_heal.get_current(AttributeComponent.STAT_MAX_HEALTH) * ratio)
