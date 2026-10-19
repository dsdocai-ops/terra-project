extends GutTest
## Tests for the enemy and projectile spawners under World/Entities and the
## enemy-base StateSync stub (W2-B3). Owned by networking.
## Single-instance: the offline peer is the server, so spawn() runs the custom
## spawn function locally exactly as the host does.

const WORLD_SCENE := "res://scenes/main/world.tscn"
const ENEMY_STUB_SCENE := "res://tests/helpers/enemy_base_stub.tscn"

var _world: World


func before_each() -> void:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world


func after_each() -> void:
	NetworkManager.disconnect_all()
	GameState.world = null


func _spawn_stub_enemy() -> EnemyBaseStub:
	_world.enemy_spawner.enemy_scene = load(ENEMY_STUB_SCENE) as PackedScene
	var node := _world.enemy_spawner.spawn_enemy(EnemySpawnInfo.new(&"grub", Vector2(200, 100), false, 7))
	return node as EnemyBaseStub


# Spawn info round-trips

func test_enemy_spawn_info_defaults() -> void:
	var info := EnemySpawnInfo.new()
	assert_eq(info.kind, &"grub")
	assert_eq(info.spawn_position, Vector2.ZERO)
	assert_false(info.elite)
	assert_eq(info.fight_id, 0)


func test_enemy_spawn_info_round_trips_through_dictionary() -> void:
	var info := EnemySpawnInfo.new(&"rock_tick", Vector2(300, 40), true, 12)
	var copy := EnemySpawnInfo.from_dict(info.to_dict())
	assert_eq(copy.kind, &"rock_tick")
	assert_eq(copy.spawn_position, Vector2(300, 40))
	assert_true(copy.elite)
	assert_eq(copy.fight_id, 12)


func test_enemy_spawn_info_dictionary_uses_plain_types_for_the_wire() -> void:
	var d := EnemySpawnInfo.new(&"grub", Vector2.ZERO, false, 1).to_dict()
	assert_eq(typeof(d["kind"]), TYPE_STRING)
	assert_eq(typeof(d["spawn_position"]), TYPE_VECTOR2)
	assert_eq(typeof(d["elite"]), TYPE_BOOL)
	assert_eq(typeof(d["fight_id"]), TYPE_INT)


func test_projectile_spawn_info_round_trips_through_dictionary() -> void:
	var info := ProjectileSpawnInfo.new(&"pebble", Vector2(150, 80), Vector2(120, 0), 1)
	var copy := ProjectileSpawnInfo.from_dict(info.to_dict())
	assert_eq(copy.projectile_id, &"pebble")
	assert_eq(copy.spawn_position, Vector2(150, 80))
	assert_eq(copy.velocity, Vector2(120, 0))
	assert_eq(copy.owner_peer_id, 1)
	assert_eq(typeof(info.to_dict()["velocity"]), TYPE_VECTOR2, "plain Vector2 on the wire")


# Spawner registration under World/Entities

func test_world_has_enemy_and_projectile_spawners_under_entities() -> void:
	assert_not_null(_world.enemy_spawner, "World/Entities/EnemySpawner")
	assert_not_null(_world.projectile_spawner, "World/Entities/ProjectileSpawner")
	assert_eq(_world.enemy_spawner.get_node(_world.enemy_spawner.spawn_path), _world.entities)
	assert_eq(_world.projectile_spawner.get_node(_world.projectile_spawner.spawn_path), _world.entities)
	assert_true(_world.enemy_spawner is MultiplayerSpawner)
	assert_true(_world.projectile_spawner is MultiplayerSpawner)


# Spawn round-trip

func test_spawn_enemy_creates_a_node_under_entities_with_authority_set() -> void:
	NetworkManager.start_solo()
	var enemy := _spawn_stub_enemy()
	assert_not_null(enemy)
	assert_eq(enemy.get_parent(), _world.entities)
	assert_eq(enemy.name, "Enemy7", "name carries the fight id")
	assert_eq(enemy.fight_id, 7)
	assert_eq(enemy.get_multiplayer_authority(), 1, "root stays host-owned")
	assert_eq(enemy.position, Vector2(200, 100))
	assert_eq(enemy.synced_position, Vector2(200, 100), "spawn pose reaches the replicated fields")


func test_spawn_enemy_assigns_a_fight_id_when_none_is_given() -> void:
	NetworkManager.start_solo()
	var first := _world.enemy_spawner.spawn_enemy(EnemySpawnInfo.new(&"grub"))
	var second := _world.enemy_spawner.spawn_enemy(EnemySpawnInfo.new(&"grub"))
	assert_ne(first.name, second.name, "distinct ids for distinct fights")
	assert_eq(int(String(first.name).trim_prefix("Enemy")) + 1, int(String(second.name).trim_prefix("Enemy")))


func test_spawn_enemy_is_refused_on_a_client() -> void:
	NetworkManager.start_solo()
	var client_spawner := _FakeClientEnemySpawner.new()
	add_child_autofree(client_spawner)
	assert_null(client_spawner.spawn_enemy(EnemySpawnInfo.new(&"grub")), "client spawn request is refused")
	assert_null(_world.entities.get_node_or_null("Enemy1"), "nothing spawned on the client")


func test_spawn_projectile_creates_a_node_under_entities() -> void:
	NetworkManager.start_solo()
	var node := _world.projectile_spawner.spawn_projectile(ProjectileSpawnInfo.new(&"pebble", Vector2(150, 80), Vector2(120, 0), 1))
	assert_not_null(node)
	assert_eq(node.get_parent(), _world.entities)
	assert_eq(node.get_multiplayer_authority(), 1)
	assert_eq(node.position, Vector2(150, 80))
	assert_eq(node.synced_position, Vector2(150, 80))
	assert_eq(node.synced_velocity, Vector2(120, 0))
	assert_eq(node.owner_peer_id, 1)


# Enemy-base stub StateSync (position, anim, HP) — host-authoritative

func test_enemy_stub_state_sync_replicates_position_anim_and_hp() -> void:
	var stub := (load(ENEMY_STUB_SCENE) as PackedScene).instantiate() as EnemyBaseStub
	add_child_autofree(stub)
	var sync := stub.get_node("StateSync") as MultiplayerSynchronizer
	assert_not_null(sync, "stub carries its StateSync")
	assert_eq(sync.root_path, NodePath(".."))
	assert_eq(sync.get_multiplayer_authority(), 1, "host-authoritative synchronizer")
	var cfg := sync.replication_config
	var paths := cfg.get_properties()
	assert_true(paths.has(NodePath(".:synced_position")), "position")
	assert_true(paths.has(NodePath(".:current_anim")), "animation")
	assert_true(paths.has(NodePath(".:current_hp")), "HP")
	assert_true(cfg.property_get_spawn(NodePath(".:synced_position")), "spawn pose is part of the spawn state")
	assert_true(cfg.property_get_spawn(NodePath(".:current_hp")), "HP arrives with the spawn")
	assert_false(paths.has(NodePath(".:position")), "raw position is never replicated")


func test_host_writes_publish_into_the_stub_synced_payload() -> void:
	var stub: EnemyBaseStub = (load(ENEMY_STUB_SCENE) as PackedScene).instantiate()
	add_child_autofree(stub)
	stub.synced_position = Vector2(500, 40)
	stub.current_anim = &"attack"
	stub.current_hp = 3
	await wait_physics_frames(1)
	assert_eq(stub.global_position, Vector2(500, 40), "the synced pose drives the stub's presentation")


# Host-only hit resolution

func test_host_resolves_hits_and_lowers_hp() -> void:
	NetworkManager.start_solo()
	var enemy := _spawn_stub_enemy()
	assert_eq(enemy.current_hp, 10)
	assert_true(enemy.apply_hit(4))
	assert_eq(enemy.current_hp, 6)
	assert_true(enemy.apply_hit(6), "lethal hit lands")
	assert_eq(enemy.current_hp, 0)
	assert_false(enemy.apply_hit(1), "a dead enemy takes no further hits")
	assert_eq(enemy.current_hp, 0)


func test_client_request_does_not_resolve_hits() -> void:
	NetworkManager.start_solo()
	var enemy := _spawn_stub_enemy()
	var client_enemy := _FakeClientEnemyStub.new()
	add_child_autofree(client_enemy)
	client_enemy.current_hp = 10
	assert_false(client_enemy.apply_hit(4), "client-side hit request is refused")
	assert_eq(client_enemy.current_hp, 10, "HP unchanged on the client")
	assert_true(enemy.apply_hit(4), "the same request on the host side lands")


# Client-side doubles ---------------------------------------------------
# GUT runs one instance per process and the offline peer is always the
# server, so a real second instance cannot exist inside a test. These
# subclasses flip the host-only seams (_can_spawn / _resolves_hits) that the
# production scripts expose, driving the client path exactly as a replicated
# copy would. The real client behaviour is re-checked by smoke_two.sh step 3.

class _FakeClientEnemySpawner:
	extends EnemySpawner
	## A client copy of the spawner: _can_spawn() is false there.
	func _can_spawn() -> bool:
		return false


class _FakeClientEnemyStub:
	extends EnemyBaseStub
	## A client copy of the stub: _resolves_hits() is false there.
	func _resolves_hits() -> bool:
		return false