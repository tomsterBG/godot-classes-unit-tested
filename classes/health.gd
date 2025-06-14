# IMPORTANT:
# Make it performant and useful in many places.
# Type all variables, parameters and returns.
# Keep complete documentation.
# INFO:
# This works without knowing about other nodes. Knowing is optional.
# TODO:
# IDEAS:
# - More signals: damaged(DamageResult), healed(HealResult), shields_became_cyclic() -> bool.
# - Shield methods? what if revive() method would propagate through all shields.
# - Add an automatically updated variable shield_of or parent_health or parent_of, it holds the health this shield is a shield of.
# - Add absorbed_damage to DamageResult.

## @experimental: This class is immature.
## Health for anything that can live and die.
##
## Widely applicable for most health stuff. See also [HealthPlus].
##[br][br][b]Note:[/b] Can have a shield, and that shield can have its own shield!

@tool
@icon("health.svg")
class_name Health
extends Node


#region signals
## Emitted on death. See [member is_dead].
signal died()

## Emitted when [member health] changes. Positive [param difference] means healed, negative means damaged.
signal health_changed(difference: float)
#endregion signals


#region enums
## Controls the order in which resistances are applied. 
enum ResistanceOrder {
	## First reduce damage by [member resistance_percent], then by [member resistance_flat].
	##[br][br][b]Note:[/b] This resists more damage if [member resistance_percent] is not [param 0].
	PERCENT_FLAT,
	## First reduce damage by [member resistance_flat], then by [member resistance_percent].
	##[br][br][b]Note:[/b] This resists less damage if [member resistance_percent] is not [param 0].
	FLAT_PERCENT,
}
#endregion enums


#region classes
## The result returned by [method Health.damage].
class DamageResult:
	## If [member Health.shield] is set, its [method Health.damage] method is called and this is what it returns.
	var shield_result: DamageResult
	## The damage taken by this [Health].
	var taken_damage: float
	## The remaining damage. If this is a [member Health.shield], its parent [Health] will take the damage.
	var remaining_damage: float
#endregion classes


#region variables
@export_group("Health")

## Clamped between [param 0 and max_health]. If this reaches [param 0], [method kill] is called.
@export var health := 100.0: set = set_health

## Can't be less than [param 0] because of [member health]. If this reaches [param 0], [member health] will also reach [param 0].
@export var max_health := 100.0: set = set_max_health

#region resistances
@export_group("Resistance", "resistance_")

## Reduces incoming damage by this number. Used when calling [method damage] and ignored when setting [member health] directly.
@export var resistance_flat := 0.0: set = set_resistance_flat

## Reduces incoming damage by this percent. Used when calling [method damage] and ignored when setting [member health] directly.
@export var resistance_percent := 0.0: set = set_resistance_percent

## Controls the order in which [member resistance_flat] and [member resistance_percent] are applied. See [enum ResistanceOrder].
@export var resistance_order := ResistanceOrder.PERCENT_FLAT
#endregion resistances

@export_group("Other")

## If this is [param false], [member is_dead] can't become [param true]. Useful for a constantly depleted [member shield].
@export var can_die := true: set = set_can_die

## If this is [param true], it emits [signal died], but only if it was [param false]. See [method kill] and [method revive].
var is_dead := false: set = set_is_dead

## Optional. If there's a shield, all [method damage] first goes through it. Useful for games with shields that guard your [member health]. See [method make_shield].
##[br][br][b]Note:[/b] The shield can have its own shield! ([param caution]: don't make circular dependencies)
@export var shield: Health: set = set_shield
#endregion variables


#region setters
func set_health(value: float) -> void:
	if health != value:
		health_changed.emit(value - health)
	health = clamp(value, 0.0, max_health)
	if health <= 0: kill()

func set_max_health(value: float) -> void:
	max_health = max(value, 0.0)
	set_health(health)

func set_is_dead(value: bool) -> void:
	if not can_die: is_dead = false; return
	if is_dead == false and value == true:
		died.emit()
	is_dead = value

func set_can_die(value: bool) -> void:
	can_die = value
	set_is_dead(is_dead)

func set_resistance_flat(value: float) -> void:
	resistance_flat = max(value, 0.0)

func set_resistance_percent(value: float) -> void:
	resistance_percent = clamp(value, 0.0, 100.0)

func set_shield(value: Health) -> void:
	shield = value
	if Engine.is_editor_hint(): update_configuration_warnings()
#endregion setters


#region methods
## Applies flat and percent resistances. If [member shield] is present, first damages that to absorb as much as it can. See [Health.DamageResult].
func damage(value: float) -> DamageResult:
	var shield_result := DamageResult.new()
	if shield and shield.health > 0.0 and not are_shields_cyclic():
		shield_result = shield.damage(value)
		value = shield_result.remaining_damage
	var damage_after_resistance := get_damage_after_resistance(value)
	var old_health := health
	health -= damage_after_resistance
	var taken_damage := old_health - health
	var damage_result := DamageResult.new()
	damage_result.shield_result = shield_result
	damage_result.taken_damage = taken_damage
	damage_result.remaining_damage = damage_after_resistance - taken_damage
	return damage_result

## Syntax sugar to add [param value] to [member health].
func heal(value: float) -> void:
	health += value

## Represents the fullness of [member health] in [member max_health] as a percent, or [method get_health_ratio] [param * 100].
func get_health_percent() -> float:
	return get_health_ratio() * 100.0

## Represents the fullness of [member health] in [member max_health] as a normalized value, or [param health / max_health].
func get_health_ratio() -> float:
	if max_health == 0: return 0.0
	return health / max_health

## Syntax sugar to set [member is_dead] to [param true]. If the parameter is [param true], [member health] will be set to [param 0].
func kill(should_health_be_zero := false) -> void:
	is_dead = true
	if should_health_be_zero: health = 0.0

## Syntax sugar to set [member is_dead] to [param false]. If the parameter is [param true], [member health] will be set to [member max_health].
func revive(should_health_be_max := false) -> void:
	is_dead = false
	if should_health_be_max: health = max_health

## Returns true if you managed to make cyclic [member shield] dependencies.
##[br][br][b]Note:[/b] No worries, the scene tree will show a warning.
func are_shields_cyclic() -> bool:
	var shields := [self]
	var current_shield := shield
	while current_shield:
		if shields.has(current_shield): return true
		shields.append(current_shield)
		current_shield = current_shield.shield
	return false

## Makes a new [member shield] as child of [Health]. Sets its [member can_die] to [param false] because shields are supposed to lose health and not die. The parameter sets [member max_health] and [member health].
func make_shield(new_shield_hp := max_health) -> Health:
	var new_shield := Health.new()
	shield = new_shield
	add_child(new_shield)
	new_shield.can_die = false
	new_shield.max_health = new_shield_hp
	new_shield.health = new_shield.max_health
	return new_shield

## Applies flat and percent resistances in the order of [member resistance_order] without applying the damage. Used by [method damage].
func get_damage_after_resistance(value: float) -> float:
	if resistance_order == ResistanceOrder.PERCENT_FLAT:
		return max((value * ((100.0 - resistance_percent) / 100.0)) - resistance_flat, 0.0)
	else:
		return max(value - resistance_flat, 0.0) * ((100.0 - resistance_percent) / 100.0)
#endregion methods


#region internal
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray
	if are_shields_cyclic():
		warnings.append("Cyclic shield dependencies.")
	return warnings
#endregion internal
