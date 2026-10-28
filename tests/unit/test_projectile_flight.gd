extends GutTest
## The pure flight math behind the `Projectile` base (W2-A6): bounce count and
## angle, homing turn rate, lifetime and range budgets, the reflect flag, and
## time-scaled stepping. Owned by combat-core. The math is tested on a bare
## `ProjectileFlight`; the node cases prove `launch` reads its bounce count
## from the `ProjectileSpec` — bounce, homing turn rate, lifetime and the
## reflect flag all of them — that the relic seam `add_bounce` lands on the
## real node, that a reflect flips the team and moves the projectile between
## time groups with it, that a hostile projectile joins the enemy time group,
## and that the node's wall path bounces without spending range. Named-method
## callbacks only; no scene, no pool.

const EPSILON: float = 0.0001
const STOP_SOURCE: StringName = &"test_projectile_flight"


func after_each() -> void:
	TimeManager.clear_source(STOP_SOURCE)


# --- bounce: count and angle ------------------------------------------------------------


func test_a_bounce_reflects_the_velocity_off_the_wall_normal() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, -100), 1000.0)
	flight.bounces_left = 2
	assert_true(flight.bounce_off(Vector2(-1, 0)), "a bounce is left, so the wall ricochets")
	assert_eq(flight.velocity, Vector2(-100, -100), "mirrored across the wall")
	assert_eq(flight.bounces_left, 1, "and one bounce is spent")


func test_the_last_bounce_stops_the_projectile_at_the_wall() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, -100), 1000.0)
	flight.bounces_left = 1
	assert_true(flight.bounce_off(Vector2(-1, 0)), "the last bounce lands")
	assert_false(flight.bounce_off(Vector2(-1, 0)), "no bounce left")
	assert_eq(flight.velocity, Vector2(-100, -100), "the refused wall changes nothing")


func test_a_projectile_without_bounces_dies_on_its_first_wall() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 1000.0)
	assert_false(flight.bounce_off(Vector2(-1, 0)), "the old straight-flight behaviour")
	assert_eq(flight.velocity, Vector2(100, 0), "velocity untouched by the refusal")


# --- homing: turn rate ------------------------------------------------------------------


func test_the_turn_rate_is_radians_per_second_and_never_overshoots() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 10000.0)
	flight.homing_strength = PI / 2.0
	# A full second of budget exactly matches the quarter circle to the target.
	var turned: float = flight.turn_toward(Vector2(0, 100), Vector2.ZERO, 1.0)
	assert_almost_eq(turned, PI / 2.0, EPSILON, "the angle the budget allows")
	assert_almost_eq(flight.velocity.x, 0.0, EPSILON)
	assert_almost_eq(flight.velocity.y, 100.0, EPSILON, "pointing straight at the target")


func test_one_frame_turns_by_the_rate_times_the_frame() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 10000.0)
	flight.homing_strength = PI / 2.0
	var turned: float = flight.turn_toward(Vector2(0, 100), Vector2.ZERO, 0.1)
	assert_almost_eq(turned, PI / 20.0, EPSILON, "a tenth of a second turns a tenth of the arc")
	assert_almost_eq(flight.velocity.angle(), PI / 20.0, EPSILON)


func test_a_small_remaining_angle_is_taken_whole() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 10000.0)
	flight.homing_strength = PI / 2.0
	var turned: float = flight.turn_toward(Vector2(100, 5), Vector2.ZERO, 1.0)
	assert_almost_eq(turned, atan2(5.0, 100.0), EPSILON, "the target direction, not the whole budget")
	assert_almost_eq(flight.velocity.angle(), atan2(5.0, 100.0), EPSILON, "no overshoot past the target")


func test_a_projectile_without_homing_strength_flies_straight() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 10000.0)
	assert_eq(flight.turn_toward(Vector2(0, 100), Vector2.ZERO, 1.0), 0.0)
	assert_eq(flight.velocity, Vector2(100, 0))


func test_time_scale_scales_the_homing_turn() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 10000.0)
	flight.homing_strength = PI / 2.0
	var turned: float = flight.turn_toward(Vector2(0, 100), Vector2.ZERO, 0.2, 0.5)
	assert_almost_eq(turned, PI / 20.0, EPSILON, "half speed, half the turn")


# --- lifetime and range -----------------------------------------------------------------


func test_a_configured_lifetime_expires_the_projectile() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 10000.0, 1.0)
	flight.advance(0.6)
	assert_false(flight.is_expired(), "still alive at 0.6 s of 1 s")
	flight.advance(0.4)
	assert_true(flight.is_expired(), "the second burns out")


func test_the_lifetime_burns_at_the_time_scale() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 10000.0, 1.0)
	flight.advance(0.5, 0.5)
	assert_false(flight.is_expired(), "half speed burns a quarter second")
	flight.advance(0.5, 0.5)
	assert_false(flight.is_expired(), "half a second burned of one")
	flight.advance(1.0)
	assert_true(flight.is_expired(), "past the budget now")


func test_an_unconfigured_lifetime_never_expires_by_time() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 200000.0)
	for step in 1000:
		flight.advance(1.0)
		if flight.is_expired():
			fail_test("a projectile with no lifetime must not expire by time")
			return
	pass_test("a thousand seconds in and still flying")


func test_the_range_budget_expires_the_projectile() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 50.0)
	var step: Vector2 = flight.advance(1.0)
	assert_eq(step, Vector2(100, 0), "the frame still moves the step it took")
	assert_true(flight.is_expired(), "and the range is spent")


# --- time-scaled movement ---------------------------------------------------------------


func test_the_step_is_velocity_times_delta_times_scale() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 1000.0)
	assert_eq(flight.advance(0.1, 1.0), Vector2(10, 0))
	assert_eq(flight.advance(0.1, 0.5), Vector2(5, 0))


func test_a_frozen_projectile_neither_moves_nor_expires() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 100.0, 0.05)
	for step in 10:
		assert_eq(flight.advance(1.0, 0.0), Vector2.ZERO, "scale 0, no step")
		assert_false(flight.is_expired(), "and nothing burns while frozen")
	assert_eq(flight.distance_left, 100.0, "the range budget is untouched")


func test_step_for_prices_the_frame_and_commit_burns_it() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 1000.0)
	assert_eq(flight.step_for(0.1, 0.5), Vector2(5, 0), "the step is priced before anything burns")
	assert_eq(flight.distance_left, 1000.0, "and pricing alone spends nothing")
	flight.commit(Vector2(5, 0), 0.1, 0.5)
	assert_eq(flight.distance_left, 995.0, "the commit burns the range by the step it is given")


# --- a bounce frame costs time, not range ------------------------------------------------


func test_a_bounce_frame_burns_lifetime_but_not_range() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, -100), 500.0, 0.3)
	flight.bounces_left = 1
	assert_true(flight.hit_wall(Vector2(-1, 0), 0.1), "the bounce lands")
	assert_eq(flight.velocity, Vector2(-100, -100), "mirrored off the wall")
	assert_eq(flight.distance_left, 500.0, "the range is untouched: nothing moved")
	flight.advance(0.2)
	assert_true(flight.is_expired(), "and the frame's time still passed: 0.1 + 0.2 burns the 0.3 s budget")


func test_a_wall_without_bounces_refuses_and_costs_nothing() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 500.0, 0.3)
	assert_false(flight.hit_wall(Vector2(-1, 0), 0.1), "no bounce left: the caller must stop it")
	assert_eq(flight.velocity, Vector2(100, 0), "velocity untouched by the refusal")
	assert_eq(flight.distance_left, 500.0, "range untouched")
	flight.advance(0.2)
	assert_false(flight.is_expired(), "the refusal burned no lifetime either: 0.2 of the 0.3 s is still left")


# --- reflect flag -----------------------------------------------------------------------


func test_a_projectile_without_the_flag_cannot_be_reflected() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 1000.0)
	assert_false(flight.reflect(), "not reflectable")
	assert_eq(flight.velocity, Vector2(100, 0), "and nothing moved")


func test_a_reflectable_projectile_flies_back_the_way_it_came() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, 0), 1000.0)
	flight.reflectable = true
	assert_true(flight.reflect())
	assert_eq(flight.velocity, Vector2(-100, 0))


func test_a_reflect_off_a_surface_mirrors_like_a_bounce() -> void:
	var flight: ProjectileFlight = _flight(Vector2(100, -100), 1000.0)
	flight.reflectable = true
	assert_true(flight.reflect(Vector2(-1, 0)))
	assert_eq(flight.velocity, Vector2(-100, -100))


# --- the projectile base reads the flight ------------------------------------------------


func test_launch_reads_the_bounce_count_from_the_spec() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	var spec: ProjectileSpec = ProjectileSpec.new(null, 240.0, 12.5, HitInfo.Element.NONE, 2, 3)
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 2, spec)
	assert_eq(projectile.bounces_left(), 3, "bounce comes from ProjectileSpec")
	assert_eq(projectile.flight_velocity(), Vector2(240, 0), "the spawn velocity is the flight velocity")
	assert_true(projectile.active, "and the hitbox is armed")


func test_launch_without_a_spec_keeps_the_straight_no_bounce_flight() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 2)
	assert_eq(projectile.bounces_left(), 0, "no spec, no ricochet")
	assert_eq(projectile.flight_velocity(), Vector2(240, 0))


func test_launch_reads_every_flight_number_from_the_spec() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	var spec: ProjectileSpec = ProjectileSpec.new(
		null, 240.0, 12.5, HitInfo.Element.NONE, 2, 3, 1.5, 2.5, true
	)
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 2, spec)
	assert_eq(projectile.homing_strength, 1.5, "the homing turn rate comes from ProjectileSpec")
	assert_eq(projectile.lifetime_seconds, 2.5, "the lifetime comes from ProjectileSpec")
	assert_true(projectile.reflectable, "the reflect flag comes from ProjectileSpec")
	assert_eq(projectile.bounces_left(), 3, "as does the bounce count")


func test_launch_without_a_spec_flies_on_the_node_vars() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	projectile.homing_strength = 1.5
	projectile.lifetime_seconds = 2.5
	projectile.reflectable = true
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	assert_eq(projectile.homing_strength, 1.5, "no spec: the homing turn rate stands")
	assert_eq(projectile.lifetime_seconds, 2.5, "so does the lifetime")
	assert_true(projectile.reflectable, "and the reflect flag")


func test_the_relic_seam_adds_bounces_to_the_real_projectile() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	projectile.add_bounce(2)
	assert_eq(projectile.bounces_left(), 2, "Rune of Ricochet's ask lands name for name")


func test_reflect_projectile_bats_it_back_at_the_other_team() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	projectile.reflectable = true
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	assert_true(projectile.reflect_projectile())
	assert_eq(projectile.flight_velocity(), Vector2(-240, 0), "flying back the way it came")
	assert_eq(projectile.team, Team.Kind.ENEMY, "and it fights for the other side now")
	assert_true(projectile.hostile)


func test_reflect_projectile_is_a_noop_without_the_flag() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	assert_false(projectile.reflect_projectile())
	assert_eq(projectile.team, Team.Kind.PLAYER)


func test_a_hostile_projectile_respects_the_enemy_time_stack() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	projectile.launch(HitInfo.new(), Team.Kind.ENEMY, 600.0, 0)
	TimeManager.stop_enemies(1.0, STOP_SOURCE)
	assert_eq(TimeManager.scale_for(projectile), 0.0, "a stopped enemy stack freezes enemy projectiles")
	TimeManager.clear_source(STOP_SOURCE)
	assert_eq(TimeManager.scale_for(projectile), 1.0, "and releases them")


func test_a_reflected_enemy_projectile_leaves_the_enemy_time_group() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	projectile.reflectable = true
	projectile.launch(HitInfo.new(), Team.Kind.ENEMY, 600.0, 0)
	TimeManager.stop_enemies(1.0, STOP_SOURCE)
	assert_eq(TimeManager.scale_for(projectile), 0.0, "frozen while it flies for the enemy")
	assert_true(projectile.reflect_projectile(), "a Guardian block bats it back")
	assert_eq(TimeManager.scale_for(projectile), 1.0, "the reflect moves it out of the enemy stack")
	assert_false(projectile.hostile)


func test_a_reflected_player_projectile_joins_the_enemy_time_group() -> void:
	var projectile: Projectile = autofree(Projectile.new())
	projectile.synced_velocity = Vector2(240, 0)
	projectile.reflectable = true
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	TimeManager.stop_enemies(1.0, STOP_SOURCE)
	assert_eq(TimeManager.scale_for(projectile), 1.0, "a player bolt ignores the enemy stack")
	assert_true(projectile.reflect_projectile(), "an enemy reflect source turns it")
	assert_true(projectile.hostile)
	assert_eq(TimeManager.scale_for(projectile), 0.0, "and now it flies on the enemy clock")


# --- the node-level wall path ------------------------------------------------------------


func test_the_node_bounces_off_a_wall_without_spending_range() -> void:
	var projectile: WalledProjectile = autofree(WalledProjectile.new())
	projectile.synced_velocity = Vector2(100, -100)
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 400.0, 0)
	projectile.add_bounce(1)
	projectile.wall = {"normal": Vector2(-1, 0)}
	projectile._host_step(0.1)
	assert_eq(projectile.flight_velocity(), Vector2(-100, -100), "the wall mirrors the flight")
	assert_false(projectile.is_queued_for_deletion(), "a bounce was left, so it flies on")
	assert_almost_eq(projectile.range_left(), 400.0, EPSILON, "the bounce frame spent no range")
	assert_eq(projectile.position, Vector2.ZERO, "and it did not move through the wall")


func test_the_node_bounce_frame_still_burns_lifetime() -> void:
	var projectile: WalledProjectile = autofree(WalledProjectile.new())
	projectile.synced_velocity = Vector2(100, -100)
	projectile.lifetime_seconds = 0.3
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 400.0, 0)
	projectile.add_bounce(1)
	projectile.wall = {"normal": Vector2(-1, 0)}
	projectile._host_step(0.1)
	assert_false(projectile.is_queued_for_deletion(), "still flying after the bounce frame")
	projectile.wall = {}
	projectile._host_step(0.2)
	assert_true(projectile.is_queued_for_deletion(), "0.1 + 0.2 burns the 0.3 s budget: time passed on the bounce frame")


func test_the_node_dies_at_a_wall_it_cannot_bounce_off() -> void:
	var projectile: WalledProjectile = autofree(WalledProjectile.new())
	projectile.synced_velocity = Vector2(100, 0)
	projectile.launch(HitInfo.new(), Team.Kind.PLAYER, 400.0, 0)
	projectile.wall = {"normal": Vector2(-1, 0)}
	projectile._host_step(0.1)
	assert_true(projectile.is_queued_for_deletion(), "no bounce left at the wall: the projectile stops")


## A `Projectile` whose wall ray always reports `wall`: the node-level wall
## path (`_host_step`'s raycast, bounce and death) without a physics world.
class WalledProjectile extends Projectile:
	var wall: Dictionary = {}

	func _wall_normal_ahead(_step: Vector2) -> Dictionary:
		return wall


func _flight(velocity: Vector2, range_px: float, lifetime: float = ProjectileFlight.NO_LIFETIME) -> ProjectileFlight:
	var flight: ProjectileFlight = ProjectileFlight.new()
	flight.arm(velocity, range_px, lifetime)
	return flight
