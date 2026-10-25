extends GutTest
## Integration: ending a run on the real main scene opens the HUD's run-over
## screen and locks player input. The button's reload is not exercised here
## (it would reload this test's own scene). Owned by ui-hud; main and HUD are
## loaded, never modified, here.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _main: Main


func before_each() -> void:
	Player.input_locked = false
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.start_solo()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	add_child_autofree(_main)


func after_each() -> void:
	Player.input_locked = false
	GameState.run = null
	GameState.forced_seed = 0
	GameState.world = null
	NetworkManager.disconnect_all()


func test_ending_a_run_opens_the_run_over_screen() -> void:
	var hud := _main.get_node("HUD") as Hud
	GameState.start_run(101, 1, [])
	GameState.end_run(RunEndReason.Reason.DEFEAT)
	assert_true(hud.pause_layer.visible, "run-over screen is shown")
	assert_eq(hud.run_summary.title, "Run over")
	assert_eq(hud.pause_menu.items, ["Back to Menu"] as Array[String])


func test_ending_a_run_locks_player_input() -> void:
	GameState.start_run(102, 1, [])
	GameState.end_run(RunEndReason.Reason.DEFEAT)
	assert_true(Player.input_locked, "movement and attacks are locked")


func test_ending_a_run_sets_the_menu_status_for_the_next_load() -> void:
	GameState.start_run(103, 1, [])
	GameState.end_run(RunEndReason.Reason.EXTRACT)
	assert_eq(Main.take_pending_status(), "Run over. Floors cleared: 0")
