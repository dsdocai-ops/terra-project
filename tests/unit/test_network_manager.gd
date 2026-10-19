extends GutTest
## Tests for the NetworkManager autoload (SPEC-networking). Owned by networking.
## Uses a port off the default so a dev server on 7777 never collides.

const TEST_PORT := 7801


func after_each() -> void:
	NetworkManager.disconnect_all()


func test_enemy_hp_multiplier_table() -> void:
	assert_eq(NetworkManager.enemy_hp_multiplier_for(1), 1.0)
	assert_eq(NetworkManager.enemy_hp_multiplier_for(2), 1.5)
	assert_eq(NetworkManager.enemy_hp_multiplier_for(3), 2.0)
	assert_eq(NetworkManager.enemy_hp_multiplier_for(4), 2.5)
	assert_eq(NetworkManager.enemy_hp_multiplier_for(0), 1.0, "never below solo")


func test_inactive_state_before_anything_starts() -> void:
	assert_false(NetworkManager.is_active)
	assert_eq(NetworkManager.peer_ids, [] as Array[int])
	assert_eq(NetworkManager.player_count(), 0)


func test_start_solo_is_a_host_with_one_peer() -> void:
	watch_signals(NetworkManager)
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_active)
	assert_true(NetworkManager.is_host)
	assert_eq(NetworkManager.local_peer_id, 1)
	assert_eq(NetworkManager.peer_ids, [1] as Array[int])
	assert_eq(NetworkManager.player_count(), 1)
	assert_eq(NetworkManager.enemy_hp_multiplier(), 1.0)
	assert_signal_emitted_with_parameters(NetworkManager, "player_joined", [1])
	assert_true(multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "solo uses the offline peer")


func test_host_opens_an_enet_server_and_counts_itself() -> void:
	watch_signals(NetworkManager)
	assert_eq(NetworkManager.host(TEST_PORT), OK)
	assert_true(NetworkManager.is_host)
	assert_true(multiplayer.multiplayer_peer is ENetMultiplayerPeer)
	assert_eq(NetworkManager.peer_ids, [1] as Array[int])
	assert_signal_emitted_with_parameters(NetworkManager, "player_joined", [1])


func test_hosting_while_active_is_refused_without_touching_the_session() -> void:
	assert_eq(NetworkManager.host(TEST_PORT), OK)
	assert_eq(NetworkManager.host(TEST_PORT), ERR_ALREADY_IN_USE)
	assert_true(NetworkManager.is_host, "first session still up")
	assert_eq(NetworkManager.peer_ids, [1] as Array[int])


func test_joining_while_active_is_refused() -> void:
	NetworkManager.start_solo()
	assert_eq(NetworkManager.join("127.0.0.1", TEST_PORT), ERR_ALREADY_IN_USE)
	assert_true(NetworkManager.is_host, "solo session untouched")


func test_looks_like_address_accepts_ips_and_hostnames() -> void:
	assert_true(NetworkManager.looks_like_address("127.0.0.1"))
	assert_true(NetworkManager.looks_like_address("my-tunnel.playit.gg"))
	assert_false(NetworkManager.looks_like_address(""))
	assert_false(NetworkManager.looks_like_address("not an address"))
	assert_false(NetworkManager.looks_like_address(" 127.0.0.1"))


func test_disconnect_all_resets_to_inactive_offline_peer() -> void:
	NetworkManager.host(TEST_PORT)
	NetworkManager.disconnect_all()
	assert_false(NetworkManager.is_active)
	assert_eq(NetworkManager.peer_ids, [] as Array[int])
	assert_eq(NetworkManager.players.size(), 0)
	assert_true(multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func test_join_with_an_unparseable_address_fails_before_enet() -> void:
	var err := NetworkManager.join("not an address", TEST_PORT)
	assert_eq(err, ERR_INVALID_PARAMETER)
	assert_false(NetworkManager.is_active)


func test_join_registers_as_client_until_connected() -> void:
	# Nothing listens on this port; the connection will time out later, but
	# the manager must already report a pending client session.
	assert_eq(NetworkManager.join("127.0.0.1", TEST_PORT + 1), OK)
	assert_true(NetworkManager.is_active)
	assert_false(NetworkManager.is_host)
	assert_true(multiplayer.multiplayer_peer is ENetMultiplayerPeer)


func test_get_player_returns_null_when_unknown() -> void:
	assert_null(NetworkManager.get_player(42))
