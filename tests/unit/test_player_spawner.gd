extends GutTest
## Tests for PlayerSpawnInfo and PlayerSpawner (W1-B8). Owned by networking.
## Single-instance: the offline peer is the server, so spawn() runs the custom
## spawn function locally exactly as the host does.

const WORLD_SCENE := "res://scenes/main/world.tscn"

var _world: World


func before_each() -> void:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world


func after_each() -> void:
	NetworkManager.disconnect_all()
	GameState.world = null


# PlayerSpawnInfo

func test_spawn_info_defaults() -> void:
	var info := PlayerSpawnInfo.new(7)
	assert_eq(info.peer_id, 7)
	assert_eq(info.character_id, &"wren")
	assert_eq(info.class_id, &"warrior")
	assert_eq(info.weapon_ids, [&"pickaxe", &"crossbow"] as Array[StringName])


func test_spawn_info_round_trips_through_dictionary() -> void:
	var info := PlayerSpawnInfo.new(3, &"ivy", &"mage", [&"lantern_staff", &"pickaxe"] as Array[StringName], Vector2(320, 160))
	var copy := PlayerSpawnInfo.from_dict(info.to_dict())
	assert_eq(copy.peer_id, 3)
	assert_eq(copy.character_id, &"ivy")
	assert_eq(copy.class_id, &"mage")
	assert_eq(copy.weapon_ids, [&"lantern_staff", &"pickaxe"] as Array[StringName])
	assert_eq(copy.spawn_position, Vector2(320, 160))


func test_spawn_info_dictionary_uses_plain_types_for_the_wire() -> void:
	var d := PlayerSpawnInfo.new(2).to_dict()
	assert_eq(typeof(d["peer_id"]), TYPE_INT)
	assert_eq(typeof(d["character_id"]), TYPE_STRING)
	assert_eq(typeof(d["weapon_ids"]), TYPE_PACKED_STRING_ARRAY)
	assert_eq(typeof(d["spawn_position"]), TYPE_VECTOR2)


# PlayerSpawner

func test_world_has_a_player_spawner_targeting_players() -> void:
	assert_not_null(_world.player_spawner, "World/PlayerSpawner")
	assert_eq(_world.player_spawner.get_node(_world.player_spawner.spawn_path), _world.players)


func test_spawn_player_creates_a_player_under_players_with_authority_set() -> void:
	NetworkManager.start_solo()
	var player := _world.player_spawner.spawn_player(PlayerSpawnInfo.new(1, &"wren", &"warrior", [&"pickaxe", &"crossbow"] as Array[StringName], Vector2(100, 50)))
	assert_not_null(player)
	assert_eq(player.get_parent(), _world.players)
	assert_eq(player.name, "Player1")
	assert_eq(player.peer_id, 1)
	assert_eq(player.global_position, Vector2(100, 50))
	assert_eq(player.get_multiplayer_authority(), 1, "root stays host-owned")
	assert_eq(player.input_sync.get_multiplayer_authority(), 1, "input belongs to the owning peer")
	assert_eq(player.state_sync.get_multiplayer_authority(), 1, "state belongs to the host")


func test_spawned_player_input_authority_follows_peer_id() -> void:
	NetworkManager.start_solo()
	var player := _world.player_spawner.spawn_player(PlayerSpawnInfo.new(5))
	assert_eq(player.input_sync.get_multiplayer_authority(), 5)
	assert_eq(player.get_multiplayer_authority(), 1)
	assert_false(player.input_sync.public_visibility, "input is sent to the host only")
	assert_true(player.input_sync.get_visibility_for(1), "host can see it")


func test_spawn_registers_in_network_manager_players() -> void:
	NetworkManager.start_solo()
	var player := _world.player_spawner.spawn_player(PlayerSpawnInfo.new(1))
	assert_eq(NetworkManager.get_player(1), player)


func test_despawn_removes_the_node_and_the_registry_entry() -> void:
	NetworkManager.start_solo()
	_world.player_spawner.spawn_player(PlayerSpawnInfo.new(1))
	_world.player_spawner.despawn_player(1)
	await wait_process_frames(1)
	assert_null(_world.players.get_node_or_null("Player1"))
	assert_null(NetworkManager.get_player(1))


func test_spawning_the_same_peer_twice_replaces_the_first() -> void:
	NetworkManager.start_solo()
	var first := _world.player_spawner.spawn_player(PlayerSpawnInfo.new(1))
	var second := _world.player_spawner.spawn_player(PlayerSpawnInfo.new(1))
	await wait_process_frames(1)
	assert_false(is_instance_valid(first), "old node freed")
	assert_eq(NetworkManager.get_player(1), second)
	assert_eq(_world.players.get_child_count(), 1)


func test_network_manager_player_joined_spawns_on_the_host() -> void:
	# start_solo emits player_joined(1); with a world registered the spawner
	# reacts and the host's own player appears without any extra call.
	NetworkManager.start_solo()
	await wait_process_frames(1)
	var player := NetworkManager.get_player(1)
	assert_not_null(player, "host player spawned from player_joined")
	assert_eq(player.get_parent(), _world.players)


func test_player_left_despawns() -> void:
	NetworkManager.start_solo()
	_world.player_spawner.spawn_player(PlayerSpawnInfo.new(9))
	NetworkManager.player_left.emit(9)
	await wait_process_frames(1)
	assert_null(_world.players.get_node_or_null("Player9"))


func test_spawn_positions_spread_players_so_they_do_not_overlap() -> void:
	var a := PlayerSpawner.default_spawn_position(1)
	var b := PlayerSpawner.default_spawn_position(2)
	var c := PlayerSpawner.default_spawn_position(3)
	assert_ne(a, b)
	assert_ne(b, c)
	assert_gt(a.distance_to(b), 16.0)
