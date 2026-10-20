extends GutTest
## Tests for the debug console parser, command registry, and core commands
## (W2-B4, SPEC-debug-tools). Owned by debug-tools.
## Single-instance: the offline peer is the server, so the console's run()
## executes the host path exactly as it does in a real session, and
## NetworkManager.request_debug is exercised with its sender validation.

const CORE_COMMANDS: Array[StringName] = [
	&"help", &"spawn", &"give", &"gold", &"skip", &"floor", &"seed",
	&"net_lag", &"god", &"kill", &"heal", &"timestop", &"fps", &"dump",
]
const WORLD_SCENE := "res://scenes/main/world.tscn"
const DUMP_PATH := "user://debug_dump.json"

var _console: DebugConsole
var _world: World
var _players: Array[Player] = []


func before_each() -> void:
	_console = DebugConsole.new()
	add_child_autofree(_console)


func after_each() -> void:
	for player: Player in _players:
		player.free()
	_players.clear()
	NetworkManager.disconnect_all()
	# timestop / timeslow leave a global TimeManager effect for their full
	# duration; clear the console's source so it never bleeds into the next
	# test file's scale_for assertions.
	TimeManager.clear_source(&"debug_console")
	GameState.world = null
	GameState.forced_seed = 0
	# skip / floor advance the live run; drop it and the recorded refusal so no
	# run state bleeds into the next test file (LESSONS: autoload state leaks
	# across GUT files).
	GameState.run = null
	GameState.last_advance_refusal = GameState.ADVANCE_REFUSAL_NONE
	# net_lag records on NetworkManager, an autoload: clear it so a simulated
	# latency set here cannot bleed into the next test file (LESSONS: autoload
	# state leaks across GUT files).
	NetworkManager.net_lag_ms = 0
	NetworkManager.net_lag_loss = 0.0
	if FileAccess.file_exists(DUMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DUMP_PATH))


func _spawn_world() -> void:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world


## A real Player node registered with NetworkManager without a scene or the
## tree (its @onready children don't exist on a bare node); enough for
## get_player() and the position the spawn command reads. after_each frees it.
func _add_player(peer_id: int) -> Player:
	var player := Player.new()
	player.name = "Player%d" % peer_id
	player.peer_id = peer_id
	_players.append(player)
	NetworkManager.players[peer_id] = player
	return player


# Parser

func test_tokenize_empty_and_blank_lines() -> void:
	assert_eq(DebugParser.tokenize(""), [] as PackedStringArray)
	assert_eq(DebugParser.tokenize("   \t  "), [] as PackedStringArray)


func test_tokenize_splits_on_whitespace() -> void:
	assert_eq(DebugParser.tokenize("gold 100"), ["gold", "100"] as PackedStringArray)
	assert_eq(DebugParser.tokenize("  seed   42 "), ["seed", "42"] as PackedStringArray)


func test_tokenize_quoted_args_keep_spaces() -> void:
	assert_eq(DebugParser.tokenize("give weapon \"Iron Sword\""), ["give", "weapon", "Iron Sword"] as PackedStringArray)


func test_tokenize_mixed_quoted_and_plain() -> void:
	assert_eq(DebugParser.tokenize("spawn grub 2 elite \"drain\""), ["spawn", "grub", "2", "elite", "drain"] as PackedStringArray)


func test_tokenize_escaped_quotes_inside_quotes() -> void:
	assert_eq(DebugParser.tokenize("echo \"say \\\"hi\\\"\""), ["echo", "say \"hi\""] as PackedStringArray)


func test_tokenize_unterminated_quote_keeps_partial_token() -> void:
	assert_eq(DebugParser.tokenize("spawn \"grub"), ["spawn", "grub"] as PackedStringArray)


# Registry

func test_core_commands_are_registered() -> void:
	for name: StringName in CORE_COMMANDS:
		assert_true(_console.has_command(name), String(name))


func test_unknown_command_is_reported() -> void:
	var result := _console.run("frobnicate the widget", 1)
	assert_true(String(result).contains("unknown"), result)


func test_help_lists_every_core_command() -> void:
	var result := _console.run("help", 1)
	for name: StringName in CORE_COMMANDS:
		assert_true(String(result).contains(String(name)), "%s missing from help" % name)


func test_help_describes_a_single_command() -> void:
	var result := _console.run("help seed", 1)
	assert_true(String(result).contains("seed"), result)
	assert_false(String(result).contains("spawn"), "only the named command is described")


func test_help_unknown_command_reports_unknown() -> void:
	var result := _console.run("help nope", 1)
	assert_true(String(result).contains("unknown"), result)


func test_run_ignores_blank_lines() -> void:
	assert_eq(_console.run("", 1), "")
	assert_eq(_console.run("   ", 1), "")


# Commands

func test_seed_command_sets_game_state_forced_seed() -> void:
	GameState.forced_seed = 0
	var result := _console.run("seed 4242", 1)
	assert_true(String(result).contains("4242"), result)
	assert_eq(GameState.forced_seed, 4242)


func test_seed_zero_clears_forced_seed() -> void:
	GameState.forced_seed = 7
	_console.run("seed 0", 1)
	assert_eq(GameState.forced_seed, 0)


func test_seed_rejects_non_numbers() -> void:
	var result := _console.run("seed abc", 1)
	assert_true(String(result).contains("seed"), result)
	assert_eq(GameState.forced_seed, 0, "a refused seed argument forces nothing")


# seed <n> against GameState — the next run really starts on the forced seed
# (the W3-B1 seed-precedence rule: forced_seed, then the caller's seed, then a
# host roll).


func test_a_run_after_seed_starts_on_the_forced_seed() -> void:
	NetworkManager.start_solo()
	_console.run("seed 4242", 1)
	assert_eq(GameState.forced_seed, 4242)
	# The caller names a different seed: the console's forced_seed has to win.
	GameState.start_run(999, 1, _party([1]))
	assert_not_null(GameState.run)
	assert_eq(GameState.run.seed, 4242, "forced_seed beats the caller's seed")


func test_a_run_after_seed_zero_uses_the_callers_seed() -> void:
	NetworkManager.start_solo()
	GameState.forced_seed = 31337
	_console.run("seed 0", 1)
	assert_eq(GameState.forced_seed, 0, "seed 0 clears the forced seed")
	GameState.start_run(999, 1, _party([1]))
	assert_not_null(GameState.run)
	assert_eq(GameState.run.seed, 999, "with no forced seed the caller's seed is used")


# net_lag -- the placeholder (W3-B5b). The real delay proxy lands in W4-B11; until
# then the command has to be registered, record what it was asked for on
# NetworkManager, and say plainly that nothing is delayed yet.

func test_net_lag_is_registered() -> void:
	assert_true(_console.has_command(&"net_lag"))
	var result := _console.run("help net_lag", 1)
	assert_true(String(result).contains("net_lag"), result)
	assert_true(String(result).contains("latency"), result)


func test_net_lag_records_latency_and_loss_on_network_manager() -> void:
	var result := _console.run("net_lag 150 5", 1)
	assert_eq(NetworkManager.net_lag_ms, 150)
	assert_eq(NetworkManager.net_lag_loss, 5.0)
	assert_true(String(result).contains("150"), result)
	assert_true(String(result).contains("5"), result)


func test_net_lag_defaults_loss_to_zero() -> void:
	_console.run("net_lag 200", 1)
	assert_eq(NetworkManager.net_lag_ms, 200)
	assert_eq(NetworkManager.net_lag_loss, 0.0)


func test_net_lag_says_where_the_real_proxy_lands() -> void:
	var result := _console.run("net_lag 100", 1)
	assert_true(String(result).contains("W4-B11"),
		"the placeholder names the goal that makes it real: %s" % result)
	assert_true(String(result).contains("placeholder"), result)


func test_net_lag_rejects_a_non_integer_millisecond_value() -> void:
	var result := _console.run("net_lag soon", 1)
	assert_true(String(result).contains("net_lag"), result)
	assert_true(String(result).contains("milliseconds"), "the reason is readable: %s" % result)
	assert_eq(NetworkManager.net_lag_ms, 0, "a refused argument changes nothing")
	assert_eq(NetworkManager.net_lag_loss, 0.0)


func test_net_lag_rejects_a_negative_millisecond_value() -> void:
	var result := _console.run("net_lag -40", 1)
	assert_true(String(result).contains("milliseconds"), result)
	assert_eq(NetworkManager.net_lag_ms, 0, "a refused argument changes nothing")


func test_net_lag_rejects_a_non_numeric_loss() -> void:
	_console.run("net_lag 120 2", 1)
	var result := _console.run("net_lag 120 soggy", 1)
	assert_true(String(result).contains("loss"), "the reason is readable: %s" % result)
	assert_eq(NetworkManager.net_lag_ms, 120, "the earlier setting is left alone")
	assert_eq(NetworkManager.net_lag_loss, 2.0, "the earlier loss is left alone")


func test_net_lag_clamps_loss_to_a_percentage() -> void:
	var result := _console.run("net_lag 80 250", 1)
	assert_eq(NetworkManager.net_lag_loss, 100.0, "loss is a percentage and cannot exceed 100")
	assert_true(String(result).contains("100"), result)


func test_net_lag_zero_clears_the_simulation() -> void:
	_console.run("net_lag 150 5", 1)
	var result := _console.run("net_lag 0", 1)
	assert_eq(NetworkManager.net_lag_ms, 0)
	assert_eq(NetworkManager.net_lag_loss, 0.0)
	assert_true(String(result).contains("off"), "clearing is reported: %s" % result)


func test_gold_emits_currency_gained_for_the_issuing_peer() -> void:
	NetworkManager.start_solo()
	var player := _add_player(1)
	watch_signals(Events)
	var result := _console.run("gold 250", 1)
	assert_true(String(result).contains("250"), result)
	assert_signal_emitted_with_parameters(Events, "currency_gained", [player, &"gold", 250])


func test_timestop_stops_enemies() -> void:
	NetworkManager.start_solo()
	watch_signals(TimeManager)
	var result := _console.run("timestop 3", 1)
	assert_true(String(result).contains("3"), result)
	assert_signal_emitted_with_parameters(TimeManager, "enemy_time_changed", [0.0])


func test_timeslow_slows_enemies() -> void:
	NetworkManager.start_solo()
	watch_signals(TimeManager)
	var result := _console.run("timeslow 0.5 2", 1)
	assert_true(String(result).contains("0.5"), result)
	assert_signal_emitted_with_parameters(TimeManager, "enemy_time_changed", [0.5])


func test_spawn_spawns_enemies_at_the_issuing_player() -> void:
	NetworkManager.start_solo()
	_spawn_world()
	var player := _add_player(1)
	player.global_position = Vector2(300, 200)
	var result := _console.run("spawn grub 2", 1)
	assert_true(String(result).contains("2"), result)
	assert_not_null(_world.entities.get_node_or_null("Enemy1"))
	assert_not_null(_world.entities.get_node_or_null("Enemy2"))
	assert_eq(_world.entities.get_node("Enemy1").position, Vector2(300, 200), "spawned at the issuing player")


func test_spawn_reports_without_a_world() -> void:
	var result := _console.run("spawn grub", 1)
	assert_true(String(result).contains("world"), result)


func test_kill_clears_spawned_enemies() -> void:
	NetworkManager.start_solo()
	_spawn_world()
	_add_player(1)
	_console.run("spawn grub 3", 1)
	var result := _console.run("kill", 1)
	assert_true(String(result).contains("3"), result)
	for child in _world.entities.get_children():
		if child.has_method("apply_hit"):
			assert_eq(int(child.get("current_hp")), 0, "%s killed" % child.name)


func test_god_toggles_per_peer() -> void:
	assert_false(_console.is_god(1))
	var result := _console.run("god", 1)
	assert_true(_console.is_god(1), result)
	_console.run("god", 1)
	assert_false(_console.is_god(1))
	_console.run("god", 2)
	assert_true(_console.is_god(2), "god is per peer")


func test_fps_toggles_the_overlay() -> void:
	assert_false(_console.is_fps_overlay())
	_console.run("fps", 1)
	assert_true(_console.is_fps_overlay())
	_console.run("fps", 1)
	assert_false(_console.is_fps_overlay())


func test_dump_writes_a_json_file() -> void:
	var result := _console.run("dump", 1)
	assert_true(String(result).contains("debug_dump.json"), result)
	assert_true(FileAccess.file_exists(DUMP_PATH))
	var file := FileAccess.open(DUMP_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert_true(parsed is Dictionary, "dump is a JSON object")


# skip / floor <n> — the debug floor advance wired to GameState (W3-B5a)


## A one-player party for a headless run.
func _party(peer_ids: Array[int]) -> Array[PlayerSpawnInfo]:
	var party: Array[PlayerSpawnInfo] = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	return party


## A live host run starting on `start_floor`; `required_rooms` is how many rooms
## the floor demands before its exit opens (0 is the RunState default and keeps
## the exit open).
func _start_host_run(start_floor: int = 1, required_rooms: int = 0) -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_host, "test session is a host")
	GameState.start_run(4242, start_floor, _party([1]))
	GameState.run.required_rooms_cleared = required_rooms


func test_skip_advances_the_live_run_one_floor() -> void:
	_start_host_run()
	watch_signals(GameState)
	var result := _console.run("skip", 1)
	assert_not_null(GameState.run, "skip does not end the run")
	assert_eq(GameState.run.floor_index, 2, "skip calls GameState.next_floor()")
	assert_eq(GameState.run.biome_index, 1)
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_NONE,
		"an advance that worked records no refusal")
	assert_signal_emit_count(GameState, "floor_changed", 1)
	assert_true(String(result).contains("2"), "the result names the new floor: %s" % result)


func test_skip_reports_a_shut_exit_without_advancing() -> void:
	_start_host_run(1, 3)
	var result := _console.run("skip", 1)
	assert_eq(GameState.run.floor_index, 1, "a shut exit blocks the advance")
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_EXIT_SHUT)
	assert_true(String(result).contains("skip"), result)
	assert_true(String(result).contains("refused"), result)
	assert_true(String(result).contains("shut"), "the reason is readable: %s" % result)


func test_skip_reports_no_live_run() -> void:
	# A host session with no live run: the refusal is "no run", not "not host".
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_host)
	assert_null(GameState.run)
	var result := _console.run("skip", 1)
	assert_true(String(result).contains("refused"), result)
	assert_true(String(result).contains("no run"), "the reason is readable: %s" % result)
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_NO_RUN)


func test_skip_reports_the_last_floor() -> void:
	_start_host_run(RunState.MAX_FLOOR)
	var result := _console.run("skip", 1)
	assert_eq(GameState.run.floor_index, RunState.MAX_FLOOR)
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_LAST_FLOOR)
	assert_true(String(result).contains("refused"), result)
	assert_true(String(result).contains("last floor"), "the reason is readable: %s" % result)


func test_skip_is_refused_on_a_client() -> void:
	_start_host_run()
	NetworkManager.is_host = false
	var result := _console.run("skip", 1)
	assert_eq(GameState.run.floor_index, 1, "a client never advances the floor")
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_NOT_HOST)
	assert_true(String(result).contains("refused"), result)
	assert_true(String(result).contains("host"), "the reason is readable: %s" % result)


func test_floor_jumps_to_the_named_floor_one_at_a_time() -> void:
	_start_host_run()
	watch_signals(GameState)
	var result := _console.run("floor 5", 1)
	assert_eq(GameState.run.floor_index, 5, "floor <n> advances until the run is on floor n")
	assert_eq(GameState.run.floors_cleared, 4, "one advance per floor passed through")
	assert_signal_emit_count(GameState, "floor_changed", 4)
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_NONE)
	assert_true(String(result).contains("5"), "the result names the target floor: %s" % result)


func test_floor_accepts_the_last_floor() -> void:
	_start_host_run()
	var result := _console.run("floor 30", 1)
	assert_eq(GameState.run.floor_index, RunState.MAX_FLOOR, "floor 30 is a legal jump target")
	assert_true(String(result).contains("30"), result)


func test_floor_on_the_current_floor_does_not_advance() -> void:
	_start_host_run(4)
	var result := _console.run("floor 4", 1)
	assert_eq(GameState.run.floor_index, 4)
	assert_true(String(result).contains("already"), result)


func test_floor_rejects_a_non_integer() -> void:
	_start_host_run()
	var result := _console.run("floor upstairs", 1)
	assert_eq(GameState.run.floor_index, 1, "a bad argument advances nothing")
	assert_true(String(result).contains("whole number"), "the reason is readable: %s" % result)


func test_floor_rejects_a_value_below_the_first_floor() -> void:
	_start_host_run()
	var result := _console.run("floor 0", 1)
	assert_eq(GameState.run.floor_index, 1, "a bad argument advances nothing")
	assert_true(String(result).contains("out of range"), "the reason is readable: %s" % result)


func test_floor_rejects_a_value_above_the_last_floor() -> void:
	_start_host_run()
	var result := _console.run("floor 31", 1)
	assert_eq(GameState.run.floor_index, 1, "a bad argument advances nothing")
	assert_true(String(result).contains("out of range"), "the reason is readable: %s" % result)


func test_floor_refuses_without_a_live_run() -> void:
	# A host session with no live run: the refusal is "no run", not "not host".
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_host)
	assert_null(GameState.run)
	var result := _console.run("floor 3", 1)
	assert_true(String(result).contains("refused"), result)
	assert_true(String(result).contains("no run"), "the reason is readable: %s" % result)
	assert_null(GameState.run, "a refused jump never starts a run")


func test_floor_stops_at_a_shut_exit_and_says_where_it_got_to() -> void:
	_start_host_run(1, 3)
	var result := _console.run("floor 5", 1)
	assert_eq(GameState.run.floor_index, 1, "the shut exit blocks the very first step")
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_EXIT_SHUT)
	assert_true(String(result).contains("refused"), result)
	assert_true(String(result).contains("shut"), "the reason is readable: %s" % result)


func test_floor_does_not_go_backwards() -> void:
	_start_host_run(6)
	var result := _console.run("floor 3", 1)
	assert_eq(GameState.run.floor_index, 6, "floor only advances")
	assert_true(String(result).contains("behind"), "the reason is readable: %s" % result)


func test_floor_is_refused_on_a_client() -> void:
	_start_host_run()
	NetworkManager.is_host = false
	var result := _console.run("floor 5", 1)
	assert_eq(GameState.run.floor_index, 1, "a client never advances the floor")
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_NOT_HOST)
	assert_true(String(result).contains("refused"), result)


func test_heal_is_deferred_until_combat_core() -> void:
	NetworkManager.start_solo()
	_add_player(1)
	var result := _console.run("heal", 1)
	assert_true(String(result).contains("heal"), result)


func test_give_validates_type_and_reports_deferred() -> void:
	var bad := _console.run("give fish flounder", 1)
	assert_true(String(bad).contains("unknown type"), bad)
	var relic := _console.run("give relic ember_boots 2", 1)
	assert_true(String(relic).contains("relic"), relic)
	assert_true(String(relic).contains("ember_boots"), relic)
	assert_true(String(relic).contains("2"), relic)


# request_debug RPC on NetworkManager

func test_request_debug_exists_as_a_rpc() -> void:
	assert_true(NetworkManager.has_method("request_debug"))
	assert_true(NetworkManager.has_signal("debug_command_requested"))


func test_request_debug_runs_on_the_host_and_validates_sender() -> void:
	NetworkManager.start_solo()
	watch_signals(NetworkManager)
	# Called locally the remote sender id is 0, so only a claimed peer of 0
	# matches and is executed; a claimed peer of 1 is refused as a spoof.
	NetworkManager.request_debug("seed 99", 0)
	assert_signal_emitted_with_parameters(NetworkManager, "debug_command_requested", ["seed 99", 0])
	NetworkManager.request_debug("seed 99", 1)
	assert_signal_emit_count(NetworkManager, "debug_command_requested", 1)
	assert_eq(GameState.forced_seed, 99)
