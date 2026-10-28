extends GutTest
## Integration: the World builds combat-core's ProjectilePool in `_ready` (the
## CombatFeedback pattern — made in code, world.tscn untouched) and warms the
## base projectile scene's set, so the pool exists in the running game. Owned
## by combat-core.

const WORLD_SCENE := "res://scenes/main/world.tscn"

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
	assert_same(pool.spawn_root, _world.entities, "acquired bolts fly from the Entities container")
	assert_eq(pool.created_count, ProjectilePool.WARM_PER_TYPE, "the common scene's set is warmed at load")
