class_name CurrencyReadout
extends Control
## The run's three currencies: the pickup sprite for each next to a right-aligned
## number. Gold (shared), Ore (shared, all kinds summed) and Echo Shards (this
## player's). Owned by ui-hud (Dev B). Sync: presentation only.

var gold: int = 0:
	set(value):
		gold = value
		queue_redraw()
var ore: int = 0:
	set(value):
		ore = value
		queue_redraw()
var echo: int = 0:
	set(value):
		echo = value
		queue_redraw()


## Thousands separators: 1240 -> "1,240".
static func format_amount(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	for index: int in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			out += ","
		out += digits[index]
	return ("-" if amount < 0 else "") + out


## The pickup sprites, kept for the widget's lifetime: a texture loaded inside
## _draw and held only by a local is freed before the renderer draws it.
var _sprites: Dictionary[StringName, Texture2D] = {}


func _sprite_for(kind: StringName) -> Texture2D:
	if not _sprites.has(kind):
		_sprites[kind] = load(Pickup.art_path_for(kind)) as Texture2D
	return _sprites[kind]

func _draw() -> void:
	var font: Font = get_theme_default_font()
	var rows: Array[Dictionary] = [
		{"amount": gold, "kind": &"gold"},
		{"amount": ore, "kind": &"ore"},
		{"amount": echo, "kind": &"echo"},
	]
	var row_height: float = size.y / float(rows.size())
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var y: float = row_height * (float(index) + 0.5)
		var sprite: Texture2D = _sprite_for(row["kind"] as StringName)
		if sprite != null:
			var at := Vector2(size.x - sprite.get_width() * 2.0, y - sprite.get_height())
			draw_texture_rect(sprite, Rect2(at, sprite.get_size() * 2.0), false)
		UiPalette.draw_outlined(self, font, Vector2(0, y + 6.0), format_amount(int(row["amount"])), 16, UiPalette.PARCHMENT, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 36.0)
