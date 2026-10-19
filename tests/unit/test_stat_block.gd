extends GutTest
## Tests for StatBlock (SPEC-stats-status). Owned by stats-status.
## Covers the (base + sum flat) * (1 + sum percent) formula and its ordering,
## modifier handles, remove_source, per-stat clamps, MAX_HP ratio preservation
## across set_base, the snapshot of all 11 stats, and the stat_changed signal.

const EPSILON := 0.0001


func _block() -> StatBlock:
	var sb := StatBlock.new()
	sb.base = {
		StatBlock.Stat.MAX_HP: 100.0,
		StatBlock.Stat.ATTACK: 100.0,
		StatBlock.Stat.DEFENSE: 50.0,
		StatBlock.Stat.MOVE_SPEED: 120.0,
		StatBlock.Stat.ATTACK_SPEED: 1.0,
		StatBlock.Stat.DODGE_COOLDOWN: 0.8,
		StatBlock.Stat.CRIT_CHANCE: 0.05,
		StatBlock.Stat.CRIT_DAMAGE: 0.0,
		StatBlock.Stat.ABILITY_POWER: 100.0,
		StatBlock.Stat.COOLDOWN_REDUCTION: 0.0,
		StatBlock.Stat.LUCK: 0.0,
	}
	add_child_autofree(sb)
	return sb


func test_enum_has_eleven_stats() -> void:
	assert_eq(StatBlock.Stat.values().size(), 11)
	assert_eq(StatBlock.STAT_COUNT, 11)


func test_base_only_value_is_the_base() -> void:
	assert_almost_eq(_block().get_value(StatBlock.Stat.MAX_HP), 100.0, EPSILON)


func test_percent_applies_after_flat_sum() -> void:
	var sb := _block()
	sb.add_modifier(StatBlock.Stat.ATTACK, 10.0, 0.2, &"test")
	assert_almost_eq(sb.get_value(StatBlock.Stat.ATTACK), 132.0, EPSILON,
		"(100 + 10) * 1.2 = 132, not 100 * 1.2 + 10 = 130")


func test_flats_sum_then_percents_sum() -> void:
	var sb := _block()
	sb.add_modifier(StatBlock.Stat.ATTACK, 10.0, 0.1, &"a")
	sb.add_modifier(StatBlock.Stat.ATTACK, 5.0, 0.2, &"b")
	assert_almost_eq(sb.get_value(StatBlock.Stat.ATTACK), 149.5, EPSILON,
		"(100 + 15) * 1.3")


func test_add_modifier_returns_a_unique_handle() -> void:
	var sb := _block()
	var h1 := sb.add_modifier(StatBlock.Stat.ATTACK, 1.0, 0.0, &"a")
	var h2 := sb.add_modifier(StatBlock.Stat.ATTACK, 1.0, 0.0, &"b")
	assert_ne(h1, h2)


func test_remove_modifier_restores_the_value() -> void:
	var sb := _block()
	var h1 := sb.add_modifier(StatBlock.Stat.ATTACK, 10.0, 0.0, &"a")
	sb.add_modifier(StatBlock.Stat.ATTACK, 5.0, 0.0, &"b")
	assert_almost_eq(sb.get_value(StatBlock.Stat.ATTACK), 115.0, EPSILON)
	sb.remove_modifier(h1)
	assert_almost_eq(sb.get_value(StatBlock.Stat.ATTACK), 105.0, EPSILON,
		"only the removed handle's flat is gone")


func test_remove_modifier_ignores_unknown_handles() -> void:
	var sb := _block()
	sb.remove_modifier(9999)
	assert_almost_eq(sb.get_value(StatBlock.Stat.ATTACK), 100.0, EPSILON)


func test_remove_source_removes_every_modifier_from_that_source() -> void:
	var sb := _block()
	sb.add_modifier(StatBlock.Stat.ATTACK, 10.0, 0.0, &"relic")
	sb.add_modifier(StatBlock.Stat.ATTACK, 20.0, 0.0, &"relic")
	sb.add_modifier(StatBlock.Stat.DEFENSE, 5.0, 0.0, &"other")
	sb.remove_source(&"relic")
	assert_almost_eq(sb.get_value(StatBlock.Stat.ATTACK), 100.0, EPSILON)
	assert_almost_eq(sb.get_value(StatBlock.Stat.DEFENSE), 55.0, EPSILON,
		"unrelated source survives")


func test_crit_chance_clamps_to_unit_interval() -> void:
	var sb := _block()  # base CRIT_CHANCE 0.05
	sb.add_modifier(StatBlock.Stat.CRIT_CHANCE, 2.0, 0.0, &"test")
	assert_almost_eq(sb.get_value(StatBlock.Stat.CRIT_CHANCE), 1.0, EPSILON)
	sb.add_modifier(StatBlock.Stat.CRIT_CHANCE, -10.0, 0.0, &"test2")
	assert_almost_eq(sb.get_value(StatBlock.Stat.CRIT_CHANCE), 0.0, EPSILON)


func test_cooldown_reduction_caps_at_60_percent() -> void:
	var sb := _block()
	sb.add_modifier(StatBlock.Stat.COOLDOWN_REDUCTION, 1.0, 0.0, &"test")
	assert_almost_eq(sb.get_value(StatBlock.Stat.COOLDOWN_REDUCTION), 0.6, EPSILON)


func test_attack_speed_never_below_20_percent() -> void:
	var sb := _block()
	sb.add_modifier(StatBlock.Stat.ATTACK_SPEED, -1.0, 0.0, &"test")
	assert_almost_eq(sb.get_value(StatBlock.Stat.ATTACK_SPEED), 0.2, EPSILON)


func test_unclamped_stats_pass_through() -> void:
	var sb := _block()
	sb.add_modifier(StatBlock.Stat.MOVE_SPEED, 40.0, 0.0, &"test")
	assert_almost_eq(sb.get_value(StatBlock.Stat.MOVE_SPEED), 160.0, EPSILON)


func test_max_hp_ratio_is_preserved_on_base_change() -> void:
	var sb := _block()
	sb.current_hp_ratio = 0.5
	sb.set_base(StatBlock.Stat.MAX_HP, 200.0)
	assert_almost_eq(sb.get_value(StatBlock.Stat.MAX_HP), 200.0, EPSILON)
	assert_almost_eq(sb.current_hp_ratio, 0.5, EPSILON,
		"the fill fraction survives a base change")


func test_set_base_writes_the_base_dictionary() -> void:
	var sb := _block()
	sb.set_base(StatBlock.Stat.LUCK, 7.0)
	assert_almost_eq(sb.get_value(StatBlock.Stat.LUCK), 7.0, EPSILON)
	assert_almost_eq(sb.base[StatBlock.Stat.LUCK], 7.0, EPSILON)


func test_snapshot_covers_all_eleven_stats_with_derived_values() -> void:
	var sb := _block()
	sb.add_modifier(StatBlock.Stat.ATTACK, 50.0, 0.0, &"test")
	var snap := sb.snapshot()
	assert_eq(snap.size(), 11)
	for stat: int in StatBlock.Stat.values():
		assert_almost_eq(snap[stat], sb.get_value(stat), EPSILON)


func test_stat_changed_emits_the_new_value() -> void:
	var sb := _block()
	watch_signals(sb)
	sb.add_modifier(StatBlock.Stat.ATTACK, 50.0, 0.0, &"test")
	assert_signal_emitted_with_parameters(sb, "stat_changed", [StatBlock.Stat.ATTACK, 150.0])
