extends GutTest
## The melee and enemy cone hitbox shapes are built once and reused (combat v2
## C5, SPEC-project perf: no allocations after warm-up). Owned by combat-core.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"

var _player: Player
var _weapons: WeaponController


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_weapons = _player.get_node("WeaponController") as WeaponController


func test_a_spec_reuses_its_shape_for_every_swing() -> void:
	var spec: AttackSpec = _weapons.active_weapon().light_combo[0]
	var first: Shape2D = _weapons._melee_shape(spec, 0.0, false)
	for _swing in 25:
		assert_same(_weapons._melee_shape(spec, 0.0, false), first)


func test_each_spec_has_its_own_shape() -> void:
	var combo: Array[AttackSpec] = _weapons.active_weapon().light_combo
	assert_ne(_weapons._melee_shape(combo[0], 0.0, false), _weapons._melee_shape(combo[1], 0.0, false))
	assert_ne(_weapons._melee_shape(combo[0], 0.0, false), _weapons._melee_shape(combo[2], 0.0, false), "an arc and a circle differ")


func test_a_heavy_caches_one_shape_per_charge_bucket() -> void:
	var heavy: AttackSpec = _weapons.take_heavy()
	var empty: Shape2D = _weapons._melee_shape(heavy, 0.0, true)
	var full: Shape2D = _weapons._melee_shape(heavy, 1.0, true)
	assert_ne(empty, full, "a full charge reaches further, so it is its own shape")
	assert_same(_weapons._melee_shape(heavy, 0.04, true), empty, "charge 0.04 rounds to the uncharged bucket")
	assert_same(_weapons._melee_shape(heavy, 0.97, true), full, "0.97 rounds to the full bucket")
	assert_same(_weapons._melee_shape(heavy, 0.5, true), _weapons._melee_shape(heavy, 0.55, true), "neighbours in one bucket share")
	assert_gt((full as CircleShape2D).radius, (empty as CircleShape2D).radius)


func test_the_cached_shape_matches_the_stepped_reach() -> void:
	var heavy: AttackSpec = _weapons.take_heavy()
	for charge: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var circle: CircleShape2D = _weapons._melee_shape(heavy, charge, true) as CircleShape2D
		assert_almost_eq(circle.radius, WeaponController.melee_reach(heavy, charge, true), 0.001, "charge %.2f" % charge)
	assert_almost_eq(WeaponController.melee_reach(heavy, 1.0, true), heavy.reach * 1.35, 0.001, "the full charge bonus is unchanged")
	assert_eq(WeaponController.melee_reach(heavy, 1.0, false), heavy.reach, "a light ignores charge")


func test_swinging_reuses_the_hitbox_shape_object_once_warm() -> void:
	var spec: AttackSpec = _weapons.active_weapon().light_combo[0]
	_weapons.begin_swing(spec, Vector2.RIGHT, 0.0, false)
	var shape: Shape2D = _weapons._hitbox_shape.shape
	_weapons.end_swing()
	for _swing in 20:
		_weapons.begin_swing(spec, Vector2.RIGHT, 0.0, false)
		assert_same(_weapons._hitbox_shape.shape, shape, "the hitbox keeps the same shape object")
		_weapons.end_swing()


func test_no_shape_objects_are_created_while_swinging_a_warm_spec() -> void:
	var spec: AttackSpec = _weapons.active_weapon().light_combo[0]
	_weapons.begin_swing(spec, Vector2.RIGHT, 0.0, false)
	_weapons.end_swing()
	var before: int = Performance.get_monitor(Performance.OBJECT_COUNT) as int
	for _swing in 30:
		_weapons._melee_shape(spec, 0.0, false)
	assert_eq(Performance.get_monitor(Performance.OBJECT_COUNT) as int, before, "no objects allocated by 30 lookups")


func test_an_enemy_reuses_its_cone_for_every_attack() -> void:
	var enemy: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.setup(&"hollow_miner")
	add_child_autofree(enemy)
	enemy.next_attack = enemy.data.attacks[0]
	enemy.machine.change_to(&"Attack")
	var attack: Node = enemy.machine.current
	var first: Shape2D = attack.call(&"_cone_shape") as Shape2D
	for _swing in 25:
		assert_same(attack.call(&"_cone_shape") as Shape2D, first)
	var other: AttackPattern = enemy.data.attacks[0].duplicate() as AttackPattern
	other.telegraph_size = Vector2(80.0, 120.0)
	enemy.next_attack = other
	enemy.machine.change_to(&"Chase")
	enemy.machine.change_to(&"Attack")
	var second: Shape2D = enemy.machine.current.call(&"_cone_shape") as Shape2D
	assert_ne(second, first, "a different pattern gets its own cone")
