extends GutTest
## Tests for scenes/main/main.tscn: loads the world, hands it to GameState,
## and without launch args shows the placeholder Host / Join menu.
## Owned by foundation.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _main: Main


func before_each() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	add_child_autofree(_main)


func after_each() -> void:
	GameState.world = null
	GameState.forced_seed = 0


func test_is_the_project_main_scene() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), MAIN_SCENE)


func test_loads_world_and_registers_it_with_game_state() -> void:
	assert_not_null(_main.world, "world instantiated")
	assert_true(_main.world.is_inside_tree())
	assert_eq(GameState.world, _main.world)


func test_no_args_shows_placeholder_menu() -> void:
	assert_not_null(_main.menu, "menu exists")
	assert_true(_main.menu.visible, "menu shown when no launch args")


func test_apply_options_host_hides_menu_and_sets_seed() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--host", "--seed=99"]))
	_main.apply_options(opts)
	assert_false(_main.menu.visible, "menu hidden in host mode")
	assert_eq(GameState.forced_seed, 99)


func test_apply_options_join_hides_menu() -> void:
	var opts := LaunchArgs.parse(PackedStringArray(["--join=127.0.0.1"]))
	_main.apply_options(opts)
	assert_false(_main.menu.visible)


func test_apply_options_menu_mode_keeps_menu() -> void:
	var opts := LaunchArgs.parse(PackedStringArray())
	_main.apply_options(opts)
	assert_true(_main.menu.visible)


func test_menu_ip_field_defaults_to_localhost() -> void:
	assert_eq(_main.menu.ip_field.text, "127.0.0.1")
