class_name RelicRope
extends Control
## The relics a player holds, hung as charms from a sagging rope in the bottom
## right corner. A charm's outline shape and colour follow its rarity and the
## relic's own 16x16 icon sits inside it; stacked relics show a count. More
## charms than fit collapse into a "+N" tag. Drawn on the UI pixel grid.
## Owned by ui-hud (Dev B). Sync: presentation only.

const MAX_CHARMS: int = 9
const CHARM_RADIUS: float = 16.0

var relics: Array[HudModel.HudRelic] = []:
	set(value):
		relics = value
		queue_redraw()


## How many charms are drawn (the rest fold into "+N").
func visible_charm_count() -> int:
	return mini(relics.size(), MAX_CHARMS)


## The "+N" overflow tag, empty when everything fits.
func overflow_text() -> String:
	return "+%d" % (relics.size() - MAX_CHARMS) if relics.size() > MAX_CHARMS else ""


## The rope's height at fraction `t` (0 left, 1 right) of its width.
func rope_y(t: float) -> float:
	return 8.0 + sin(t * PI) * size.y * 0.1


func _draw() -> void:
	# An empty rope is just a stray line in the corner: draw it only once a relic hangs on it.
	if relics.is_empty():
		return
	var previous := Vector2(0, rope_y(0.0))
	for step: int in range(1, 25):
		var t: float = float(step) / 24.0
		var next := Vector2(t * size.x, rope_y(t))
		UiPalette.line(self, previous, next, UiPalette.ROPE, 2)
		previous = next
	var count: int = visible_charm_count()
	var font: Font = get_theme_default_font()
	var spacing: float = (size.x - 8.0) / float(MAX_CHARMS)
	for index: int in count:
		var x: float = size.x - spacing * (float(index) + 0.5) - 4.0
		var hang: float = 8.0 + float((index * 7) % 3) * 6.0
		var anchor := Vector2(x, rope_y(x / size.x))
		var center := anchor + Vector2(0, hang + CHARM_RADIUS)
		UiPalette.line(self, anchor, center - Vector2(0, CHARM_RADIUS), UiPalette.ROPE, 1)
		var relic: HudModel.HudRelic = relics[index]
		var color: Color = UiPalette.rarity_color(relic.rarity)
		var shape: PackedVector2Array = charm_shape(relic.rarity, CHARM_RADIUS)
		UiPalette.fill_polygon(self, UiPalette.placed(shape, center + Vector2(2, 2)), UiPalette.OUTLINE)
		UiPalette.fill_polygon(self, UiPalette.placed(shape, center), Color(color.r * 0.45, color.g * 0.45, color.b * 0.45))
		UiPalette.outline_polygon(self, UiPalette.placed(shape, center), color, 1)
		if relic.icon != null:
			UiPalette.draw_icon(self, relic.icon, center - relic.icon.get_size() * float(UiPalette.PIXEL) * 0.5 + Vector2(0, 0))
		else:
			var letter: String = relic.display_name.substr(0, 1).to_upper()
			UiPalette.draw_outlined(self, font, center + Vector2(-CHARM_RADIUS, 4.0), letter, 8, UiPalette.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, CHARM_RADIUS * 2.0)
		if relic.stacks > 1:
			UiPalette.draw_outlined(self, font, center + Vector2(CHARM_RADIUS * 0.3, CHARM_RADIUS + 8.0), "x%d" % relic.stacks, 8, UiPalette.GOLD)
	var overflow: String = overflow_text()
	if overflow != "":
		UiPalette.draw_outlined(self, font, Vector2(2, rope_y(0.0) + 20.0), overflow, 8, UiPalette.GOLD)


## The outline of a charm of `rarity`, centred on the origin: a disc for common,
## a diamond for rare, a hexagon for epic, a pentagon for legendary and a
## jagged shard for cursed.
static func charm_shape(rarity: int, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	match rarity:
		RelicData.Rarity.RARE:
			points = PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])
		RelicData.Rarity.EPIC:
			for corner: int in 6:
				points.append(Vector2.from_angle(float(corner) * TAU / 6.0) * radius)
		RelicData.Rarity.LEGENDARY:
			for corner: int in 5:
				points.append(Vector2.from_angle(float(corner) * TAU / 5.0 - PI * 0.5) * radius)
		RelicData.Rarity.CURSED:
			points = PackedVector2Array([Vector2(0, -radius), Vector2(radius * 0.5, -radius * 0.2), Vector2(radius, radius * 0.7),
				Vector2(0, radius * 0.35), Vector2(-radius, radius * 0.7), Vector2(-radius * 0.5, -radius * 0.2)])
		_:
			for corner: int in 10:
				points.append(Vector2.from_angle(float(corner) * TAU / 10.0) * radius)
	return points
