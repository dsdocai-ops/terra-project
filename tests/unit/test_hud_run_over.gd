extends GutTest
## Tests for the HUD's run-over screen: after a run ends the pause layer shows
## "Run over" with a single "Back to Menu" button that emits menu_requested.
## Owned by ui-hud.

const HUD_SCENE := "res://scenes/ui/hud.tscn"

var _hud: Hud


func before_each() -> void:
	_hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child_autofree(_hud)
	watch_signals(_hud)


func test_show_run_over_opens_pause_layer_with_run_over_title() -> void:
	_hud.show_run_over()
	assert_true(_hud.pause_layer.visible, "run-over screen is shown")
	assert_eq(_hud.run_summary.title, "Run over")


func test_show_run_over_leaves_only_back_to_menu() -> void:
	_hud.show_run_over()
	assert_eq(_hud.pause_menu.items, ["Back to Menu"] as Array[String])


func test_choosing_back_to_menu_emits_menu_requested() -> void:
	_hud.show_run_over()
	_hud._on_pause_chosen(0)
	assert_signal_emitted(_hud, "menu_requested")


func test_pause_toggle_is_ignored_after_run_over() -> void:
	_hud.show_run_over()
	_hud.set_paused_view(false)
	_hud.pause_layer.visible = true
	var press := InputEventAction.new()
	press.action = &"pause"
	press.pressed = true
	_hud._unhandled_input(press)
	assert_true(_hud.pause_layer.visible, "pause does not close the run-over screen")
	assert_signal_not_emitted(_hud, "menu_requested")
