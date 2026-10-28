extends GutTest
## Tests for scripts/player/dodge_clock.gd — the pure dodge numbers and the
## cooldown/charge bookkeeping (W2-A8 logic half; the hurtbox i-frame wiring is
## tested through the scene). Owned by player-controller.

var _clock: DodgeClock


func before_each() -> void:
	_clock = DodgeClock.new()


## Spec values (SPEC-player-controller "Dodge roll")

func test_iframes_cover_the_full_roll() -> void:
	assert_eq(DodgeClock.IFRAME_SECONDS, DodgeClock.DURATION_SECONDS,
		"SPEC: 'I-frames for the full roll'")


func test_the_roll_duration_is_the_tuned_spec_value() -> void:
	assert_eq(DodgeClock.DURATION_SECONDS, 0.28, "SPEC '~0.25 s'")


func test_the_roll_speed_is_a_multiple_of_move_speed() -> void:
	assert_eq(DodgeClock.SPEED_MULT, 2.6)


## Cooldown from the DODGE_COOLDOWN stat


func test_the_cooldown_is_the_stat_value() -> void:
	assert_eq(_clock.cooldown_seconds(0.8), 0.8, "base DODGE_COOLDOWN 0.8 s")


func test_the_cooldown_never_drops_below_the_floor() -> void:
	assert_eq(_clock.cooldown_seconds(0.0), DodgeClock.MIN_COOLDOWN_SECONDS)
	assert_eq(_clock.cooldown_seconds(0.05), DodgeClock.MIN_COOLDOWN_SECONDS)


func test_the_cooldown_rides_a_stat_modifier_and_its_handle() -> void:
	var stats := StatBlock.new()
	add_child_autofree(stats)
	stats.set_base(StatBlock.Stat.DODGE_COOLDOWN, 0.8)
	assert_eq(_clock.cooldown_seconds(stats.get_value(StatBlock.Stat.DODGE_COOLDOWN)), 0.8)
	var handle := stats.add_modifier(StatBlock.Stat.DODGE_COOLDOWN, -0.3, 0.0, &"test_dodge")
	assert_eq(_clock.cooldown_seconds(stats.get_value(StatBlock.Stat.DODGE_COOLDOWN)), 0.5,
		"the modifier shortens the recharge")
	stats.remove_modifier(handle)
	assert_eq(_clock.cooldown_seconds(stats.get_value(StatBlock.Stat.DODGE_COOLDOWN)), 0.8,
		"removed by handle, the base is back")
	assert_eq(float(stats.base[StatBlock.Stat.DODGE_COOLDOWN]), 0.8, "the base was never edited")


## Charges


func test_a_fresh_clock_has_the_default_charge() -> void:
	assert_eq(_clock.charges, DodgeClock.DEFAULT_MAX_CHARGES)
	assert_eq(_clock.max_charges, DodgeClock.DEFAULT_MAX_CHARGES)
	assert_true(_clock.can_dodge())


func test_spending_the_charge_starts_the_recharge() -> void:
	assert_true(_clock.spend(0.8))
	assert_eq(_clock.charges, 0)
	assert_false(_clock.can_dodge(), "the cooldown runs")


func test_the_charge_refills_when_the_cooldown_elapses() -> void:
	_clock.spend(0.8)
	_clock.tick(0.4)
	_clock.tick(0.39)
	assert_eq(_clock.charges, 0, "the recharge is still running")
	_clock.tick(0.02)
	assert_eq(_clock.charges, 1, "the recharge finished")
	assert_true(_clock.can_dodge())


func test_the_recharge_never_goes_past_max() -> void:
	_clock.tick(10.0)
	assert_eq(_clock.charges, 1)


func test_a_second_charge_dodges_while_the_first_recharges() -> void:
	_clock.max_charges = 2
	_clock.charges = 2
	assert_true(_clock.spend(0.8))
	assert_true(_clock.can_dodge(), "the second charge does not wait for the cooldown")
	assert_true(_clock.spend(0.8))
	assert_false(_clock.can_dodge(), "both spent")


func test_two_spent_charges_recharge_one_per_cooldown() -> void:
	_clock.max_charges = 2
	_clock.charges = 2
	_clock.spend(0.8)
	_clock.spend(0.8)
	_clock.tick(0.8)
	assert_eq(_clock.charges, 1, "one per cooldown period")
	_clock.tick(0.8)
	assert_eq(_clock.charges, 2, "then the other")
	_clock.tick(0.8)
	assert_eq(_clock.charges, 2, "capped at max")


func test_a_refused_spend_leaves_the_running_recharge_alone() -> void:
	_clock.spend(0.8)
	assert_false(_clock.spend(0.8), "no charge to spend")
	_clock.tick(0.8)
	assert_eq(_clock.charges, 1, "the first spend's recharge finished on time")


func test_raising_max_refills_the_missing_charge_on_the_next_tick() -> void:
	_clock.max_charges = 2
	_clock.tick(0.016)
	assert_eq(_clock.charges, 2, "a synergy's second charge is ready at once")


## reset_dodge_cooldown()


func test_reset_dodge_cooldown_clears_the_cooldown_and_refills() -> void:
	_clock.spend(0.8)
	_clock.reset_dodge_cooldown()
	assert_eq(_clock.charges, 1, "the running recharge finished now")
	assert_true(_clock.can_dodge())


func test_reset_with_two_missing_charges_refills_one_and_restarts() -> void:
	_clock.max_charges = 2
	_clock.charges = 2
	_clock.spend(0.8)
	_clock.spend(0.8)
	_clock.reset_dodge_cooldown()
	assert_eq(_clock.charges, 1, "one back now")
	_clock.tick(0.8)
	assert_eq(_clock.charges, 2, "the other keeps its normal recharge")


func test_reset_on_a_fresh_clock_changes_nothing() -> void:
	_clock.reset_dodge_cooldown()
	assert_eq(_clock.charges, 1)
	assert_true(_clock.can_dodge())


func test_reset_restores_a_fresh_run_state() -> void:
	_clock.spend(0.8)
	_clock.reset()
	assert_eq(_clock.charges, 1)
	_clock.spend(0.8)
	assert_false(_clock.can_dodge())
	_clock.tick(0.8)
	assert_eq(_clock.charges, 1, "the fresh clock recharges at the normal cost")
