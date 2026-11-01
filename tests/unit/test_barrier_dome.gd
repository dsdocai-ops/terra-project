extends GutTest
## Tests for Barrier Dome (SPEC-abilities section 8, Utility; SINKHOLE_SPEC "dome
## that blocks all enemy projectiles for 4 seconds, allies can stand inside"): an
## enemy Projectile inside the dome's edge is blocked, an allied Projectile passes,
## an allied FriendlyUnit inside still takes an enemy hit, and the dome lasts the
## rank's duration. Owned by abilities. Sync: host only. The dome is a Zone with
## blocks_projectiles set; the tests drive the cast and the zone's advance by hand.

const DATA_PATH: String = "res://data/abilities/barrier_dome.tres"
const DOME_CENTRE: Vector2 = Vector2.ZERO
const CLIENT_PORT: int = 7814

var _data: AbilityData


func before_each() -> void:
	_data = load(DATA_PATH) as AbilityData


## Spawns the dome as the cast would, centred on DOME_CENTRE, and returns its zone.
func _spawn_dome() -> Zone:
	var cast := _data.cast_scene.instantiate() as BarrierDomeCast
	cast.setup(null, _data, 1, DOME_CENTRE, Vector2.RIGHT)
	add_child_autofree(cast)
	for child: Node in cast.get_children():
		var zone := child as Zone
		if zone != null:
			return zone
	return null


## A bolt of `side` at `at`, in the tree and not launched, so it only needs its
## position for the dome to find it.
func _bolt(side: Team.Kind, at: Vector2) -> Projectile:
	var bolt := Projectile.new()
	bolt.team = side
	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape_node.shape = circle
	bolt.add_child(shape_node)
	add_child_autofree(bolt)
	bolt.global_position = at
	return bolt


func test_the_dome_is_a_blocking_zone_with_no_damage_tick() -> void:
	var zone := _spawn_dome()
	assert_not_null(zone, "the cast spawns the dome as a Zone")
	if zone == null:
		return
	assert_true(zone.blocks_projectiles, "the dome blocks projectiles")
	assert_eq(zone.ticks_done, 0, "the dome has not ticked a hit yet")


func test_an_enemy_bolt_crossing_the_edge_is_blocked() -> void:
	var zone := _spawn_dome()
	var bolt := _bolt(Team.Kind.ENEMY, Vector2(300, 0))
	var ref: WeakRef = weakref(bolt)
	await wait_physics_frames(2)
	bolt.global_position = DOME_CENTRE + Vector2(10, 0)
	await wait_physics_frames(2)
	zone.advance(0.016)
	assert_true(_ended(ref), "an enemy bolt inside the edge is ended")


func test_an_enemy_bolt_outside_the_edge_is_left_alone() -> void:
	var zone := _spawn_dome()
	var bolt := _bolt(Team.Kind.ENEMY, Vector2(300, 0))
	var ref: WeakRef = weakref(bolt)
	await wait_physics_frames(2)
	zone.advance(0.016)
	assert_false(_ended(ref), "an enemy bolt outside the dome flies on")


func test_an_allied_bolt_crossing_the_edge_is_not_blocked() -> void:
	var zone := _spawn_dome()
	var bolt := _bolt(Team.Kind.PLAYER, Vector2(300, 0))
	var ref: WeakRef = weakref(bolt)
	await wait_physics_frames(2)
	bolt.global_position = DOME_CENTRE + Vector2(10, 0)
	await wait_physics_frames(2)
	zone.advance(0.016)
	assert_false(_ended(ref), "an allied bolt passes through the dome")


func test_an_allied_friendly_unit_inside_the_dome_still_takes_an_enemy_hit() -> void:
	var dome := _spawn_dome()
	assert_not_null(dome, "the dome stands over the ally")
	var unit := FriendlyUnit.new()
	unit.name = "Ally"
	unit.setup(null, 5.0)
	add_child_autofree(unit)
	unit.global_position = DOME_CENTRE + Vector2(8, 0)
	await wait_physics_frames(2)
	# An enemy-side zone strikes the ally while the dome stands over it: the dome
	# neither shields the ally nor stops the enemy's hit from landing.
	var template := HitInfo.new()
	template.base_damage = 10.0
	var enemy_zone := Zone.new()
	enemy_zone.team = Team.Kind.ENEMY
	enemy_zone.configure(template, 1.0, 0.5, null)
	enemy_zone.set_physics_process(false)
	add_child_autofree(enemy_zone)
	var hurtbox := unit.get_node("Hurtbox") as Hurtbox
	var health := unit.get_node("Health") as Health
	var before: float = health.current_hp
	assert_true(enemy_zone.strike(hurtbox), "the enemy hit lands on the allied unit inside the dome")
	assert_lt(health.current_hp, before, "the allied unit loses health")


func test_a_zone_that_does_not_block_leaves_an_enemy_bolt_alone() -> void:
	var zone := Zone.new()
	zone.set_radius(BarrierDomeCast.RADIUS)
	zone.configure(null, 2.0, 0.5, null)
	zone.set_physics_process(false)
	add_child_autofree(zone)
	var bolt := _bolt(Team.Kind.ENEMY, Vector2(300, 0))
	var ref: WeakRef = weakref(bolt)
	await wait_physics_frames(2)
	bolt.global_position = DOME_CENTRE + Vector2(10, 0)
	await wait_physics_frames(2)
	zone.advance(0.016)
	assert_false(_ended(ref), "without blocks_projectiles the zone ends no bolt")


func test_a_bolt_the_physics_server_still_places_inside_is_judged_on_its_real_position() -> void:
	var zone := _spawn_dome()
	zone.set_physics_process(false)
	var bolt := _bolt(Team.Kind.ENEMY, DOME_CENTRE)
	var ref: WeakRef = weakref(bolt)
	await wait_physics_frames(2)
	# The server still has the bolt at the centre, but the bolt now sits outside.
	bolt.global_position = Vector2(300, 0)
	zone.block_projectiles()
	assert_false(_ended(ref), "a bolt that has left the edge is not blocked on its old place")


func test_the_dome_frees_when_its_duration_is_spent() -> void:
	var cast := _data.cast_scene.instantiate() as BarrierDomeCast
	cast.setup(null, _data, 1, DOME_CENTRE, Vector2.RIGHT)
	add_child_autofree(cast)
	var zone: Zone = null
	for child: Node in cast.get_children():
		zone = child as Zone
	assert_not_null(zone, "the dome spawned")
	cast.advance(_data.rank_data(1).duration + 0.01)
	assert_true(cast.is_queued_for_deletion(), "the cast ends when its duration is spent, and the dome with it")


func test_the_dome_lasts_four_seconds_at_rank_one() -> void:
	assert_almost_eq(_data.rank_data(1).duration, 4.0, 0.001, "the spec's 4 seconds at rank 1")


## Whether a bolt has been ended: freed, or queued to be. The dome's own physics
## step can end a bolt during the frames a test waits, so the bolt may already be gone.
func _ended(ref: WeakRef) -> bool:
	var bolt := ref.get_ref() as Node
	return bolt == null or bolt.is_queued_for_deletion()


func test_an_allied_bolt_on_the_enemy_layer_is_still_left_alone() -> void:
	var zone := _spawn_dome()
	zone.set_physics_process(false)
	var bolt := _bolt(Team.Kind.PLAYER, DOME_CENTRE)
	bolt.collision_layer = Hitbox.LAYER_HITBOX_ENEMY
	var ref: WeakRef = weakref(bolt)
	zone.block_projectiles()
	assert_false(_ended(ref), "an allied bolt is not ended even when it sits on the enemy layer")


func test_a_zone_outside_the_tree_blocks_nothing_and_does_not_fail() -> void:
	var zone := Zone.new()
	zone.blocks_projectiles = true
	zone.set_radius(BarrierDomeCast.RADIUS)
	zone.block_projectiles()
	assert_true(true, "the call returns with no physics world to query")
	zone.free()


func test_a_client_dome_blocks_no_enemy_bolt() -> void:
	# The dome is cast on the host, then its clock runs under a client API, so the
	# host-only branch in Zone.advance is the one that stops the block. The bolt is
	# placed inside the edge before the client API is swapped in.
	var zone := _spawn_dome()
	var bolt := _bolt(Team.Kind.ENEMY, DOME_CENTRE + Vector2(10, 0))
	var ref: WeakRef = weakref(bolt)
	var default_api: MultiplayerAPI = get_multiplayer()
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", CLIENT_PORT), OK, "the client peer opens")
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = client_peer
	get_tree().set_multiplayer(client_api, get_path())
	await wait_physics_frames(2)
	zone.advance(0.016)
	get_tree().set_multiplayer(default_api, get_path())
	client_peer.close()
	assert_false(_ended(ref), "a client's dome ends no enemy bolt")


func test_block_on_a_client_projectile_is_refused() -> void:
	var bolt := _bolt(Team.Kind.ENEMY, DOME_CENTRE)
	var ref: WeakRef = weakref(bolt)
	var default_api: MultiplayerAPI = get_multiplayer()
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", CLIENT_PORT), OK, "the client peer opens")
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = client_peer
	get_tree().set_multiplayer(client_api, get_path())
	bolt.block()
	get_tree().set_multiplayer(default_api, get_path())
	client_peer.close()
	assert_false(_ended(ref), "Projectile.block on a client ends nothing")


func test_a_zone_with_no_radius_blocks_nothing() -> void:
	var zone := Zone.new()
	zone.set_physics_process(false)
	zone.blocks_projectiles = true
	add_child_autofree(zone)
	var bolt := _bolt(Team.Kind.ENEMY, Vector2.ZERO)
	var ref: WeakRef = weakref(bolt)
	zone.block_projectiles()
	assert_false(_ended(ref), "a zone with no radius has no edge to block at")
