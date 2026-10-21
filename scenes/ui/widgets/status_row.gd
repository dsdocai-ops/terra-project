class_name StatusRow
extends Control
## The local player's active statuses as 16x16 pixel icons on a dark disc, with a
## stack count. Owned by ui-hud (Dev B). Sync: presentation only; the statuses are
## read from the player's StatusEffects by HudModel.

const DISC_RADIUS: float = 18.0
const GAP: float = 4.0

var statuses: Array[HudModel.HudStatus] = []:
	set(value):
		statuses = value
		queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	for index: int in statuses.size():
		var entry: HudModel.HudStatus = statuses[index]
		var center := Vector2(DISC_RADIUS + float(index) * (DISC_RADIUS * 2.0 + GAP), size.y * 0.5)
		UiPalette.fill_circle(self, center, DISC_RADIUS, UiPalette.OUTLINE)
		UiPalette.fill_circle(self, center, DISC_RADIUS - 2.0, UiPalette.STONE_DARK)
		UiPalette.ring(self, center, DISC_RADIUS - 2.0, 2.0, UiPalette.status_color(entry.status))
		var icon: Texture2D = UiPalette.status_icon(entry.status)
		if icon != null:
			UiPalette.draw_icon(self, icon, center - icon.get_size())
		if entry.stacks > 1:
			UiPalette.draw_outlined(self, font, center + Vector2(DISC_RADIUS * 0.3, DISC_RADIUS + 4.0), str(entry.stacks), 8, UiPalette.GOLD)
