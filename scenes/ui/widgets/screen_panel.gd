class_name ScreenPanel
extends Control
## A stone slab with a title, titled sections of label/value rows and a carved
## button list underneath. The one surface the inventory, death, town and setup
## screens share. Owned by ui-hud (Dev B). Sync: presentation only; a choice is
## reported through `chosen` and the owner decides what to ask the host.

signal chosen(index: int)

const ROW_HEIGHT: float = 16.0
const HEADING_HEIGHT: float = 22.0
const PADDING: float = 18.0
const TITLE_HEIGHT: float = 34.0
const COLUMN_WIDTH: float = 70.0
const FONT_SIZE: int = 8


## A titled block of rows. Each row is its cells (first left, the rest right in
## fixed columns) with one colour per cell; a missing colour is parchment.
class Section extends RefCounted:
	var heading: String = ""
	var rows: Array[PackedStringArray] = []
	var colors: Array[PackedColorArray] = []

	func _init(p_heading: String = "") -> void:
		heading = p_heading

	func add(cells: PackedStringArray, cell_colors: PackedColorArray = PackedColorArray()) -> Section:
		rows.append(cells)
		colors.append(cell_colors)
		return self

	## Convenience for the common two-cell row.
	func pair(label: String, value: String, tint: Color = UiPalette.PARCHMENT) -> Section:
		return add(PackedStringArray([label, value]), PackedColorArray([UiPalette.ROPE, tint]))


var title: String = "":
	set(value):
		title = value
		queue_redraw()
var subtitle: String = "":
	set(value):
		subtitle = value
		queue_redraw()
var sections: Array[Section] = []:
	set(value):
		sections = value
		_relayout()
var buttons: Array[String] = []:
	set(value):
		buttons = value
		_relayout()

var menu: CarvedMenu = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	menu = CarvedMenu.new()
	menu.name = "Menu"
	menu.chosen.connect(_on_menu_chosen)
	add_child(menu)


## Height the sections need, so a screen can size its slab to its content.
func content_height() -> float:
	var total: float = TITLE_HEIGHT + (14.0 if subtitle != "" else 0.0)
	for section: Section in sections:
		total += (HEADING_HEIGHT if section.heading != "" else 0.0) + ROW_HEIGHT * float(section.rows.size()) + 6.0
	return total


func grab_menu_focus() -> void:
	menu.grab_focus()


func _relayout() -> void:
	if menu == null:
		return
	menu.items = buttons
	menu.visible = not buttons.is_empty()
	var top: float = content_height() + PADDING
	menu.position = Vector2(PADDING, top)
	menu.size = Vector2(maxf(size.x - PADDING * 2.0, 120.0), ROW_HEIGHT * 1.6 * float(buttons.size()) + 8.0)
	custom_minimum_size = Vector2(300.0, top + menu.size.y + PADDING)
	queue_redraw()


func _on_menu_chosen(index: int) -> void:
	chosen.emit(index)


func _draw() -> void:
	var w: float = maxf(size.x, custom_minimum_size.x)
	var h: float = maxf(size.y, custom_minimum_size.y)
	var slab := PackedVector2Array([
		Vector2(w * 0.02, 0), Vector2(w * 0.98, h * 0.015), Vector2(w, h * 0.5),
		Vector2(w * 0.985, h), Vector2(w * 0.03, h * 0.985), Vector2(0, h * 0.45)])
	UiPalette.fill_polygon(self, UiPalette.placed(slab, Vector2(3, 4)), Color(0, 0, 0, 0.45))
	UiPalette.fill_polygon(self, slab, Color(0.2, 0.15, 0.1, 0.96))
	UiPalette.outline_polygon(self, slab, UiPalette.BRONZE, 2)
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(PADDING, 26), title, HORIZONTAL_ALIGNMENT_LEFT, w - PADDING * 2.0, 16, UiPalette.GOLD)
	var y: float = TITLE_HEIGHT
	if subtitle != "":
		draw_string(font, Vector2(PADDING, y + 4), subtitle, HORIZONTAL_ALIGNMENT_LEFT, w - PADDING * 2.0, FONT_SIZE, UiPalette.ROPE)
		y += 14.0
	for section: Section in sections:
		if section.heading != "":
			draw_string(font, Vector2(PADDING, y + 12), section.heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiPalette.GOLD)
			y += HEADING_HEIGHT
		for row_index: int in section.rows.size():
			_draw_row(font, section, row_index, y + 10.0, w)
			y += ROW_HEIGHT
		y += 6.0


func _draw_row(font: Font, section: Section, row_index: int, baseline: float, width: float) -> void:
	var cells: PackedStringArray = section.rows[row_index]
	var tints: PackedColorArray = section.colors[row_index]
	for cell_index: int in cells.size():
		var tint: Color = tints[cell_index] if cell_index < tints.size() else UiPalette.PARCHMENT
		if cell_index == 0:
			draw_string(font, Vector2(PADDING, baseline), cells[0], HORIZONTAL_ALIGNMENT_LEFT, width * 0.5, FONT_SIZE, tint)
		else:
			var from_right: int = cells.size() - cell_index
			var right_edge: float = width - PADDING - COLUMN_WIDTH * float(from_right - 1)
			draw_string(font, Vector2(right_edge - COLUMN_WIDTH, baseline), cells[cell_index], HORIZONTAL_ALIGNMENT_RIGHT, COLUMN_WIDTH, FONT_SIZE, tint)
