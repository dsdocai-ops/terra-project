class_name TeammateBadge
extends Control
## One teammate: a round badge with an HP ring around it and their name under
## it. A downed teammate gets a hatched grey ring and a cross. Drawn on the UI
## pixel grid. Owned by ui-hud (Dev B). Sync: presentation only.

const SKIN_TONES: Array[Color] = [
	Color(0.85, 0.70, 0.48), Color(0.72, 0.55, 0.36), Color(0.60, 0.42, 0.28), Color(0.90, 0.78, 0.62)]

var display_name: String = "":
	set(value):
		display_name = value
		queue_redraw()
var hp_ratio: float = 1.0:
	set(value):
		hp_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
var is_downed: bool = false:
	set(value):
		is_downed = value
		queue_redraw()
## 0 to 3, the player slot; picks the skin tone of the placeholder face.
var slot: int = 0:
	set(value):
		slot = value
		queue_redraw()


func _draw() -> void:
	var px: int = UiPalette.PIXEL
	var radius: float = float(int(minf(size.x * 0.5, (size.y - 12.0) * 0.5) / px)) * px - px
	var center := Vector2(float(UiPalette.cell(size.x * 0.5)) * px, radius + px * 2.0)
	UiPalette.fill_circle(self, center, radius + px, UiPalette.OUTLINE)
	UiPalette.fill_circle(self, center, radius, UiPalette.STONE_DARK)
	var skin: Color = SKIN_TONES[posmod(slot, SKIN_TONES.size())]
	if is_downed:
		for index: int in 8:
			var start: float = float(index) * TAU / 8.0
			UiPalette.arc(self, center, radius - 2.0, start, start + TAU / 16.0, UiPalette.DOWNED_GREY, 4.0)
		var arm: float = radius * 0.4
		UiPalette.line(self, center + Vector2(-arm, -arm), center + Vector2(arm, arm), UiPalette.DOWNED_GREY, 2)
		UiPalette.line(self, center + Vector2(arm, -arm), center + Vector2(-arm, arm), UiPalette.DOWNED_GREY, 2)
	else:
		UiPalette.fill_circle(self, center + Vector2(0, -radius * 0.18), radius * 0.3, skin)
		UiPalette.fill_polygon(self, PackedVector2Array([
			center + Vector2(-radius * 0.55, radius * 0.65), center + Vector2(-radius * 0.4, radius * 0.2),
			center + Vector2(radius * 0.4, radius * 0.2), center + Vector2(radius * 0.55, radius * 0.65)]), skin.darkened(0.15))
		if hp_ratio > 0.0:
			UiPalette.arc(self, center, radius - 2.0, -PI * 0.5, -PI * 0.5 + TAU * hp_ratio, UiPalette.ALLY_GREEN, 4.0)
	var font: Font = get_theme_default_font()
	var tint: Color = UiPalette.DOWNED_GREY if is_downed else UiPalette.PARCHMENT
	UiPalette.draw_outlined(self, font, Vector2(0, size.y - 2.0), display_name, 8, tint, HORIZONTAL_ALIGNMENT_CENTER, size.x)
