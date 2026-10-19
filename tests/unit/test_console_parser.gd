extends GutTest
## Tests for the debug console parser, command registry, and core commands
## (W2-B4, SPEC-debug-tools). Owned by debug-tools.
## Single-instance: the offline peer is the server, so the console's run()
## executes the host path exactly as it does in a real session, and
## NetworkManager.request_debug is exercised with its sender validation.

const CORE_COMMANDS: Array[StringName] = [
	&"help", &"spawn", &"give", &"gold", &"skip", &"seed",
	&"god", &"kill", &"heal", &"timestop", &"fps", &"dump",
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


func test_skip_is_a_stub() -> void:
	var result := _console.run("skip", 1)
	assert_true(String(result).contains("skip"), result)


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
