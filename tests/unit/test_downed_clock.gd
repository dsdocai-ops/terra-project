extends GutTest
## Tests for scripts/player/downed_clock.gd — the pure downed numbers and the
## bleed-out / revive-hold bookkeeping (W3-A5 logic half, G13a1; the Downed and
## Dead state wiring is G13a2, tested through the scene). Owned by
## player-controller.
##
## Spec values (SPEC-player-controller "Downed and revive"): a 30 s bleed-out
## timer; teammates hold interact for 3 s to revive to 40% HP; solo skips
## downed and goes to Dead immediately; revive speed multipliers scale the
## hold. The clock takes every number in, so no scene and no autoload state is
## driven here — NetworkManager and Player constants are read only to prove
## the copies cannot drift.

var _clock: DownedClock


func before_each() -> void:
	_clock = DownedClock.new()


## The bleed-out numbers


func test_the_bleed_out_window_is_30_seconds() -> void:
	assert_eq(DownedClock.BLEED_OUT_SECONDS, 30.0, "SPEC: 'a bleed-out timer of 30 s'")


func test_the_clock_and_the_scene_hold_the_same_bleed_out() -> void:
	assert_eq(DownedClock.BLEED_OUT_SECONDS, Player.BLEED_OUT_SECONDS,
		"the scene's inline timer and the clock cannot drift apart")


func test_a_down_starts_the_bleed_out_running() -> void:
	assert_false(_clock.bleeding(), "a standing player is not bleeding out")
	_clock.start_bleed_out()
	assert_true(_clock.bleeding())
	assert_eq(_clock.bleed_out_left, DownedClock.BLEED_OUT_SECONDS)


func test_the_bleed_out_does_not_run_unless_started() -> void:
	_clock.tick(100.0)
	assert_false(_clock.bleeding(), "a clock nobody started never expires")


func test_the_bleed_out_expires_after_exactly_30_seconds() -> void:
	_clock.start_bleed_out()
	_clock.tick(15.0)
	assert_true(_clock.bleeding(), "half the window is still down")
	_clock.tick(15.0)
	assert_false(_clock.bleeding(), "30 s of bleed-out is the end")
	assert_eq(_clock.bleed_out_left, 0.0)


func test_the_expired_bleed_out_stays_at_zero() -> void:
	_clock.start_bleed_out()
	_clock.tick(15.0)
	_clock.tick(15.0)
	_clock.tick(15.0)
	assert_eq(_clock.bleed_out_left, 0.0, "the clock never counts negative")


func test_a_revive_stops_the_bleed_out_before_it_expires() -> void:
	_clock.start_bleed_out()
	_clock.tick(10.0)
	_clock.stop_bleed_out()
	assert_false(_clock.bleeding(), "the teammate stood up in time")


## The solo skip (SPEC: "Solo: downed is skipped, Dead immediately")


func test_solo_skips_downed_and_goes_straight_to_dead() -> void:
	assert_true(DownedClock.goes_straight_to_dead(false),
		"no teammate standing: Dead at once, no bleed-out clock")


func test_a_standing_teammate_means_downed_not_dead() -> void:
	assert_false(DownedClock.goes_straight_to_dead(true),
		"a revivable teammate keeps the player in Downed")


## The revive hold


func test_the_revive_hold_is_3_seconds() -> void:
	assert_eq(DownedClock.REVIVE_HOLD_SECONDS, 3.0, "SPEC: 'hold interact within 48 px for 3 s'")


func test_the_clock_and_the_host_read_the_same_hold() -> void:
	assert_eq(DownedClock.REVIVE_HOLD_SECONDS, NetworkManager.REVIVE_SECONDS,
		"the clock and the host's revive path cannot drift apart")


func test_the_hold_does_not_run_unless_begun() -> void:
	_clock.tick(10.0)
	assert_false(_clock.holding())
	assert_eq(_clock.hold_progress(), 0.0)
	assert_false(_clock.hold_complete())


func test_the_hold_completes_at_exactly_3_seconds() -> void:
	_clock.begin_hold(1.0)
	assert_true(_clock.holding())
	_clock.tick(2.5)
	assert_false(_clock.hold_complete(), "half a second short")
	_clock.tick(0.5)
	assert_true(_clock.hold_complete(), "3 s of holding is the revive")
	assert_eq(_clock.hold_progress(), 1.0)


func test_the_hold_progress_is_a_fraction_of_the_running_hold() -> void:
	_clock.begin_hold(1.0)
	_clock.tick(0.75)
	assert_eq(_clock.hold_progress(), 0.25, "0.75 s of a 3 s hold")


## The hold scaled by revive_speed_mult


func test_the_hold_scales_with_the_revivers_speed_multiplier() -> void:
	assert_eq(_clock.hold_duration(2.0), 1.5, "Field Medic twice as fast is half the hold")


func test_a_scaled_hold_still_needs_the_full_scaled_time() -> void:
	_clock.begin_hold(2.0)
	_clock.tick(1.25)
	assert_false(_clock.hold_complete(), "1.25 s of a 1.5 s hold")
	_clock.tick(0.25)
	assert_true(_clock.hold_complete(), "the scaled hold finishes in its own time")


func test_a_zero_or_negative_multiplier_hits_the_floor() -> void:
	# 3 s / 0.1 is not binary-exact, so the floor reads with a tolerance.
	assert_almost_eq(_clock.hold_duration(0.0), 30.0, 0.0001, "3 s at the 0.1 floor")
	assert_almost_eq(_clock.hold_duration(-1.0), 30.0, 0.0001, "a negative mult behaves like the floor")


func test_the_mult_floor_mirrors_the_host_guard() -> void:
	assert_eq(DownedClock.MIN_SPEED_MULT, NetworkManager.REVIVE_SPEED_MULT_MIN,
		"the clock's division guard and the host's cannot drift apart")


func test_letting_go_banks_nothing() -> void:
	_clock.begin_hold(1.0)
	_clock.tick(1.0)
	assert_eq(_clock.hold_progress(), 1.0 / 3.0)
	_clock.break_hold()
	assert_false(_clock.holding(), "the hold is no longer running")
	assert_eq(_clock.hold_progress(), 0.0, "a hold is a continuous hold: nothing banked")
	_clock.begin_hold(1.0)
	assert_eq(_clock.hold_progress(), 0.0, "the next attempt starts from zero")


func test_a_new_hold_replaces_a_finished_one() -> void:
	_clock.begin_hold(1.0)
	_clock.tick(3.0)
	assert_true(_clock.hold_complete())
	_clock.begin_hold(2.0)
	assert_eq(_clock.hold_progress(), 0.0, "a second teammate's attempt starts fresh")
	assert_eq(_clock.hold_seconds, 1.5, "at the new reviver's own speed")


## Reaching 40%: the completed hold is the revive's precondition, and the
## restore reads the same fraction.


func test_the_revive_comes_back_at_40_percent() -> void:
	assert_eq(DownedClock.REVIVE_HP_FRACTION, 0.4, "SPEC: 'revive to 40% HP'")
	assert_eq(DownedClock.REVIVE_HP_FRACTION, NetworkManager.REVIVE_HP_FRACTION,
		"the clock and the host's restore cannot drift apart")
	assert_eq(NetworkManager.revive_hp_for(100), 40, "the completed hold stands the player up at 40")


func test_a_completed_hold_carries_a_stopped_bleed_out() -> void:
	# The revive the hold completes applies `stop_bleed_out()` — proven on the
	# clock as: a bleeding clock plus a completed hold holds everything the
	# standing-up path needs to clear.
	_clock.start_bleed_out()
	_clock.begin_hold(1.0)
	_clock.tick(3.0)
	assert_true(_clock.hold_complete())
	assert_true(_clock.bleeding())
	_clock.stop_bleed_out()
	assert_false(_clock.bleeding())


## Reset and time scale


func test_reset_restores_a_fresh_run_state() -> void:
	_clock.start_bleed_out()
	_clock.begin_hold(1.0)
	_clock.tick(5.0)
	_clock.reset()
	assert_eq(_clock.bleed_out_left, 0.0)
	assert_eq(_clock.hold_seconds, 0.0)
	assert_eq(_clock.hold_banked, 0.0)
	assert_false(_clock.bleeding())
	assert_false(_clock.holding())


func test_the_clock_never_touches_engine_time_scale() -> void:
	# The project rule: never Engine.time_scale. The clock takes the delta the
	# caller passes; a TimeManager slow is the caller's decision.
	var file := FileAccess.open("res://scripts/player/downed_clock.gd", FileAccess.READ)
	assert_not_null(file, "the clock source is readable")
	if file == null:
		return
	var source := file.get_as_text()
	assert_eq(source.find("Engine.time_scale"), -1, "no Engine.time_scale in the clock")
