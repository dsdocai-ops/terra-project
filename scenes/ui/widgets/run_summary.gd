class_name RunSummary
extends Control
## A chipped stone slab listing the run so far (floor, time, currencies, relics).
## Shown beside the pause menu. Owned by ui-hud (Dev B). Sync: presentation only.

var title: String = "Run so far":
	set(value):
		title = value
		queue_redraw()
## "Label" -> "value" rows, in display order.
var rows: Array[PackedStringArray] = []:
	set(value):
		rows = value
		queue_redraw()


## "m:ss" for a whole number of seconds.
static func format_clock(seconds: int) -> String:
	var clamped: int = maxi(seconds, 0)
	return "%d:%02d" % [clamped / 60, clamped % 60]


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var slab := PackedVector2Array([
		Vector2(w * 0.03, 0), Vector2(w * 0.97, h * 0.04), Vector2(w, h * 0.38),
		Vector2(w * 0.98, h), Vector2(w * 0.06, h * 0.96), Vector2(0, h * 0.6)])
	UiPalette.fill_polygon(self, UiPalette.placed(slab, Vector2(3, 4)), Color(0, 0, 0, 0.45))
	UiPalette.fill_polygon(self, slab, Color(0.2, 0.15, 0.1, 0.96))
	UiPalette.outline_polygon(self, slab, UiPalette.BRONZE, 2)
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(18, 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiPalette.GOLD)
	for index: int in rows.size():
		var y: float = 48.0 + float(index) * 18.0
		draw_string(font, Vector2(18, y), rows[index][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiPalette.ROPE)
		draw_string(font, Vector2(18, y), rows[index][1], HORIZONTAL_ALIGNMENT_RIGHT, w - 36.0, 8, UiPalette.PARCHMENT)
