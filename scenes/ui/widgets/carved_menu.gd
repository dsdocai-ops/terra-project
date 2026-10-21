class_name CarvedMenu
extends Control
## A vertical list of choices drawn as carved text on a gentle curve, with a
## pickaxe pointing at the highlighted one. Up and Down (or the mouse) move,
## Accept (or a click) chooses. Used by the pause screen. Owned by ui-hud
## (Dev B). Sync: presentation only.

signal chosen(index: int)

const ROW_HEIGHT: float = 26.0
const FONT_SIZE: int = 16

var items: Array[String] = []:
	set(value):
		items = value
		selected = clampi(selected, 0, maxi(items.size() - 1, 0))
		custom_minimum_size = Vector2(190, ROW_HEIGHT * items.size() + 8.0)
		queue_redraw()
var selected: int = 0:
	set(value):
		selected = value
		queue_redraw()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func move_selection(step: int) -> void:
	if items.is_empty():
		return
	selected = posmod(selected + step, items.size())


## How far row `index` is pushed right so the list bows like a lantern's glass.
func row_indent(index: int) -> float:
	if items.size() <= 1:
		return 0.0
	var t: float = float(index) / float(items.size() - 1)
	return sin(t * PI) * 14.0


func _row_at(point: Vector2) -> int:
	var index: int = int(point.y / ROW_HEIGHT)
	return index if index >= 0 and index < items.size() else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var row: int = _row_at((event as InputEventMouseMotion).position)
		if row >= 0:
			selected = row
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			var row: int = _row_at(click.position)
			if row >= 0:
				selected = row
				chosen.emit(row)
	elif event.is_action_pressed(&"ui_up"):
		move_selection(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_down"):
		move_selection(1)
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		chosen.emit(selected)
		accept_event()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	for index: int in items.size():
		var is_selected: bool = index == selected
		var baseline := Vector2(24.0 + row_indent(index), ROW_HEIGHT * float(index) + 18.0)
		if is_selected:
			_draw_pickaxe(baseline + Vector2(-20.0, -6.0))
		var color: Color = UiPalette.GOLD if is_selected else UiPalette.PARCHMENT
		draw_string(font, baseline + Vector2(1, 2), items[index], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.8))
		draw_string(font, baseline, items[index], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


func _draw_pickaxe(at: Vector2) -> void:
	UiPalette.draw_icon(self, UiPalette.icon("pointer"), at + Vector2(-14.0, -10.0))
