extends GutTest
## Integration for time-manager (SPEC-time-manager): a scripted enemy that
## steps itself by TimeManager.scale_for(self) on each physics frame must
## travel 0 px during a stop and resume once it expires, and a slow must cut
## its distance in proportion. Owned by time-manager.

const TPS: int = 60


func before_each() -> void:
	_clear_all_sources()


func after_each() -> void:
	NetworkManager.disconnect_all()
	_clear_all_sources()


func _clear_all_sources() -> void:
	for source: StringName in [&"test-stop", &"test-slow"]:
		TimeManager.clear_source(source)


func test_enemy_travels_zero_during_a_stop_and_resumes() -> void:
	var enemy := ScaledMover.new()
	enemy.group = TimeManager.Group.ENEMY
	enemy.speed = 100.0
	add_child_autofree(enemy)
	enemy.global_position = Vector2.ZERO
	await wait_physics_frames(2)  # _ready registers the group
	TimeManager.stop_enemies(1.0, &"test-stop")
	enemy.walked = 0.0
	var origin := enemy.global_position.x
	await wait_physics_frames(int(0.5 * float(TPS)) + 2)  # halfway through the 1 s stop
	assert_eq(enemy.global_position.x, origin, "0 px moved during the stop")
	assert_eq(enemy.walked, 0.0, "no scaled time accumulated while stopped")
	await wait_physics_frames(int(0.6 * float(TPS)) + 5)  # well past the full stop
	assert_gt(enemy.global_position.x, origin + 10.0, "resumed moving at full speed")


func test_slow_cuts_distance_in_proportion_to_scale() -> void:
	var enemy := ScaledMover.new()
	enemy.group = TimeManager.Group.ENEMY
	enemy.speed = 100.0
	add_child_autofree(enemy)
	await wait_physics_frames(2)
	TimeManager.slow_enemies(0.5, 2.0, &"test-slow")
	var before := enemy.walked
	await wait_physics_frames(30)  # 0.5 s real time at scale 0.5 = 0.25 s walked
	var gained := enemy.walked - before
	# 0.25 s at 100 px/s = 25 px; full speed would be 50 px.
	assert_between(gained, 15.0, 35.0)
