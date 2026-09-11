## Data resource defining a shop upgrade's metadata, text formatting, and gameplay effect.
class_name UpgradeResource
extends Resource

enum UpgradeType {
	STAT,         ## Applies bonus to a Character property via Character.set()
	MAX_HEALTH,   ## Modifies Character.health_component.max_health and current_health
	HEAL_PERCENT, ## Heals Character.health_component.current_health by a percentage of max_health
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
func get_current_value(player: Character) -> float:
	if player == null:
		return 0.0
	match upgrade_type:
		UpgradeType.STAT:
			var val: Variant = player.get(stat_name)
			return float(val) if val != null else 0.0
		UpgradeType.MAX_HEALTH:
			if player.health_component != null:
				return player.health_component.max_health
		UpgradeType.HEAL_PERCENT:
			if player.health_component != null:
				return player.health_component.current_health
	return 0.0


## Returns the projected value after taking this upgrade.
func get_upgraded_value(player: Character) -> float:
	if player == null:
		return 0.0
	match upgrade_type:
		UpgradeType.STAT, UpgradeType.MAX_HEALTH:
			return get_current_value(player) + stat_bonus
		UpgradeType.HEAL_PERCENT:
			if player.health_component != null:
				var ratio: float = stat_bonus / 100.0 if stat_bonus > 1.0 else stat_bonus
				var heal_amount: float = player.health_component.max_health * ratio
				return minf(player.health_component.max_health, player.health_component.current_health + heal_amount)
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


## Applies this upgrade to the given player Character.
func apply(player: Character) -> void:
	if player == null:
		return
	match upgrade_type:
		UpgradeType.STAT:
			if not stat_name.is_empty():
				player.set(stat_name, get_current_value(player) + stat_bonus)
		UpgradeType.MAX_HEALTH:
			if player.health_component != null:
				player.health_component.max_health += stat_bonus
				player.health_component.current_health += stat_bonus
		UpgradeType.HEAL_PERCENT:
			if player.health_component != null:
				var ratio: float = stat_bonus / 100.0 if stat_bonus > 1.0 else stat_bonus
				var heal_amount: float = player.health_component.max_health * ratio
				player.health_component.current_health = minf(
					player.health_component.max_health,
					player.health_component.current_health + heal_amount
				)
