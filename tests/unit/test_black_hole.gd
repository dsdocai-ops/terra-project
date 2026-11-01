extends GutTest
## Tests for Black Hole (SPEC-abilities section 8, Void; SINKHOLE_SPEC "pull every
## enemy to a point, then implode"): every enemy inside the radius is pulled toward
## the point through its own apply_knockback, an enemy outside is not, and the
## implode is one hit spawned when the last IMPLODE_LEAD seconds of the cast start,
## so it lands after the pull has ended. Owned by abilities. Sync: host only. The
## enemies are stand-ins in the enemies group that record their impulses; the cast
## is driven by hand.

const DATA_PATH: String = "res://data/abilities/black_hole.tres"
const CENTRE: Vector2 = Vector2.ZERO
const CLIENT_PORT: int = 7813

var _data: AbilityData


## A stand-in enemy: records every impulse the pull hands it.
class PullStub:
	extends Node2D
	var impulses: Array[Vector2] = []

	func apply_knockback(impulse: Vector2, _stun_seconds: float, _hit: HitInfo = null) -> void:
		impulses.append(impulse)


func before_each() -> void:
	_data = load(DATA_PATH) as AbilityData


func _cast() -> BlackHoleCast:
	var cast := _data.cast_scene.instantiate() as BlackHoleCast
	cast.setup(null, _data, 1, CENTRE, Vector2.RIGHT)
	add_child_autofree(cast)
	return cast


func _stub_at(at: Vector2) -> PullStub:
	var stub := PullStub.new()
	stub.position = at
	add_child_autofree(stub)
	stub.add_to_group(Enemy.GROUP)
	return stub


func _zones_of(cast: Node) -> Array[Zone]:
	var zones: Array[Zone] = []
	for child: Node in cast.get_children():
		var zone := child as Zone
		if zone != null:
			zones.append(zone)
	return zones


func test_an_enemy_inside_the_radius_is_pulled_toward_the_point() -> void:
	var cast := _cast()
	var near := _stub_at(Vector2(40, 0))
	cast.advance(0.016)
	assert_eq(near.impulses.size(), 1, "the enemy inside the radius is pulled once this step")
	if near.impulses.size() > 0:
		assert_true(near.impulses[0].x < 0.0, "the pull points at the centre, from the right")
		assert_almost_eq(near.impulses[0].y, 0.0, 0.001, "the pull has no sideways part on the axis")


func test_an_enemy_outside_the_radius_is_not_pulled() -> void:
	var cast := _cast()
	var far := _stub_at(Vector2(BlackHoleCast.RADIUS * 3.0, 0))
	cast.advance(0.016)
	assert_eq(far.impulses.size(), 0, "an enemy outside the radius is left alone")


func test_an_enemy_standing_on_the_centre_is_not_given_a_zero_direction() -> void:
	var cast := _cast()
	var centred := _stub_at(CENTRE)
	cast.advance(0.016)
	assert_eq(centred.impulses.size(), 0, "an enemy on the point has no direction to pull along")


func test_the_pull_has_a_finite_strength() -> void:
	var cast := _cast()
	var near := _stub_at(Vector2(40, 0))
	cast.advance(0.016)
	if near.impulses.size() > 0:
		assert_true(is_finite(near.impulses[0].x) and is_finite(near.impulses[0].y), "the pull impulse is finite")
		assert_almost_eq(near.impulses[0].length(), BlackHoleCast.PULL_SPEED, 0.001, "the pull runs at the set speed")


func test_the_implode_is_not_spawned_while_the_pull_runs() -> void:
	var cast := _cast()
	cast.advance(0.5)
	assert_eq(_zones_of(cast).size(), 0, "no implode during the pull")


func test_the_implode_is_one_hit_spawned_after_the_pull_ends() -> void:
	var cast := _cast()
	var near := _stub_at(Vector2(40, 0))
	cast.advance(0.016)
	cast.advance(_data.rank_data(1).duration - BlackHoleCast.IMPLODE_LEAD)
	var zones := _zones_of(cast)
	assert_eq(zones.size(), 1, "the implode spawns once the pull's time is spent")
	if zones.size() == 1:
		assert_eq(zones[0].ticks_done, 0, "the implode has not ticked when it spawns")
		zones[0].advance(BlackHoleCast.IMPLODE_LEAD)
		assert_gte(zones[0].ticks_done, 1, "the implode ticks on the step after the pull ends")
	assert_true(near.impulses.size() >= 1, "the pull ran before the implode")


func test_the_pull_stops_once_the_implode_is_spawned() -> void:
	var cast := _cast()
	var near := _stub_at(Vector2(40, 0))
	cast.advance(0.016)
	cast.advance(_data.rank_data(1).duration - BlackHoleCast.IMPLODE_LEAD)
	var pulled_before: int = near.impulses.size()
	cast.advance(0.01)
	assert_eq(near.impulses.size(), pulled_before, "no pull after the implode")


func test_the_implode_is_spawned_once_however_long_the_cast_runs() -> void:
	var cast := _cast()
	cast.advance(0.016)
	# Each full duration is more than the pull time left, so without the guard each
	# step after the implode would spawn another implode.
	cast.advance(_data.rank_data(1).duration)
	cast.advance(_data.rank_data(1).duration)
	cast.advance(_data.rank_data(1).duration)
	assert_eq(_zones_of(cast).size(), 1, "the implode is spawned once; later steps after the pull do not spawn another")


func test_every_enemy_inside_the_radius_is_pulled_and_one_outside_is_not() -> void:
	var cast := _cast()
	var first := _stub_at(Vector2(40, 0))
	var second := _stub_at(Vector2(0, -50))
	var outside := _stub_at(Vector2(300, 0))
	cast.advance(0.016)
	assert_eq(first.impulses.size(), 1, "the first enemy inside the radius is pulled")
	assert_eq(second.impulses.size(), 1, "the second enemy inside the radius is pulled")
	assert_eq(outside.impulses.size(), 0, "the enemy outside the radius is not")


func test_a_group_member_with_no_knockback_method_is_skipped() -> void:
	var plain := Node2D.new()
	plain.position = Vector2(40, 0)
	add_child_autofree(plain)
	plain.add_to_group(Enemy.GROUP)
	var stub := _stub_at(Vector2(0, 40))
	var cast := _cast()
	cast.advance(0.016)
	assert_eq(stub.impulses.size(), 1, "the pull still reaches the enemy after the plain node is skipped")


func test_the_implode_hits_an_enemy_inside_the_radius_on_the_tick_after_the_pull() -> void:
	var cast := _cast()
	cast.set_physics_process(false)
	var hurtbox := RecordingHurtbox.new()
	hurtbox.team = Team.Kind.ENEMY
	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape_node.shape = circle
	hurtbox.add_child(shape_node)
	hurtbox.position = CENTRE + Vector2(20, 0)
	add_child_autofree(hurtbox)
	await wait_physics_frames(2)
	cast.advance(0.016)
	cast.advance(_data.rank_data(1).duration - BlackHoleCast.IMPLODE_LEAD)
	await wait_physics_frames(15)
	assert_eq(hurtbox.received.size(), 1, "the implode ticks once on the enemy inside the radius")
	if hurtbox.received.size() == 1:
		var hit: HitInfo = hurtbox.received[0]
		assert_almost_eq(hit.base_damage, _data.base_damage * _data.rank_data(1).damage_mult, 0.001, "the implode hits for the ability's damage at rank 1")
		assert_true(hit.tags.has(&"black_hole"), "the implode hit carries the ability's tag")


func test_a_client_black_hole_does_not_pull() -> void:
	# The cast is made on the host (so _perform sets its pull time), then the clock
	# runs under a client API, so the host-only guard in advance is the one that
	# stops the pull. Restored with the default API afterwards.
	var cast := _cast()
	var near := _stub_at(Vector2(40, 0))
	var default_api: MultiplayerAPI = get_multiplayer()
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", CLIENT_PORT), OK, "the client peer opens")
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = client_peer
	get_tree().set_multiplayer(client_api, get_path())
	cast.advance(0.016)
	get_tree().set_multiplayer(default_api, get_path())
	client_peer.close()
	assert_eq(near.impulses.size(), 0, "a client's Black Hole pulls nothing")
