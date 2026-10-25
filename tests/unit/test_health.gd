extends GutTest
## Tests for `Health` (SPEC-combat-core, "Components"): damage, about_to_die
## prevention, death, healing with the Toxin penalty and heal multipliers, and the
## overheal hook.

const MAX_HP: float = 100.0

var _entity: Node
var _stats: StatBlock
var _health: Health
var _statuses: StatusEffects


func before_each() -> void:
	_entity = Node.new()
	add_child_autofree(_entity)
	_stats = StatBlock.new()
	_stats.name = "StatBlock"
	_stats.base = {StatBlock.Stat.MAX_HP: MAX_HP}
	_entity.add_child(_stats)
	_statuses = StatusEffects.new()
	_statuses.name = "StatusEffects"
	_entity.add_child(_statuses)
	_health = Health.new()
	_health.name = "Health"
	_entity.add_child(_health)


func _hit(damage: int) -> HitInfo:
	var hit := HitInfo.new()
	hit.final_damage = damage
	return hit


func test_starts_at_max_hp() -> void:
	assert_eq(_health.current_hp, 100)
	assert_eq(_health.max_hp, 100)
	assert_almost_eq(_stats.current_hp_ratio, 1.0, 0.0001)


func test_damage_reduces_hp_and_syncs_ratio() -> void:
	watch_signals(_health)
	assert_true(_health.apply_damage(_hit(30)))
	assert_eq(_health.current_hp, 70)
	assert_almost_eq(_stats.current_hp_ratio, 0.7, 0.0001)
	assert_signal_emitted(_health, "damaged")
	assert_signal_not_emitted(_health, "died")


func test_null_hit_is_refused() -> void:
	assert_false(_health.apply_damage(null))
	assert_eq(_health.current_hp, 100)


func test_lethal_hit_emits_about_to_die_then_died() -> void:
	watch_signals(_health)
	_health.apply_damage(_hit(100))
	assert_true(_health.is_dead)
	assert_eq(_health.current_hp, 0)
	assert_signal_emitted(_health, "about_to_die")
	assert_signal_emitted(_health, "died")


func test_prevented_death_leaves_one_hp_and_no_died() -> void:
	_health.about_to_die.connect(func(hit: HitInfo) -> void: hit.prevented = true)
	watch_signals(_health)
	_health.apply_damage(_hit(500))
	assert_false(_health.is_dead)
	assert_eq(_health.current_hp, 1)
	assert_signal_not_emitted(_health, "died")
	assert_signal_emitted(_health, "damaged")


func test_prevention_handler_may_heal_instead() -> void:
	_health.about_to_die.connect(func(hit: HitInfo) -> void:
		hit.prevented = true
		_health.heal(40))
	_health.apply_damage(_hit(500))
	assert_eq(_health.current_hp, 40, "the handler's heal stands, no clamp to 1")
	assert_false(_health.is_dead)


func test_dead_entity_takes_no_further_damage_or_healing() -> void:
	_health.apply_damage(_hit(100))
	watch_signals(_health)
	assert_false(_health.apply_damage(_hit(10)))
	assert_eq(_health.heal(50), 0)
	assert_signal_not_emitted(_health, "died")
	assert_eq(_health.current_hp, 0)


func test_heal_caps_at_max_and_reports_granted() -> void:
	_health.apply_damage(_hit(30))
	assert_eq(_health.heal(50), 30)
	assert_eq(_health.current_hp, 100)


func test_toxin_halves_healing() -> void:
	_health.apply_damage(_hit(60))
	_statuses.apply_status(StatusEffects.Status.TOXIN)
	assert_eq(_health.heal(20), 10)
	assert_eq(_health.current_hp, 50)


func test_heal_multiplier_source_stacks_with_toxin_and_clears() -> void:
	_health.apply_damage(_hit(80))
	_health.set_heal_multiplier(&"coward_cloak", 0.5)
	assert_eq(_health.heal(20), 10)
	_health.set_heal_multiplier(&"coward_cloak", 1.0)
	assert_eq(_health.heal(20), 20)


func test_overheal_handler_gets_the_excess() -> void:
	var excess: Array[int] = []
	_health.overheal_handler = func(amount: int) -> void: excess.append(amount)
	_health.apply_damage(_hit(10))
	_health.heal(35)
	assert_eq(excess, [25] as Array[int])
	assert_eq(_health.current_hp, 100)


func test_heal_with_no_room_still_reports_overheal() -> void:
	var excess: Array[int] = []
	_health.overheal_handler = func(amount: int) -> void: excess.append(amount)
	assert_eq(_health.heal(15), 0)
	assert_eq(excess, [15] as Array[int])


func test_max_hp_modifier_keeps_the_fill_ratio() -> void:
	_health.apply_damage(_hit(50))
	_stats.add_modifier(StatBlock.Stat.MAX_HP, 100.0, 0.0, &"test")
	assert_eq(_health.max_hp, 200)
	assert_eq(_health.current_hp, 100)


func test_revive_restores_a_dead_entity() -> void:
	_health.apply_damage(_hit(100))
	_health.revive(40)
	assert_false(_health.is_dead)
	assert_eq(_health.current_hp, 40)


func test_player_heal_is_announced_on_the_bus() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(player)
	var stats: StatBlock = player.get_node("StatBlock")
	stats.set_base(StatBlock.Stat.MAX_HP, MAX_HP)
	var health: Health = player.get_node("Health")
	health.refill()
	watch_signals(Events)
	health.apply_damage(_hit(50))
	health.heal(20)
	assert_signal_emitted_with_parameters(Events, "player_healed", [player, 20, null])
	assert_eq(health.current_hp, 70)
