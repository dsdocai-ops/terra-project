extends GutTest
## Tests for LaunchArgs (scripts/launch_args.gd), the --host / --join / --seed
## parser main.gd uses. Owned by foundation.


func test_no_args_is_menu_mode() -> void:
	var opts := LaunchArgs.parse(PackedStringArray())
	assert_eq(opts.mode, LaunchArgs.Mode.MENU)
	assert_false(opts.host)
	assert_eq(opts.join_ip, "")
	assert_eq(opts.run_seed, 0)
	assert_eq(opts.errors, [] as Array[String])


func test_host_flag() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--host"]))
	assert_eq(opts.mode, LaunchArgs.Mode.HOST)
	assert_true(opts.host)


func test_join_with_ip() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--join=127.0.0.1"]))
	assert_eq(opts.mode, LaunchArgs.Mode.JOIN)
	assert_eq(opts.join_ip, "127.0.0.1")


func test_join_with_ip_and_port() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--join=10.0.0.5:7800"]))
	assert_eq(opts.join_ip, "10.0.0.5")
	assert_eq(opts.port, 7800)


func test_default_port_matches_network_manager() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--host"]))
	assert_eq(opts.port, NetworkManager.DEFAULT_PORT)


func test_seed_is_parsed_as_int() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--seed=42"]))
	assert_eq(opts.run_seed, 42)
	assert_eq(opts.mode, LaunchArgs.Mode.MENU, "seed alone does not change the mode")


func test_seed_combines_with_host() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--seed=7", "--host"]))
	assert_eq(opts.mode, LaunchArgs.Mode.HOST)
	assert_eq(opts.run_seed, 7)


func test_join_without_ip_is_an_error_and_falls_back_to_menu() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--join="]))
	assert_eq(opts.mode, LaunchArgs.Mode.MENU)
	assert_gt(opts.errors.size(), 0, "reports the bad argument")


func test_host_and_join_together_is_an_error_host_wins() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--host", "--join=127.0.0.1"]))
	assert_eq(opts.mode, LaunchArgs.Mode.HOST)
	assert_gt(opts.errors.size(), 0)


func test_non_numeric_seed_is_an_error() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--seed=abc"]))
	assert_eq(opts.run_seed, 0)
	assert_gt(opts.errors.size(), 0)


func test_smoke_flag_uses_default_seconds() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--host", "--smoke"]))
	assert_eq(opts.smoke_seconds, LaunchArgs.DEFAULT_SMOKE_SECONDS)
	assert_eq(opts.mode, LaunchArgs.Mode.HOST, "smoke does not change the mode")


func test_smoke_seconds_can_be_set() -> void:
	assert_eq(LaunchArgs.parse(PackedStringArray(["--smoke=5"])).smoke_seconds, 5.0)
	var bad := LaunchArgs.parse(PackedStringArray(["--smoke=soon"]))
	assert_eq(bad.smoke_seconds, 0.0)
	assert_gt(bad.errors.size(), 0)


func test_no_smoke_by_default() -> void:
	assert_eq(LaunchArgs.parse(PackedStringArray()).smoke_seconds, 0.0)


func test_smoke3_flag_uses_default_seconds() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--host", "--smoke3"]))
	assert_eq(opts.smoke3_seconds, LaunchArgs.DEFAULT_SMOKE_SECONDS, "no value uses the smoke default")
	assert_eq(opts.mode, LaunchArgs.Mode.HOST, "smoke3 does not change the mode")


func test_smoke3_seconds_can_be_set() -> void:
	assert_eq(LaunchArgs.parse(PackedStringArray(["--smoke3=14"])).smoke3_seconds, 14.0)
	var bad := LaunchArgs.parse(PackedStringArray(["--smoke3=soon"]))
	assert_eq(bad.smoke3_seconds, 0.0)
	assert_gt(bad.errors.size(), 0, "non-numeric seconds is reported")


func test_smoke3_does_not_trigger_smoke_and_vice_versa() -> void:
	var smoke3 := LaunchArgs.parse(PackedStringArray(["--smoke3=9"]))
	assert_eq(smoke3.smoke_seconds, 0.0, "smoke3 leaves smoke off")
	var smoke := LaunchArgs.parse(PackedStringArray(["--smoke=9"]))
	assert_eq(smoke.smoke3_seconds, 0.0, "smoke leaves smoke3 off")


func test_no_smoke3_by_default() -> void:
	assert_eq(LaunchArgs.parse(PackedStringArray()).smoke3_seconds, 0.0)


func test_debug_tools_flag() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--debug-tools"]))
	assert_true(opts.debug_tools)
	assert_eq(opts.mode, LaunchArgs.Mode.MENU, "debug-tools does not change the mode")


func test_no_debug_tools_by_default() -> void:
	assert_false(LaunchArgs.parse(PackedStringArray()).debug_tools)


func test_unknown_args_are_ignored() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--verbose", "--host", "extra"]))
	assert_eq(opts.mode, LaunchArgs.Mode.HOST)
	assert_eq(opts.errors, [] as Array[String], "unknown args are not errors")
