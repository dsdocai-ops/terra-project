extends GutTest
## Tests for ProjectilePool (SPEC-combat-core "Projectiles": pooled through
## ProjectilePool, per scene type, grow-on-demand, pre-warm 64 per common
## type). Owned by combat-core. The Accept line's "500 pooled projectiles no
## allocs" runs as the brief's no-allocation rule — after warm-up, acquiring
## and releasing 500 projectiles creates no new instances, counted by the
## pool's `created_count` — and as the perf scene's shape: 500 pooled
## projectiles in flight at once after a 500-strong warm-up. "No allocations"
## is read past the node count too: `ProjectileFlight.total_created` must not
## move after warm-up, across idle parked ticks and firing rounds alike.
## Named-method callbacks only.

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectiles/projectile.tscn")

var _root: Node2D
var _pool: ProjectilePool


func before_each() -> void:
	_root = Node2D.new()
	add_child_autofree(_root)
	_pool = ProjectilePool.attach(_root)


# --- attach and warm-up ------------------------------------------------------------------

func test_attach_makes_one_named_pool_and_a_second_attach_reuses_it() -> void:
	assert_same(_root.get_node("ProjectilePool"), _pool)
	assert_same(ProjectilePool.attach(_root), _pool, "a second attach reuses it")


func test_the_warm_set_exists_before_the_first_shot() -> void:
	_pool.warm(PROJECTILE_SCENE)
	assert_eq(_pool.created_count, ProjectilePool.WARM_PER_TYPE, "pre-warm 64 per common type")
	assert_eq(_pool.get_children().size(), ProjectilePool.WARM_PER_TYPE)
	for child: Node in _pool.get_children():
		var projectile := child as Projectile
		assert_not_null(projectile, "the warm set is projectiles")
		assert_false(projectile.visible, "parked out of sight")
		assert_false(projectile.active, "and parked cold")
		assert_true(projectile._retired, "parked retired, out of the physics step")


# --- no allocation after warm-up, flight objects counted too -------------------------------

func test_idle_warm_set_allocates_nothing_on_its_physics_ticks() -> void:
	_pool.warm(PROJECTILE_SCENE)
	var flights_before: int = ProjectileFlight.total_created
	for _frame in 3:
		await get_tree().physics_frame
	assert_eq(ProjectileFlight.total_created, flights_before,
		"parked bolts step nothing, so no idle tick builds a flight")


func test_500_fire_rounds_after_warm_up_allocate_zero_flight_objects() -> void:
	_pool.warm(PROJECTILE_SCENE, 500)
	var flights_before: int = ProjectileFlight.total_created
	for _round in 500:
		var shot: Projectile = _pool.acquire(PROJECTILE_SCENE)
		shot.synced_velocity = Vector2(240, 0)
		shot.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
		_pool.release(shot)
	assert_eq(ProjectileFlight.total_created, flights_before,
		"launch re-arms the pooled flight object instead of making one")


# --- the Accept line: 500 pooled projectiles, no allocations ------------------------------

func test_firing_500_pooled_projectiles_after_warm_up_allocates_nothing() -> void:
	_pool.warm(PROJECTILE_SCENE, 500)
	assert_eq(_pool.created_count, 500, "the warm-up made the whole set")
	var in_flight: Array[Projectile] = []
	for _shot in 500:
		in_flight.append(_pool.acquire(PROJECTILE_SCENE))
	assert_eq(_pool.created_count, 500, "firing all 500 created no new instance")
	for shot: Projectile in in_flight:
		_pool.release(shot)
	assert_eq(_pool.created_count, 500, "and releasing them back neither freed nor copied one")


func test_500_acquire_and_release_rounds_after_warm_up_create_zero_new_instances() -> void:
	_pool.warm(PROJECTILE_SCENE)
	for _round in 500:
		var shot: Projectile = _pool.acquire(PROJECTILE_SCENE)
		_pool.release(shot)
	assert_eq(_pool.created_count, ProjectilePool.WARM_PER_TYPE,
		"no instance past the warm set: 0 new after warm-up")


# --- grow on demand, never free ------------------------------------------------------------

func test_an_empty_type_grows_on_demand_and_shrinks_back_to_reuse() -> void:
	_pool.warm(PROJECTILE_SCENE)
	var in_flight: Array[Projectile] = []
	for _shot in ProjectilePool.WARM_PER_TYPE + 3:
		in_flight.append(_pool.acquire(PROJECTILE_SCENE))
	assert_eq(_pool.created_count, ProjectilePool.WARM_PER_TYPE + 3, "only the 3 past the warm set are new")
	for shot: Projectile in in_flight:
		_pool.release(shot)
	_pool.acquire(PROJECTILE_SCENE)
	assert_eq(_pool.created_count, ProjectilePool.WARM_PER_TYPE + 3, "and it reuses once they come back")


func test_a_reused_bolt_launches_clean_without_a_spec() -> void:
	_pool.warm(PROJECTILE_SCENE, 1)
	var spec: ProjectileSpec = ProjectileSpec.new(null, 240.0, 5.0, HitInfo.Element.NONE, 0, 2, 3.5, 5.0, true)
	var first: Projectile = _pool.acquire(PROJECTILE_SCENE)
	first.synced_velocity = Vector2(240, 0)
	first.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 1, spec)
	assert_eq(first.homing_strength, 3.5, "the spec armed the first shot")
	_pool.release(first)
	var second: Projectile = _pool.acquire(PROJECTILE_SCENE)
	assert_same(second, first, "the pool handed the same bolt back")
	assert_eq(second.homing_strength, 0.0, "the stale homing strength is reset")
	assert_null(second.homing_target, "the stale homing target is reset")
	assert_eq(second.lifetime_seconds, ProjectileFlight.NO_LIFETIME, "the stale lifetime is reset")
	assert_false(second.reflectable, "the stale reflect flag is reset")
	second.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	assert_eq(second.bounces_left(), 0, "no spec: the defaults fly, not the last shot's numbers")


func test_a_released_bolt_returns_to_scale_one_on_reuse() -> void:
	_pool.warm(PROJECTILE_SCENE, 1)
	var first: Projectile = _pool.acquire(PROJECTILE_SCENE)
	first.scale = Vector2.ONE * 1.5
	_pool.release(first)
	var second: Projectile = _pool.acquire(PROJECTILE_SCENE)
	assert_same(second, first, "the same instance comes back")
	assert_almost_eq(second.scale.x, 1.0, 0.001, "the last shot's size is not left behind")
	assert_almost_eq(second.scale.y, 1.0, 0.001)


func test_a_released_projectile_comes_back_the_same_instance() -> void:
	_pool.warm(PROJECTILE_SCENE, 1)
	var first: Projectile = _pool.acquire(PROJECTILE_SCENE)
	_pool.release(first)
	assert_true(is_instance_valid(first), "the pool never frees mid-run")
	assert_same(first.get_parent(), _pool, "parked under the pool again")
	assert_false(first.visible)
	assert_false(first.active, "parked cold")
	var second: Projectile = _pool.acquire(PROJECTILE_SCENE)
	assert_same(second, first, "the same projectile, not a new one")
	assert_true(second.visible, "flown out of hiding")
	assert_false(second._retired, "unretired and ready to launch")


func test_no_pooled_projectile_is_ever_freed_mid_run() -> void:
	_pool.warm(PROJECTILE_SCENE, 4)
	var seen: Array[Projectile] = []
	for _shot in 12:
		var projectile: Projectile = _pool.acquire(PROJECTILE_SCENE)
		seen.append(projectile)
		_pool.release(projectile)
	for projectile: Projectile in seen:
		assert_true(is_instance_valid(projectile), "a pooled projectile is recycled, never freed")


# --- per scene type -------------------------------------------------------------------------

func test_types_pool_separately() -> void:
	var alt_scene := PackedScene.new()
	var alt_source := Projectile.new()
	alt_scene.pack(alt_source)
	alt_source.free()
	_pool.warm(PROJECTILE_SCENE, 2)
	assert_eq(_pool.created_count, 2, "warming the common type")
	var alt_shot: Projectile = _pool.acquire(alt_scene)
	assert_eq(_pool.created_count, 3, "the other type grew on demand, not off the warm set")
	var common_shot: Projectile = _pool.acquire(PROJECTILE_SCENE)
	_pool.release(alt_shot)
	_pool.release(common_shot)
	assert_eq(_pool.free_count(PROJECTILE_SCENE), 2, "the common set is back to 2")
	assert_eq(_pool.free_count(alt_scene), 1, "and the other type holds its one")
	assert_same(_pool.acquire(alt_scene), alt_shot, "each type waits on its own list")


# --- the death path routes through the pool ---------------------------------------------------

func test_an_expired_pooled_projectile_hands_itself_back() -> void:
	_pool.warm(PROJECTILE_SCENE, 1)
	var shot: Projectile = _pool.acquire(PROJECTILE_SCENE)
	assert_same(shot.get_parent(), _root, "in flight it lives in the spawn root")
	shot.synced_velocity = Vector2(240, 0)
	shot.lifetime_seconds = 0.05
	shot.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	shot._host_step(0.1)
	assert_true(shot._retired, "retired the frame it expired")
	assert_false(shot.is_queued_for_deletion(), "the pool never frees mid-run")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_same(shot.get_parent(), _pool, "the deferred hand-back parked it")
	assert_false(shot.visible)
	assert_gt(_pool.free_count(PROJECTILE_SCENE), 0, "back in the free list")


func test_an_unpooled_projectile_still_dies_with_queue_free() -> void:
	var loner: ClearProjectile = ClearProjectile.new()
	autofree(loner)
	loner.synced_velocity = Vector2(240, 0)
	loner.lifetime_seconds = 0.05
	loner.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	loner._host_step(0.1)
	assert_true(loner.is_queued_for_deletion(), "no pool: the old death stands")


## A `Projectile` whose wall ray always reports clear: expiry without a
## physics world, for a projectile that is not in the tree.
class ClearProjectile extends Projectile:
	func _wall_normal_ahead(_step: Vector2) -> Dictionary:
		return {}
