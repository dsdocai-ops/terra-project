extends GutTest
## Integration: the crossbow's live shots fly the real Projectile base (W2-A7
## on W2-A6). The World points its ProjectileSpawner at the projectile scene —
## the replacement the spawner's own doc promised once W2-A6 landed — so a
## crossbow swing in the running game launches a real, armed bolt: player team,
## the spec's flight numbers, and a charged heavy's bolt scaled by its charge.
## Single-instance: the offline peer is the server, so `spawn()` runs the
## custom spawn function locally exactly as the host does. Owned by weapons.

const WORLD_SCENE := "res://scenes/main/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CROSSBOW_PATH := "res://data/weapons/crossbow.tres"
const PROJECTILE_SCENE := "res://scenes/projectiles/projectile.tscn"

var _world: World
var _player: Player
var _weapons: WeaponController
var _fired: Array[Projectile] = []


func before_each() -> void:
	_fired.clear()
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world
	NetworkManager.start_solo()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_world.entities.add_child(_player)
	_weapons = _player.get_node("WeaponController") as WeaponController
	_weapons.equip(0, load(CROSSBOW_PATH) as WeaponData)
	Events.projectile_fired.connect(_on_projectile_fired)


func after_each() -> void:
	Events.projectile_fired.disconnect(_on_projectile_fired)
	NetworkManager.disconnect_all()
	GameState.world = null


## Named-method callback (a lambda connect never fires in GUT).
func _on_projectile_fired(shooter: Player, projectile: Node) -> void:
	var bolt := projectile as Projectile
	if bolt != null:
		_fired.append(bolt)


func test_the_worlds_spawner_spawns_the_real_projectile_base() -> void:
	assert_same(_world.projectile_spawner.projectile_scene, load(PROJECTILE_SCENE),
		"the placeholder's promised replacement: live bolts fly the Projectile base")


func test_a_crossbow_light_fires_a_real_armed_bolt() -> void:
	var crossbow: WeaponData = load(CROSSBOW_PATH) as WeaponData
	_weapons.begin_swing(crossbow.light_combo[0], Vector2.RIGHT, 0.0, false)
	assert_eq(_fired.size(), 1, "one bolt per light press")
	if _fired.is_empty():
		return
	var bolt: Projectile = _fired[0]
	assert_same(bolt.get_parent(), _world.entities, "spawned under Entities like any live shot")
	assert_true(bolt.team == Team.Kind.PLAYER, "on the player's team")
	assert_almost_eq(bolt.flight_velocity().x, crossbow.light_combo[0].projectile_speed, 0.01,
		"flying at the spec's speed")
	assert_almost_eq(bolt.range_left(), crossbow.light_combo[0].projectile_range, 0.01,
		"armed with the spec's range")
	assert_almost_eq(bolt.scale.x, 1.0, 0.001, "a light bolt is the base size")


func test_a_charged_crossbow_heavy_fires_a_bigger_bolt() -> void:
	var crossbow: WeaponData = load(CROSSBOW_PATH) as WeaponData
	_weapons.begin_swing(crossbow.heavy, Vector2.RIGHT, 1.0, true)
	assert_eq(_fired.size(), 1, "one bolt per heavy release")
	if _fired.is_empty():
		return
	var bolt: Projectile = _fired[0]
	assert_almost_eq(bolt.scale.x, 1.0 + CrossbowAttack.FULL_CHARGE_SCALE_BONUS, 0.001,
		"the full charge's bolt is the bigger one, on the node that flies")
	assert_almost_eq(bolt.range_left(), crossbow.heavy.projectile_range, 0.01, "at the heavy's range")
	assert_gt(bolt.template.base_damage, crossbow.light_combo[0].base_damage,
		"and carrying the charged heavy's damage")
