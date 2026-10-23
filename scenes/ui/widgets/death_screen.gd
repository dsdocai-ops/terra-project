class_name DeathScreen
extends Control
## The end-of-run screen (SPEC-ui-hud "Death screen"): kept versus lost for the
## local player from the RunResult, the dive's numbers, and Return to Town.
## Owned by ui-hud (Dev B). Sync: presentation only; the host built the result.

signal return_requested()

const PANEL_WIDTH: float = 340.0

var panel: ScreenPanel = null
var result: RunResult = null


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.02, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = ScreenPanel.new()
	panel.name = "Panel"
	panel.chosen.connect(_on_chosen)
	add_child(panel)


## Fills the screen for `peer_id` and shows it.
func show_result(run_result: RunResult, peer_id: int) -> void:
	result = run_result
	panel.title = ScreenModels.death_title(run_result.reason)
	panel.sections = ScreenModels.death_sections(run_result, peer_id)
	panel.buttons = ["Return to Town"]
	panel.size = Vector2(PANEL_WIDTH, panel.custom_minimum_size.y)
	panel.position = ((get_viewport_rect().size if is_inside_tree() else Vector2(960, 540)) - panel.size) * 0.5
	visible = true
	panel.grab_menu_focus()


func _on_chosen(_index: int) -> void:
	visible = false
	return_requested.emit()
