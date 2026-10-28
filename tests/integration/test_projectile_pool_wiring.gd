extends GutTest
## Integration: the World builds combat-core's ProjectilePool in `_ready` (the
## CombatFeedback pattern — made in code, world.tscn untouched) and warms the
## base projectile scene's set, so the pool exists in the running game. Owned
## by combat-core. The pool's bolts fly from a dedicated container outside
## Entities: Entities is ProjectileSpawner's spawn_path, and the floor-clear
## sweep frees Entities' children — neither may ever see a pooled bolt.

const WORLD_SCENE := "res://scenes/main/world.tscn"
const PROJECTILE_SCENE := "res://scenes/projectiles/projectile.tscn"

var _world: World


func before_each() -> void:
	var packed := load(WORLD_SCENE) as PackedScene
	assert_not_null(packed, "world scene loads")
	if packed == null:
		return
	_world = packed.instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)


func test_the_world_builds_and_warms_the_pool() -> void:
	var pool := _world.get_node_or_null("ProjectilePool") as ProjectilePool
	assert_not_null(pool, "the pool is a World child")
	assert_not_null(_world.get_node_or_null(World.POOLED_PROJECTILES_NAME),
		"a dedicated container for the pooled bolts")
	assert_same(pool.spawn_root, _world.get_node(World.POOLED_PROJECTILES_NAME),
		"acquired bolts fly from the dedicated container")
	assert_false(_world.entities.is_ancestor_of(pool.spawn_root),
		"outside Entities: outside the spawner's spawn_path and the floor-clear sweep")
	assert_eq(pool.created_count, ProjectilePool.WARM_PER_TYPE, "the common scene's set is warmed at load")


func test_a_floor_clear_never_frees_an_in_flight_pooled_bolt() -> void:
	var pool := _world.get_node_or_null("ProjectilePool") as ProjectilePool
	var bolt: Projectile = pool.acquire(load(PROJECTILE_SCENE) as PackedScene)
	bolt.synced_velocity = Vector2(240, 0)
	bolt.launch(HitInfo.new(), Team.Kind.PLAYER, 600.0, 0)
	_world._clear_floor_entities()
	assert_true(is_instance_valid(bolt), "the pool never frees mid-run")
	assert_false(bolt.is_queued_for_deletion(), "a floor change queue_frees nothing pooled")
	assert_same(bolt.get_parent(), pool.spawn_root, "still in flight from its container")
	pool.release(bolt)
