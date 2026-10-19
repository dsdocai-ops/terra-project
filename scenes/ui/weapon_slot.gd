class_name WeaponSlot
extends Control
## A weapon slot frame: slot number and weapon name in the theme font, a gold
## border when active, and a dark sweep from the bottom while a skill is on
## cooldown. Owned by ui-hud (Dev B). Sync: presentation only.
## Weapon data itself is Dev A's (W2-A7); until then the name is a placeholder.

const BACKGROUND_COLOR := Color(0.169, 0.129, 0.094, 0.75) # UI palette ink
const INLAY_COLOR := Color(0.910, 0.847, 0.690, 0.15) # UI palette parchment, faint
const FRAME_COLOR := Color(0.604, 0.416, 0.180) # UI palette frame_bronze
const ACTIVE_COLOR := Color(0.949, 0.757, 0.306) # UI palette gold
const NUMBER_COLOR := Color(0.949, 0.757, 0.306) # UI palette gold
const NAME_COLOR := Color(0.910, 0.847, 0.690) # UI palette parchment
const COOLDOWN_COLOR := Color(0.0, 0.0, 0.0, 0.55)

var slot_number: String = "1"

var display_name: String = "-":
	set(value):
		display_name = value
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
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, BACKGROUND_COLOR, true)
	if active:
		draw_rect(full, INLAY_COLOR, true)
	draw_rect(full, ACTIVE_COLOR if active else FRAME_COLOR, false, 2.0 if active else 1.0)
	if cooldown_fraction > 0.0:
		var sweep := Rect2(Vector2(0, size.y * (1.0 - cooldown_fraction)), Vector2(size.x, size.y * cooldown_fraction))
		draw_rect(sweep, COOLDOWN_COLOR, true)
	var font: Font = get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	draw_string(font, Vector2(5, 11), slot_number, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, NUMBER_COLOR)
	draw_string(font, Vector2(5, size.y - 5), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, NAME_COLOR)