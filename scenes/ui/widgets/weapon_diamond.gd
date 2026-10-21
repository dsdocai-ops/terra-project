class_name WeaponDiamond
extends Control
## A weapon slot drawn as a stone diamond with the weapon's icon in it: gold-edged
## and glowing when it is the active weapon, with a dark sweep from the bottom
## while its skill recharges. Drawn on the UI pixel grid. Replaces WeaponSlot.
## Owned by ui-hud (Dev B). Sync: presentation only.
## Weapon data is Dev A's (W2-A7); until it lands the name is the weapon id and
## the icon is looked up by it (`weapon_<id>.png` under assets/ui/icons/).

var slot_number: String = "1"
var display_name: String = "-":
	set(value):
		display_name = value
		queue_redraw()
## The weapon id the icon is looked up by; empty for an empty slot.
var weapon_id: String = "":
	set(value):
		weapon_id = value
		queue_redraw()
var active: bool = false:
	set(value):
		active = value
		queue_redraw()
var cooldown_fraction: float = 0.0:
	set(value):
		cooldown_fraction = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	var px: int = UiPalette.PIXEL
	var half: float = float(int(minf(size.x, size.y - 12.0) * 0.5 / px)) * px
	var center := Vector2(float(UiPalette.cell(size.x * 0.5)) * px, half + px * 2.0)
	var diamond := PackedVector2Array([
		center + Vector2(0, -half), center + Vector2(half, 0), center + Vector2(0, half), center + Vector2(-half, 0)])
	if active:
		UiPalette.fill_polygon(self, UiPalette.placed(diamond, center * (1.0 - 1.22), 1.22), Color(UiPalette.GOLD.r, UiPalette.GOLD.g, UiPalette.GOLD.b, 0.25))
	UiPalette.fill_polygon(self, diamond, UiPalette.STONE if active else UiPalette.STONE_DARK)
	var icon: Texture2D = UiPalette.icon("weapon_" + weapon_id) if weapon_id != "" else null
	if icon != null:
		UiPalette.draw_icon(self, icon, center - icon.get_size() * float(px) * 0.5)
	if cooldown_fraction > 0.0:
		var level: float = center.y + half - 2.0 * half * (1.0 - cooldown_fraction)
		UiPalette.fill_polygon(self, _clip_below(diamond, level), Color(0, 0, 0, 0.55))
	UiPalette.outline_polygon(self, diamond, UiPalette.GOLD if active else UiPalette.BRONZE, 2 if active else 1)
	var font: Font = get_theme_default_font()
	UiPalette.draw_outlined(self, font, Vector2(center.x - half, center.y + half - 4.0), slot_number, 8, UiPalette.GOLD if active else UiPalette.ROPE, HORIZONTAL_ALIGNMENT_CENTER, half * 2.0)
	UiPalette.draw_outlined(self, font, Vector2(0, size.y - 2.0), display_name, 8, UiPalette.PARCHMENT if active else UiPalette.ROPE, HORIZONTAL_ALIGNMENT_CENTER, size.x)


## The part of a convex `polygon` with y >= `level`.
static func _clip_below(polygon: PackedVector2Array, level: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for index: int in polygon.size():
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var a_in: bool = a.y >= level
		var b_in: bool = b.y >= level
		if a_in:
			out.append(a)
		if a_in != b_in:
			var t: float = (level - a.y) / (b.y - a.y)
			out.append(a.lerp(b, t))
	return out
