extends GutTest
## Tests for the TimeManager autoload (SPEC-time-manager). Owned by time-manager.
## Covers the scale stack math (min-of-stack, expiry, clear_source), group
## exemptions (players unaffected by enemy slow/stop), per-entity override
## beating the group stack, hit-stop frame semantics, the scaled timer, and the
## host->client broadcast RPCs (unit-level: presence + solo local application).

const TPS: int = 60

## Every source used anywhere in this file, so before/after_each always leave
## the global stack empty (autoload state is shared across the whole GUT run).
const SOURCES: Array[StringName] = [&"test-slow", &"test-slow2", &"test-slow3", &"test-stop", &"test-entity", &"hit_stop"]


func before_each() -> void:
	_clear_all_sources()


func after_each() -> void:
	NetworkManager.disconnect_all()
	_clear_all_sources()


func _clear_all_sources() -> void:
	for source: StringName in SOURCES:
		TimeManager.clear_source(source)


func _mover(group: int = TimeManager.Group.ENEMY) -> ScaledMover:
	var mover := ScaledMover.new()
	mover.group = group
	add_child_autofree(mover)
	return mover


func test_unregistered_node_runs_at_normal_speed() -> void:
	var node := Node2D.new()
	add_child_autofree(node)
	assert_eq(TimeManager.scale_for(node), 1.0)
	TimeManager.stop_enemies(10.0, &"test-stop")
	assert_eq(TimeManager.scale_for(node), 1.0, "unregistered nodes are not in the enemy time group")


func test_players_are_unaffected_by_enemy_slow_and_stop() -> void:
	var player := _mover(TimeManager.Group.PLAYER)
	await wait_physics_frames(1)
	TimeManager.slow_enemies(0.25, 10.0, &"test-slow")
	assert_eq(TimeManager.scale_for(player), 1.0, "player ignores the global slow")
	TimeManager.stop_enemies(10.0, &"test-stop")
	assert_eq(TimeManager.scale_for(player), 1.0, "player ignores the global stop")


func test_global_slow_uses_min_of_the_stack() -> void:
	var enemy := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	TimeManager.slow_enemies(0.5, 10.0, &"test-slow")
	assert_eq(TimeManager.scale_for(enemy), 0.5)
	TimeManager.slow_enemies(0.8, 10.0, &"test-slow2")
	assert_eq(TimeManager.scale_for(enemy), 0.5, "the weaker slow stays in charge")
	TimeManager.slow_enemies(0.2, 10.0, &"test-slow3")
	assert_eq(TimeManager.scale_for(enemy), 0.2, "a stronger slow takes over")


func test_stop_is_a_factor_of_zero() -> void:
	var enemy := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	TimeManager.stop_enemies(10.0, &"test-stop")
	assert_eq(TimeManager.scale_for(enemy), 0.0)


func test_effect_expires_after_its_duration() -> void:
	var enemy := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	TimeManager.slow_enemies(0.5, 0.25, &"test-slow")  # 15 frames at 60 tps
	assert_eq(TimeManager.scale_for(enemy), 0.5)
	await wait_physics_frames(15)
	assert_eq(TimeManager.scale_for(enemy), 1.0, "expired after ~0.25 s")


func test_clear_source_removes_only_that_source() -> void:
	var enemy := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	TimeManager.slow_enemies(0.5, 10.0, &"test-slow")
	TimeManager.slow_enemies(0.7, 10.0, &"test-slow2")
	assert_eq(TimeManager.scale_for(enemy), 0.5)
	TimeManager.clear_source(&"test-slow")
	assert_eq(TimeManager.scale_for(enemy), 0.7, "the other source survives")
	TimeManager.clear_source(&"test-slow2")
	assert_eq(TimeManager.scale_for(enemy), 1.0, "cleared the whole stack")


func test_per_entity_override_beats_the_group_stack() -> void:
	var enemy := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	TimeManager.slow_enemies(0.5, 10.0, &"test-slow")
	TimeManager.set_entity_scale(enemy, 0.25, 10.0, &"test-entity")
	assert_eq(TimeManager.scale_for(enemy), 0.25, "per-entity factor wins over the group stack")
	TimeManager.clear_source(&"test-entity")
	assert_eq(TimeManager.scale_for(enemy), 0.5, "back to the group stack")


func test_per_entity_override_applies_to_players() -> void:
	# hit_stop is a per-entity effect on exactly attacker and target; the
	# PLAYER exemption must not leak into per-entity overrides.
	var player := _mover(TimeManager.Group.PLAYER)
	await wait_physics_frames(1)
	TimeManager.set_entity_scale(player, 0.0, 0.2, &"test-entity")
	assert_eq(TimeManager.scale_for(player), 0.0, "entity override wins over the PLAYER exemption")
	await wait_physics_frames(13)
	assert_eq(TimeManager.scale_for(player), 1.0, "restored after the duration")


func test_hit_stop_freezes_exactly_two_nodes_for_n_frames() -> void:
	var attacker := _mover(TimeManager.Group.PLAYER)
	var target := _mover(TimeManager.Group.ENEMY)
	var bystander := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	TimeManager.hit_stop(attacker, target, 6)
	assert_eq(TimeManager.scale_for(attacker), 0.0)
	assert_eq(TimeManager.scale_for(target), 0.0)
	assert_eq(TimeManager.scale_for(bystander), 1.0, "only the two hit-stopped nodes freeze")
	await wait_physics_frames(4)
	assert_eq(TimeManager.scale_for(attacker), 0.0, "still frozen before the 6th frame")
	await wait_physics_frames(3)
	assert_eq(TimeManager.scale_for(attacker), 1.0, "restored after 6 physics frames")


func test_enemy_time_changed_emits_on_global_scale_change() -> void:
	_mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	watch_signals(TimeManager)
	TimeManager.slow_enemies(0.5, 10.0, &"test-slow")
	assert_signal_emitted_with_parameters(TimeManager, "enemy_time_changed", [0.5])
	TimeManager.clear_source(&"test-slow")
	assert_signal_emitted_with_parameters(TimeManager, "enemy_time_changed", [1.0])


func test_timer_fires_after_scaled_time() -> void:
	var enemy := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	_fired = false
	TimeManager.timer(enemy, 0.5).connect(_mark_fired)
	await wait_physics_frames(35)
	assert_true(_fired, "0.5 s timer fired at full scale")


func test_timer_does_not_fire_while_the_enemy_is_stopped() -> void:
	var enemy := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	TimeManager.stop_enemies(0.4, &"test-stop")
	_fired = false
	TimeManager.timer(enemy, 0.2).connect(_mark_fired)
	await wait_physics_frames(15)
	assert_false(_fired, "0.2 s of stopped time is 0 scaled seconds")
	await wait_physics_frames(30)
	assert_true(_fired, "fires after the stop expires and scaled time resumes")


func test_broadcast_rpc_methods_exist() -> void:
	assert_true(TimeManager.has_method("time_effect_applied"), "host->client global broadcast")
	assert_true(TimeManager.has_method("entity_time_applied"), "host->client entity broadcast")


func test_solo_stop_applies_locally_and_broadcast_is_a_noop() -> void:
	var enemy := _mover(TimeManager.Group.ENEMY)
	await wait_physics_frames(1)
	NetworkManager.start_solo()
	TimeManager.stop_enemies(10.0, &"test-stop")
	assert_eq(TimeManager.scale_for(enemy), 0.0, "applied locally through the solo server path")


## Named callback so signal connections work inside GUT (lambdas connected to
## signals do not fire under the GUT runner).
var _fired := false


func _mark_fired() -> void:
	_fired = true
