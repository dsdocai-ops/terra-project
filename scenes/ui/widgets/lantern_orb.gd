class_name LanternOrb
extends Control
## The player's health: a glass lantern filled with rippling red liquid, a mana
## ring around it, and the HP numbers inside. Drawn on the UI pixel grid, so the
## liquid is stacked pixel columns and the ring is a string of squares.
## Owned by ui-hud (Dev B). Sync: presentation only. Values are set by the HUD
## from HudModel.

const RING_START: float = deg_to_rad(130.0)
const RING_SWEEP: float = deg_to_rad(280.0)

var hp_ratio: float = 1.0:
	set(value):
		hp_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
var mana_ratio: float = 0.0:
	set(value):
		mana_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
var hp_current: int = 100:
	set(value):
		hp_current = value
		queue_redraw()
var hp_max: int = 100:
	set(value):
		hp_max = value
		queue_redraw()
var is_downed: bool = false:
	set(value):
		is_downed = value
		queue_redraw()


func _process(_delta: float) -> void:
	# Only a part-full orb has a surface to ripple.
	if hp_ratio > 0.0 and hp_ratio < 1.0:
		queue_redraw()


func _draw() -> void:
	var px: int = UiPalette.PIXEL
	var radius: float = float(int(minf(size.x, size.y) * 0.32 / px)) * px
	var center := Vector2(float(UiPalette.cell(size.x * 0.5)) * px, float(UiPalette.cell(size.y * 0.58)) * px)
	# Cap: a stepped stone lid with a bronze rim.
	for step: int in 3:
		var half: int = 5 + step * 2
		UiPalette.fill_rect_cells(self, UiPalette.cell(center.x) - half, UiPalette.cell(center.y - radius) - 6 + step * 2, UiPalette.cell(center.x) + half - 1, UiPalette.cell(center.y - radius) - 5 + step * 2, UiPalette.STONE if step < 2 else UiPalette.BRONZE)
	# Mana ring: a dark track with the blue part laid on top.
	var ring_radius: float = radius + 14.0
	UiPalette.arc(self, center, ring_radius, RING_START, RING_START + RING_SWEEP, Color(0, 0, 0, 0.6), 6.0)
	if mana_ratio > 0.0:
		UiPalette.arc(self, center, ring_radius, RING_START, RING_START + RING_SWEEP * mana_ratio, UiPalette.MANA_BLUE, 6.0)
	# Glass and liquid.
	UiPalette.fill_circle(self, center, radius + 4.0, UiPalette.OUTLINE)
	UiPalette.fill_circle(self, center, radius + 2.0, UiPalette.BRONZE)
	UiPalette.fill_circle(self, center, radius, UiPalette.STONE_DARK)
	_draw_liquid(center, radius)
	# Glass highlight.
	UiPalette.fill_rect_cells(self, UiPalette.cell(center.x - radius * 0.55), UiPalette.cell(center.y - radius * 0.5), UiPalette.cell(center.x - radius * 0.55) + 1, UiPalette.cell(center.y - radius * 0.5) + 4, Color(1, 1, 1, 0.3))
	UiPalette.fill_rect_cells(self, UiPalette.cell(center.x - radius * 0.45), UiPalette.cell(center.y - radius * 0.62), UiPalette.cell(center.x - radius * 0.45) + 3, UiPalette.cell(center.y - radius * 0.62), Color(1, 1, 1, 0.3))
	var font: Font = get_theme_default_font()
	var label: String = "DOWN" if is_downed else str(hp_current)
	UiPalette.draw_outlined(self, font, center + Vector2(-radius, 6.0), label, 16, UiPalette.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0)
	if not is_downed:
		UiPalette.draw_outlined(self, font, center + Vector2(-radius, 22.0), "of %d" % hp_max, 8, UiPalette.ROPE, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0)


## Liquid as one pixel column per grid cell, rippling at the surface.
func _draw_liquid(center: Vector2, radius: float) -> void:
	if hp_ratio <= 0.0:
		return
	var px: int = UiPalette.PIXEL
	var level: float = radius - 2.0 * radius * hp_ratio
	var phase: float = float(Time.get_ticks_msec()) / 400.0
	var color: Color = UiPalette.DOWNED_GREY if is_downed else UiPalette.HP_RED
	var light: Color = color.lightened(0.25)
	var columns: int = int(radius / px)
	for index: int in range(-columns, columns):
		var x: float = (float(index) + 0.5) * px
		var chord: float = sqrt(maxf(radius * radius - x * x, 0.0))
		var ripple: float = round(sin(x * 0.18 + phase) * 1.2) * px if hp_ratio < 0.999 else 0.0
		var top: float = clampf(level + ripple, -chord, chord)
		var top_cell: int = int(floorf(top / px))
		var bottom_cell: int = int(chord / px)
		if bottom_cell <= top_cell:
			continue
		var left: float = center.x + float(index) * px
		self.draw_rect(Rect2(left, center.y + top_cell * px, px, (bottom_cell - top_cell) * px), color)
		self.draw_rect(Rect2(left, center.y + top_cell * px, px, px), light)
