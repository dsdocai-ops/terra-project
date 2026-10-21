class_name LampMap
extends Control
## The minimap: a miner's lamp. The floor's rooms are drawn as small discs on a
## dark glass, joined by corridors, with the room you are in marked white. Drawn
## on the UI pixel grid. Owned by ui-hud (Dev B). Sync: presentation only. The
## rooms come from the floor layout every peer derives from the same seed
## (FloorLayout, or the lane-B FloorLayoutPlaceholder behind FloorGeneratorSeam),
## so host and clients draw the same map.

## Room rectangles in tiles, inside a `grid_tiles` square.
var rooms: Array[Rect2i] = []:
	set(value):
		rooms = value
		queue_redraw()
var grid_tiles: int = 96:
	set(value):
		grid_tiles = maxi(value, 1)
		queue_redraw()
## Index into `rooms` of the room the local player is in; -1 for none.
var current_room: int = 0:
	set(value):
		current_room = value
		queue_redraw()


## Where room `index` sits on the glass, as a fraction of the glass diameter
## from its centre, in [-0.5, 0.5] on both axes. Public so a test can pin it.
func room_offset(index: int) -> Vector2:
	if index < 0 or index >= rooms.size():
		return Vector2.ZERO
	var rect: Rect2i = rooms[index]
	var middle := Vector2(rect.get_center())
	return (middle / float(grid_tiles) - Vector2(0.5, 0.5)) * 0.8


func _draw() -> void:
	var diameter: float = minf(size.x, size.y)
	var radius: float = float(int(diameter * 0.42 / UiPalette.PIXEL)) * UiPalette.PIXEL
	var center := Vector2(float(UiPalette.cell(size.x * 0.5)) * UiPalette.PIXEL, float(UiPalette.cell(size.y * 0.58)) * UiPalette.PIXEL)
	# Lamp hood.
	UiPalette.fill_polygon(self, PackedVector2Array([
		Vector2(center.x - radius * 0.3, center.y - radius * 1.3), Vector2(center.x + radius * 0.3, center.y - radius * 1.3),
		Vector2(center.x + radius * 0.5, center.y - radius * 0.95), Vector2(center.x - radius * 0.5, center.y - radius * 0.95)]), UiPalette.STONE)
	UiPalette.fill_circle(self, center, radius + 4.0, UiPalette.OUTLINE)
	UiPalette.fill_circle(self, center, radius + 2.0, UiPalette.BRONZE)
	UiPalette.fill_circle(self, center, radius, Color(0.08, 0.06, 0.04))
	var glass_radius: float = radius * 0.88
	var points: Array[Vector2] = []
	for index: int in rooms.size():
		points.append(center + room_offset(index) * diameter * 1.1)
	for index: int in range(1, points.size()):
		UiPalette.line(self, points[index - 1], points[index], Color(0.42, 0.31, 0.19), 2)
	for index: int in points.size():
		var point: Vector2 = points[index]
		if point.distance_to(center) > glass_radius:
			point = center + (point - center).normalized() * glass_radius
		var room_radius: float = maxf(radius * 0.1, 4.0)
		var tint: Color = UiPalette.ROPE
		if index == 0:
			tint = UiPalette.ALLY_GREEN
		elif index == rooms.size() - 1:
			tint = UiPalette.GOLD
		UiPalette.fill_circle(self, point, room_radius, tint.darkened(0.55))
		UiPalette.ring(self, point, room_radius, 2.0, tint)
		if index == current_room:
			UiPalette.fill_circle(self, point, room_radius * 0.5, Color.WHITE)
