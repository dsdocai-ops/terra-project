class_name UiPalette
extends RefCounted
## The UI's colours and the few drawing helpers every widget shares: the mine
## palette (stone, bronze, lantern gold, parchment), the rarity colours and the
## status colours. Owned by ui-hud (Dev B). Sync: none, pure presentation.
## The values mirror `assets/ui/theme.tres` so a widget drawn in code and a
## themed Control read as one system.

const PARCHMENT := Color(0.910, 0.847, 0.690)
const INK := Color(0.169, 0.129, 0.094)
const STONE := Color(0.275, 0.208, 0.137)
const STONE_DARK := Color(0.153, 0.110, 0.071)
const BRONZE := Color(0.604, 0.416, 0.180)
const ROPE := Color(0.690, 0.533, 0.314)
const GOLD := Color(0.949, 0.757, 0.306)
const HP_RED := Color(0.847, 0.227, 0.227)
const ALLY_GREEN := Color(0.373, 0.749, 0.416)
const MANA_BLUE := Color(0.290, 0.541, 0.910)
const SHADOW_VIOLET := Color(0.541, 0.353, 0.816)
const COPPER := Color(0.722, 0.451, 0.200)
const DOWNED_GREY := Color(0.46, 0.46, 0.46)
const OUTLINE := Color(0, 0, 0, 0.6)

const RARITY_COLORS: Dictionary[int, Color] = {
	RelicData.Rarity.COMMON: Color(0.812, 0.812, 0.812),
	RelicData.Rarity.RARE: Color(0.290, 0.541, 0.910),
	RelicData.Rarity.EPIC: Color(0.608, 0.365, 0.898),
	RelicData.Rarity.LEGENDARY: Color(0.949, 0.639, 0.227),
	RelicData.Rarity.CURSED: Color(0.690, 0.180, 0.353),
}

const RARITY_NAMES: Dictionary[int, String] = {
	RelicData.Rarity.COMMON: "Common",
	RelicData.Rarity.RARE: "Rare",
	RelicData.Rarity.EPIC: "Epic",
	RelicData.Rarity.LEGENDARY: "Legendary",
	RelicData.Rarity.CURSED: "Cursed",
}

## Indexed by StatusEffects.Status: BURN, CHILL, FREEZE, SHOCK, TOXIN, MARK, BLEED, UNRAVEL.
const STATUS_COLORS: Array[Color] = [
	Color(1.0, 0.478, 0.184),
	Color(0.498, 0.839, 1.0),
	Color(0.75, 0.93, 1.0),
	Color(1.0, 0.88, 0.29),
	Color(0.478, 0.788, 0.263),
	Color(0.80, 0.80, 0.80),
	Color(0.78, 0.12, 0.2),
	Color(0.85, 0.2, 0.75),
]
const STATUS_LABELS: Array[String] = ["BRN", "CHL", "FRZ", "SHK", "TOX", "MRK", "BLD", "UNR"]


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS[RelicData.Rarity.COMMON])


static func rarity_name(rarity: int) -> String:
	return RARITY_NAMES.get(rarity, "Common")


static func status_color(status: int) -> Color:
	if status < 0 or status >= STATUS_COLORS.size():
		return PARCHMENT
	return STATUS_COLORS[status]


static func status_label(status: int) -> String:
	if status < 0 or status >= STATUS_LABELS.size():
		return "???"
	return STATUS_LABELS[status]


## The polygon of the part of a circle (radius `radius`, centred on the origin)
## that lies below a rippling surface, for the lantern's liquid. `ratio` is how
## full the circle is (0 empty, 1 full); empty when there is nothing to draw.
static func liquid_polygon(radius: float, ratio: float, phase: float, steps: int = 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	if ratio <= 0.001 or radius <= 0.0:
		return points
	var level: float = radius - 2.0 * radius * clampf(ratio, 0.0, 1.0)
	var ripple: float = radius * 0.06 if ratio < 0.999 else 0.0
	var tops := PackedVector2Array()
	var bottoms := PackedVector2Array()
	for step: int in range(steps + 1):
		var t: float = float(step) / float(steps)
		var x: float = lerpf(-radius * 0.999, radius * 0.999, t)
		var chord: float = sqrt(maxf(radius * radius - x * x, 0.0))
		var y: float = level + sin(x * 0.35 + phase) * ripple
		tops.append(Vector2(x, clampf(y, -chord, chord)))
		bottoms.append(Vector2(x, chord))
	points.append_array(tops)
	for index: int in range(bottoms.size() - 1, -1, -1):
		points.append(bottoms[index])
	return points


## Bitmap fonts only look right at whole multiples of their base size, so every
## size snaps to 8 (1x), 16 (2x) or 24 (3x).
static func snap_size(wanted: int) -> int:
	if wanted < 12:
		return 8
	if wanted < 20:
		return 16
	return 24


## The largest of 16, then 8, at which `text` fits in `width`.
static func fit_size(font: Font, text: String, width: float, preferred: int = 16) -> int:
	var size: int = snap_size(preferred)
	while size > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 8
	return size


## `text` drawn with a dark outline so it reads on any background.
static func draw_outlined(canvas: CanvasItem, font: Font, position: Vector2, text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var pixel_size: int = snap_size(font_size)
	for offset: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		canvas.draw_string(font, position + offset, text, align, width, pixel_size, OUTLINE)
	canvas.draw_string(font, position, text, align, width, pixel_size, color)


# --- the pixel grid ------------------------------------------------------------
# Every widget draws on a grid of PIXEL x PIXEL screen pixels (2 at the 960x540
# canvas), so circles, polygons and arcs come out as chunky pixel art instead of
# smooth vector shapes. Text and icons already sit on the same grid.

const PIXEL: int = 2


static func cell(value: float, px: int = PIXEL) -> int:
	return int(floorf(value / float(px)))


static func fill_rect_cells(canvas: CanvasItem, x0: int, y0: int, x1: int, y1: int, color: Color, px: int = PIXEL) -> void:
	if x1 < x0 or y1 < y0:
		return
	canvas.draw_rect(Rect2(x0 * px, y0 * px, (x1 - x0 + 1) * px, (y1 - y0 + 1) * px), color)


## A filled disc whose edge steps along the pixel grid.
static func fill_circle(canvas: CanvasItem, center: Vector2, radius: float, color: Color, px: int = PIXEL) -> void:
	var cx: float = float(cell(center.x, px)) * px
	var cy: float = float(cell(center.y, px)) * px
	var rows: int = int(radius / px)
	for iy: int in range(-rows, rows):
		var dy: float = (float(iy) + 0.5) * px
		var half_cells: int = int(sqrt(maxf(radius * radius - dy * dy, 0.0)) / px)
		if half_cells > 0:
			canvas.draw_rect(Rect2(cx - half_cells * px, cy + iy * px, half_cells * 2 * px, px), color)


## A pixel ring: the cells between `radius - thickness` and `radius`.
static func ring(canvas: CanvasItem, center: Vector2, radius: float, thickness: float, color: Color, px: int = PIXEL) -> void:
	arc(canvas, center, radius - thickness * 0.5, 0.0, TAU, color, thickness, px)


## An arc drawn as grid squares of `thickness` screen pixels along the circle.
static func arc(canvas: CanvasItem, center: Vector2, radius: float, start: float, end: float, color: Color, thickness: float = 2.0, px: int = PIXEL) -> void:
	var steps: int = maxi(int(absf(end - start) * radius / float(px) * 1.5), 2)
	var size: float = maxf(thickness, float(px))
	for step: int in range(steps + 1):
		var angle: float = lerpf(start, end, float(step) / float(steps))
		var point: Vector2 = center + Vector2.from_angle(angle) * radius
		var x: float = float(cell(point.x - size * 0.5, px)) * px
		var y: float = float(cell(point.y - size * 0.5, px)) * px
		canvas.draw_rect(Rect2(x, y, size, size), color)


## A straight line of grid squares.
static func line(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, thickness: int = 1, px: int = PIXEL) -> void:
	var x0: int = cell(from.x, px)
	var y0: int = cell(from.y, px)
	var x1: int = cell(to.x, px)
	var y1: int = cell(to.y, px)
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		canvas.draw_rect(Rect2(x0 * px, y0 * px, px * thickness, px * thickness), color)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


## A filled polygon rasterised on the grid (even-odd scanlines through each row's centre).
static func fill_polygon(canvas: CanvasItem, points: PackedVector2Array, color: Color, px: int = PIXEL) -> void:
	if points.size() < 3:
		return
	var min_y: float = points[0].y
	var max_y: float = points[0].y
	for point: Vector2 in points:
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	for row: int in range(cell(min_y, px), cell(max_y, px) + 1):
		var y: float = (float(row) + 0.5) * px
		var crossings: Array[float] = []
		for index: int in points.size():
			var a: Vector2 = points[index]
			var b: Vector2 = points[(index + 1) % points.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				crossings.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
		crossings.sort()
		for pair: int in range(0, crossings.size() - 1, 2):
			var left: int = roundi(crossings[pair] / px)
			var right: int = roundi(crossings[pair + 1] / px)
			if right > left:
				canvas.draw_rect(Rect2(left * px, row * px, (right - left) * px, px), color)


## The outline of a polygon as grid squares.
static func outline_polygon(canvas: CanvasItem, points: PackedVector2Array, color: Color, thickness: int = 1, px: int = PIXEL) -> void:
	for index: int in points.size():
		line(canvas, points[index], points[(index + 1) % points.size()], color, thickness, px)


## `points` moved by `offset` and scaled about the origin by `scale`.
static func placed(points: PackedVector2Array, offset: Vector2, scale: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append(point * scale + offset)
	return out


# --- icons ---------------------------------------------------------------------

const STATUS_ICON_NAMES: Array[String] = ["burn", "chill", "freeze", "shock", "toxin", "mark", "bleed", "unravel"]
static var _icon_cache: Dictionary[String, Texture2D] = {}


## A 16x16 icon from assets/ui/icons/ by file stem, or null when it is missing.
static func icon(stem: String) -> Texture2D:
	if _icon_cache.has(stem):
		return _icon_cache[stem]
	var path: String = "res://assets/ui/icons/%s.png" % stem
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_icon_cache[stem] = texture
	return texture


static func status_icon(status: int) -> Texture2D:
	if status < 0 or status >= STATUS_ICON_NAMES.size():
		return null
	return icon("status_" + STATUS_ICON_NAMES[status])


## Draws `texture` at `at` (top-left) scaled up by whole steps.
static func draw_icon(canvas: CanvasItem, texture: Texture2D, at: Vector2, scale: int = PIXEL) -> void:
	if texture != null:
		canvas.draw_texture_rect(texture, Rect2(at, texture.get_size() * float(scale)), false)
