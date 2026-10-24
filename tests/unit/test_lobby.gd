extends GutTest
## The co-op lobby: password hashing, the LAN announcement format, the host
## form's validation and the server list rows.


func _info(server_name: String = "Mine crew", players: int = 1, locked: bool = false) -> LobbyServerInfo:
	var info := LobbyServerInfo.new()
	info.server_name = server_name
	info.players = players
	info.locked = locked
	info.address = "192.168.1.20"
	return info


# --- password ----------------------------------------------------------------


func test_an_empty_password_hashes_to_a_nonempty_marker() -> void:
	assert_false(LobbyAuth.hash_password("").is_empty(), "an empty auth packet cannot be sent")
	assert_eq(LobbyAuth.hash_password(""), LobbyAuth.OPEN)


func test_the_same_password_matches_and_another_does_not() -> void:
	var host_hash: PackedByteArray = LobbyAuth.hash_password("pickaxe")
	assert_true(LobbyAuth.accepts(host_hash, LobbyAuth.hash_password("pickaxe")))
	assert_false(LobbyAuth.accepts(host_hash, LobbyAuth.hash_password("Pickaxe")))
	assert_false(LobbyAuth.accepts(host_hash, LobbyAuth.hash_password("")), "an open join cannot enter a locked server")


func test_an_open_server_accepts_a_joiner_with_no_password() -> void:
	assert_true(LobbyAuth.accepts(LobbyAuth.hash_password(""), LobbyAuth.hash_password("")))
	assert_false(LobbyAuth.accepts(LobbyAuth.hash_password(""), LobbyAuth.hash_password("x")), "a stray password is not an open join")


func test_the_password_never_travels_as_plain_text() -> void:
	var sent: PackedByteArray = LobbyAuth.hash_password("hunter2")
	assert_eq(sent.size(), 32)
	assert_eq(sent.get_string_from_utf8().find("hunter2"), -1)


# --- announcements -----------------------------------------------------------


func test_an_announcement_round_trips() -> void:
	var bytes: PackedByteArray = LobbyDiscovery.encode("Deep shift", 3, 4, true, 7777)
	var info: LobbyServerInfo = LobbyDiscovery.decode(bytes, "10.0.0.5")
	assert_not_null(info)
	assert_eq(info.server_name, "Deep shift")
	assert_eq(info.players, 3)
	assert_eq(info.max_players, 4)
	assert_true(info.locked)
	assert_eq(info.address, "10.0.0.5")
	assert_eq(info.port, 7777)
	assert_eq(info.key(), "10.0.0.5:7777")


func test_junk_and_other_games_are_ignored() -> void:
	assert_null(LobbyDiscovery.decode("not json".to_utf8_buffer(), "1.2.3.4"))
	assert_null(LobbyDiscovery.decode("[1,2]".to_utf8_buffer(), "1.2.3.4"))
	assert_null(LobbyDiscovery.decode('{"g":"other","v":1,"n":"x","l":false}'.to_utf8_buffer(), "1.2.3.4"))
	assert_null(LobbyDiscovery.decode('{"g":"sinkhole","v":99,"n":"x","l":false}'.to_utf8_buffer(), "1.2.3.4"))
	assert_null(LobbyDiscovery.decode('{"g":"sinkhole","v":1,"n":5,"l":false}'.to_utf8_buffer(), "1.2.3.4"))
	assert_null(LobbyDiscovery.decode('{"g":"sinkhole","v":1,"n":"   ","l":false}'.to_utf8_buffer(), "1.2.3.4"))


func test_numbers_from_the_network_are_clamped() -> void:
	var bytes: PackedByteArray = '{"g":"sinkhole","v":1,"n":"x","l":false,"p":99,"m":0,"port":999999}'.to_utf8_buffer()
	var info: LobbyServerInfo = LobbyDiscovery.decode(bytes, "1.2.3.4")
	assert_not_null(info)
	assert_eq(info.players, NetworkManager.MAX_PLAYERS)
	assert_eq(info.max_players, 1)
	assert_eq(info.port, 65535)


func test_a_long_name_is_cut() -> void:
	var info: LobbyServerInfo = LobbyDiscovery.decode(LobbyDiscovery.encode("x".repeat(80), 1, 4, false, 7777), "1.2.3.4")
	assert_eq(info.server_name.length(), LobbyDiscovery.MAX_NAME_LENGTH)


func test_a_full_server_reports_full() -> void:
	var info: LobbyServerInfo = _info("Full house", NetworkManager.MAX_PLAYERS)
	assert_true(info.is_full())
	assert_false(_info("Room", 1).is_full())


# --- the host form -----------------------------------------------------------


func test_the_host_form_needs_a_name() -> void:
	assert_ne(LobbyMenu.host_error("  ", true, ""), "")


func test_the_host_form_needs_a_password_unless_open() -> void:
	assert_ne(LobbyMenu.host_error("Crew", false, ""), "")
	assert_eq(LobbyMenu.host_error("Crew", false, "abc"), "")
	assert_eq(LobbyMenu.host_error("Crew", true, ""), "")


func test_an_address_splits_into_host_and_port() -> void:
	assert_eq(LobbyMenu.parse_address("192.168.1.20"), {"address": "192.168.1.20", "port": NetworkManager.DEFAULT_PORT})
	assert_eq(LobbyMenu.parse_address(" 10.0.0.2:7790 "), {"address": "10.0.0.2", "port": 7790})
	assert_eq(LobbyMenu.parse_address("host:notaport")["port"], NetworkManager.DEFAULT_PORT)


# --- the screen --------------------------------------------------------------


func _lobby() -> LobbyMenu:
	var lobby := LobbyMenu.new()
	add_child_autofree(lobby)
	return lobby


func test_the_list_shows_one_row_per_server_and_an_empty_note() -> void:
	var lobby: LobbyMenu = _lobby()
	lobby._refresh_rows()
	assert_true(lobby._empty_label.visible)
	lobby.discovery.servers["a:1"] = _info("One")
	lobby.discovery.servers["b:1"] = _info("Two", 4, true)
	lobby._refresh_rows()
	await wait_physics_frames(2)
	assert_false(lobby._empty_label.visible)
	assert_eq(lobby._rows.get_child_count(), 2)


func test_joining_an_open_server_asks_for_no_password() -> void:
	var lobby: LobbyMenu = _lobby()
	watch_signals(lobby)
	lobby._on_join_server(_info("Open", 1, false))
	assert_signal_emitted_with_parameters(lobby, "join_requested", ["192.168.1.20", NetworkManager.DEFAULT_PORT, ""])


func test_joining_a_locked_server_prompts_first() -> void:
	var lobby: LobbyMenu = _lobby()
	watch_signals(lobby)
	lobby._on_join_server(_info("Locked", 1, true))
	assert_signal_not_emitted(lobby, "join_requested")
	assert_true(lobby._prompt.visible)
	lobby._on_prompt_join()
	assert_signal_not_emitted(lobby, "join_requested", "an empty password is not sent")
	assert_ne(lobby._prompt_error.text, "")
	lobby._prompt_field.text = "pw"
	lobby._on_prompt_join()
	assert_signal_emitted_with_parameters(lobby, "join_requested", ["192.168.1.20", NetworkManager.DEFAULT_PORT, "pw"])


func test_starting_a_server_emits_the_name_and_password() -> void:
	var lobby: LobbyMenu = _lobby()
	watch_signals(lobby)
	lobby._name_field.text = "Crew"
	lobby._password_field.text = "pw"
	lobby._on_start_server()
	assert_signal_emitted_with_parameters(lobby, "host_requested", ["Crew", "pw"])


func test_no_password_hosts_an_open_server() -> void:
	var lobby: LobbyMenu = _lobby()
	watch_signals(lobby)
	lobby._password_field.text = "ignored"
	lobby._no_password_box.button_pressed = true
	lobby._on_start_server()
	assert_signal_emitted_with_parameters(lobby, "host_requested", ["Mine crew", ""])
	assert_false(lobby._password_field.editable, "the password field is off")


# --- the wire ----------------------------------------------------------------


func test_a_browser_hears_an_announcer_on_the_same_machine() -> void:
	var browser := LobbyDiscovery.new()
	add_child_autofree(browser)
	if not browser.start_browsing():
		pending("UDP %d is taken on this machine" % LobbyDiscovery.ANNOUNCE_PORT)
		return
	var announcer := LobbyDiscovery.new()
	add_child_autofree(announcer)
	announcer.start_announcing("Loopback crew", true, 7791)
	await wait_seconds(2.5)
	var heard: bool = false
	for info: LobbyServerInfo in browser.servers.values():
		if info.server_name == "Loopback crew":
			heard = true
			assert_true(info.locked)
			assert_eq(info.port, 7791)
	if not heard:
		pending("this network did not loop the broadcast back")
	else:
		assert_true(heard)
	announcer.stop()
	browser.stop()
