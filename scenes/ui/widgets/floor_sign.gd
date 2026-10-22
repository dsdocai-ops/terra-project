class_name FloorSign
extends Control
## The floor and biome name on a plank that hangs from two ropes at the top of
## the screen. Drawn on the UI pixel grid. Owned by ui-hud (Dev B).
## Sync: presentation only.

var floor_text: String = "FLOOR -":
	set(value):
		floor_text = value
		queue_redraw()
var biome_text: String = "":
	set(value):
		biome_text = value
		queue_redraw()


func _draw() -> void:
	var plank_top: float = size.y * 0.3
	UiPalette.line(self, Vector2(size.x * 0.22, 0), Vector2(size.x * 0.24, plank_top + 2.0), UiPalette.ROPE, 1)
	UiPalette.line(self, Vector2(size.x * 0.78, 0), Vector2(size.x * 0.76, plank_top + 2.0), UiPalette.ROPE, 1)
	var width: float = size.x
	var height: float = size.y - plank_top
	var plank := PackedVector2Array([
		Vector2(width * 0.02, plank_top + height * 0.08), Vector2(width * 0.55, plank_top),
		Vector2(width * 0.98, plank_top + height * 0.06), Vector2(width * 1.0, plank_top + height * 0.92),
		Vector2(width * 0.45, plank_top + height), Vector2(0.0, plank_top + height * 0.9)])
	UiPalette.fill_polygon(self, plank, Color(0.36, 0.26, 0.15))
	for grain: float in [0.3, 0.6]:
		UiPalette.line(self, Vector2(width * 0.06, plank_top + height * grain), Vector2(width * 0.94, plank_top + height * (grain + 0.02)), Color(0.26, 0.18, 0.1), 1)
	UiPalette.outline_polygon(self, plank, UiPalette.BRONZE, 1)
	var font: Font = get_theme_default_font()
	UiPalette.draw_outlined(self, font, Vector2(0, plank_top + height * 0.52), floor_text, 16, UiPalette.GOLD, HORIZONTAL_ALIGNMENT_CENTER, width)
	if biome_text != "":
		UiPalette.draw_outlined(self, font, Vector2(0, plank_top + height * 0.86), biome_text, 8, UiPalette.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, width)
