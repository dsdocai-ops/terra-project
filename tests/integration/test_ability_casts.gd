extends GutTest
## Integration of the Week 5 casts so far, Shadow Clones included (SPEC-abilities "Testing", harness): each
## ability's cast is accepted from its slot, emits Events.ability_cast once, is
## refused inside its cooldown, and spawns its zones. Meteor Call's zones wait for
## its landing delay. Chain Lightning reads stand-in enemies in the enemies group.
## Owned by abilities. Physics processing is off, so no frame moves the clocks,
## and the tests advance a cast by hand where a delay is needed.

const SLOT_Q: int = 0

var _controller: AbilityController


func before_each() -> void:
	_controller = AbilityController.new()
	add_child_autofree(_controller)
	_controller.set_physics_process(false)


func after_each() -> void:
	if is_instance_valid(_controller.last_cast) and not _controller.last_cast.is_queued_for_deletion():
		_controller.last_cast.queue_free()


## Puts the ability `id` in the Q slot, casts it at `aim`, then casts again
## inside the cooldown. Checks the event fired once and the second cast was
## refused. Returns the first cast node.
func _cast_once_then_again(id: StringName, aim: Vector2) -> AbilityCast:
	var data := load("res://data/abilities/%s.tres" % id) as AbilityData
	assert_not_null(data, "%s loads" % id)
	_controller.assign(SLOT_Q, data)
	watch_signals(Events)
	assert_true(_controller.request_cast(SLOT_Q, aim), "%s casts from its slot" % id)
	var cast := _controller.last_cast
	assert_not_null(cast, "%s spawns its cast node" % id)
	assert_signal_emit_count(Events, "ability_cast", 1, "%s announces the cast once" % id)
	assert_false(_controller.request_cast(SLOT_Q, aim), "%s is refused inside its cooldown" % id)
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_COOLING, "%s says cooling" % id)
	assert_signal_emit_count(Events, "ability_cast", 1, "the refused cast of %s announces nothing" % id)
	return cast


func _zones_of(cast: Node) -> Array[Zone]:
	var zones: Array[Zone] = []
	for child: Node in cast.get_children():
		var zone := child as Zone
		if zone != null:
			zones.append(zone)
	return zones


func test_meteor_call_lands_after_its_delay_as_a_landing_and_a_burning_ground() -> void:
	var cast := _cast_once_then_again(&"meteor_call", Vector2(120, 0))
	assert_eq(_zones_of(cast).size(), 0, "nothing lands before the delay")
	cast.advance(MeteorCallCast.IMPACT_DELAY + 0.01)
	var zones := _zones_of(cast)
	assert_eq(zones.size(), 2, "the landing and the burning ground spawn at the delay")
	if zones.size() > 0:
		assert_eq(zones[0].global_position, Vector2(120, 0), "the meteor lands on the cursor")


func test_flame_dash_leaves_a_fire_wall_where_the_dash_began() -> void:
	var cast := _cast_once_then_again(&"flame_dash", Vector2(64, 0))
	var zones := _zones_of(cast)
	assert_eq(zones.size(), 1, "one fire wall spawns")
	if zones.size() > 0:
		assert_eq(zones[0].global_position, cast.global_position, "the wall starts where the dash began")


func test_glacier_spike_erupts_one_spike_per_rank_step_along_the_aim() -> void:
	var cast := _cast_once_then_again(&"glacier_spike", Vector2(64, 0))
	var zones := _zones_of(cast)
	assert_eq(zones.size(), 3, "rank 1 erupts three spikes")
	if zones.size() > 0:
		assert_eq(zones[0].global_position, Vector2(36, 0), "the first spike is one spacing out along the aim")


func test_chain_lightning_jumps_to_each_enemy_in_reach() -> void:
	for x: float in [100.0, 200.0, 300.0]:
		_add_enemy_at(Vector2(x, 0))
	var cast := _cast_once_then_again(&"chain_lightning", Vector2(64, 0))
	assert_eq(_zones_of(cast).size(), 3, "the bolt strikes each of the three enemies in reach")


func test_thunder_step_strikes_where_the_player_lands_inside_its_reach() -> void:
	var cast := _cast_once_then_again(&"thunder_step", Vector2(64, 0))
	var zones := _zones_of(cast)
	assert_eq(zones.size(), 1, "one strike spawns where the step lands")
	if zones.size() > 0:
		assert_eq(zones[0].global_position, Vector2(64, 0), "the strike lands at the cursor, inside the reach")


func test_chain_order_takes_the_nearest_unstruck_point_in_reach_up_to_the_jump_count() -> void:
	var points: Array[Vector2] = [Vector2(300, 0), Vector2(100, 0), Vector2(200, 0), Vector2(900, 0)]
	assert_eq(ChainLightningCast.chain_order(Vector2.ZERO, points, 4, 160.0, 120.0), [1, 2, 0], "nearest first, then each hop's nearest")
	assert_eq(ChainLightningCast.chain_order(Vector2.ZERO, points, 2, 160.0, 120.0), [1, 2], "the jump count stops the chain")


func test_chain_order_skips_a_point_out_of_the_first_reach() -> void:
	var points: Array[Vector2] = [Vector2(500, 0)]
	assert_eq(ChainLightningCast.chain_order(Vector2.ZERO, points, 4, 160.0, 120.0), [], "nothing is in the first reach")


## A stand-in enemy: a bare node in the enemies group at `at`, freed after the test.
func _add_enemy_at(at: Vector2) -> void:
	var enemy := Node2D.new()
	enemy.position = at
	add_child_autofree(enemy)
	enemy.add_to_group(Enemy.GROUP)


func test_shadow_clones_spawns_three_clones_around_the_caster() -> void:
	var cast := _cast_once_then_again(&"shadow_clones", Vector2(64, 0)) as ShadowClonesCast
	assert_not_null(cast, "the Shadow Clones cast node is a ShadowClonesCast")
	if cast == null:
		return
	assert_eq(cast.units.size(), 3, "three clones spawn")
	for unit: FriendlyUnit in cast.units:
		assert_true(unit.lifetime > 0.0, "each clone has a lifetime")


func test_a_melee_swing_by_the_owner_reaches_an_enemy_through_a_clone() -> void:
	var owner_node := load("res://scenes/player/player.tscn").instantiate() as Player
	add_child_autofree(owner_node)
	owner_node.global_position = Vector2(200, 200)
	var owner_controller := owner_node.get_node("AbilityController") as AbilityController
	owner_controller.assign(SLOT_Q, load("res://data/abilities/shadow_clones.tres") as AbilityData)
	assert_true(owner_controller.request_cast(SLOT_Q, owner_node.global_position + Vector2(64, 0)), "the owner casts Shadow Clones")
	var cast := owner_controller.last_cast as ShadowClonesCast
	assert_not_null(cast, "the cast node is a ShadowClonesCast")
	if cast == null:
		return
	assert_eq(cast.units.size(), 3, "three clones spawn for the owner")
	for unit: FriendlyUnit in cast.units:
		assert_eq(unit.owner_player, owner_node, "each clone has the caster as its owner")
	var spec := AttackSpec.new()
	spec.reach = 56.0
	spec.base_damage = 20.0
	var weapons := owner_node.get_node("WeaponController") as WeaponController
	weapons.begin_swing(spec, Vector2.RIGHT, 0.0, false)
	var enemy := RecordingHurtbox.new()
	enemy.team = Team.Kind.ENEMY
	add_child_autofree(enemy)
	var hitbox := cast.units[0].get_node("SwingHitbox") as Hitbox
	assert_true(hitbox.try_hit(enemy), "the owner's swing, copied onto a clone, hits an enemy")
	assert_eq(enemy.received.size(), 1, "the enemy is handed one copied hit")
	if enemy.received.size() > 0:
		assert_eq(enemy.received[0].owner_player, owner_node, "the copied hit is credited to the owner")


func test_a_projectile_swing_is_not_copied_but_a_melee_swing_is() -> void:
	var cast := _cast_once_then_again(&"shadow_clones", Vector2(64, 0)) as ShadowClonesCast
	assert_not_null(cast, "the cast node is a ShadowClonesCast")
	if cast == null:
		return
	var projectile := AttackSpec.new()
	projectile.shape = AttackSpec.Shape.PROJECTILE
	projectile.reach = 56.0
	cast.copy_swing(projectile, HitInfo.new())
	for unit: FriendlyUnit in cast.units:
		assert_null(unit.get_node_or_null("SwingHitbox"), "a projectile is not copied onto a clone")
	var melee := AttackSpec.new()
	melee.shape = AttackSpec.Shape.ARC
	melee.reach = 56.0
	cast.copy_swing(melee, HitInfo.new())
	for unit: FriendlyUnit in cast.units:
		assert_not_null(unit.get_node_or_null("SwingHitbox"), "a melee swing is copied onto each clone")


## The radius of a zone's circle, read off its shape node.
func _radius_of(zone: Zone) -> float:
	var shape := zone.get_node("Shape") as CollisionShape2D
	return (shape.shape as CircleShape2D).radius


func test_toxic_cloud_spawns_a_zone_that_grows_and_carries_the_toxin_status() -> void:
	var cast := _cast_once_then_again(&"toxic_cloud", Vector2(120, 0)) as ToxicCloudCast
	assert_not_null(cast, "the Toxic Cloud cast node is a ToxicCloudCast")
	if cast == null:
		return
	var zones := _zones_of(cast)
	assert_eq(zones.size(), 1, "one cloud zone spawns at the cursor")
	if zones.size() == 0:
		return
	var start: float = _radius_of(zones[0])
	cast.advance(cast.life_seconds * 0.5)
	assert_gt(_radius_of(zones[0]), start, "the cloud is larger halfway through its life")
	assert_eq(cast.build_hit().statuses[0].status, StatusEffects.Status.TOXIN, "the cloud's hit applies TOXIN")


func test_stone_skin_buffs_the_caster_and_places_no_zone() -> void:
	var cast := _cast_once_then_again(&"stone_skin", Vector2(64, 0))
	assert_true(cast is StoneSkinCast, "the Stone Skin cast node is a StoneSkinCast")
	assert_eq(_zones_of(cast).size(), 0, "Stone Skin is a buff, not a zone")


func test_black_hole_pulls_then_implodes_once_its_pull_is_spent() -> void:
	var cast := _cast_once_then_again(&"black_hole", Vector2(64, 0)) as BlackHoleCast
	assert_not_null(cast, "the Black Hole cast node is a BlackHoleCast")
	if cast == null:
		return
	assert_eq(_zones_of(cast).size(), 0, "nothing implodes while the pull runs")
	cast.advance(0.016)
	cast.advance(cast.life_seconds - BlackHoleCast.IMPLODE_LEAD)
	assert_eq(_zones_of(cast).size(), 1, "the implode spawns when the pull's time is spent")


func test_barrier_dome_spawns_a_projectile_blocking_zone_at_the_cursor() -> void:
	var cast := _cast_once_then_again(&"barrier_dome", Vector2(120, 0))
	var zones := _zones_of(cast)
	assert_eq(zones.size(), 1, "one dome zone spawns")
	if zones.size() > 0:
		assert_true(zones[0].blocks_projectiles, "the dome zone blocks projectiles")
		assert_eq(zones[0].global_position, Vector2(120, 0), "the dome stands at the cursor")


func test_toxic_cloud_stops_growing_at_its_full_size() -> void:
	var cast := _cast_once_then_again(&"toxic_cloud", Vector2(120, 0)) as ToxicCloudCast
	if cast == null:
		return
	var zones := _zones_of(cast)
	if zones.size() == 0:
		return
	var full: float = ToxicCloudCast.RADIUS * cast.size_mult()
	cast.advance(cast.life_seconds * 2.0)
	assert_almost_eq(_radius_of(zones[0]), full, 0.001, "past its life the cloud is no larger than its full size")
