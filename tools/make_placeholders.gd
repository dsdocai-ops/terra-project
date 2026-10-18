extends SceneTree
## Generates placeholder PNGs so every system has a visible stand-in before
## real art exists (art-audio). Owned by foundation / art-audio. Sync: none.
##
## Run from the repo root:
##   godot --headless --path . -s tools/make_placeholders.gd
## Then run `--import`, then tools/make_placeholder_tileset.gd.
##
## Outputs
##   assets/tilesets/placeholder/atlas.png      192x32, floor | wall | pit diamonds
##   assets/sprites/player/placeholder_sheet.png 384x48, 8 facing diamonds with arrows
##   assets/sprites/icons/placeholder/<A..Z>.png 16x16 lettered squares

const TILE_W := 64
const TILE_H := 32
const SPRITE := 48

const FLOOR_COLOR := Color(0.55, 0.52, 0.47)
const WALL_COLOR := Color(0.30, 0.22, 0.16)
const PIT_COLOR := Color(0.06, 0.05, 0.08)
const EDGE_COLOR := Color(0.12, 0.10, 0.09)
const BODY_COLOR := Color(0.25, 0.65, 0.85)
const ARROW_COLOR := Color(1.0, 0.95, 0.6)
const ICON_BG := Color(0.2, 0.2, 0.25)
const ICON_FG := Color(0.95, 0.9, 0.8)

## Facing order matches Player.facing_index: s, sw, w, nw, n, ne, e, se.
## Angles are screen-space degrees; diagonals follow the isometric tile axes.
const FACING_DEGREES: Array[float] = [90.0, 153.435, 180.0, 206.565, 270.0, 333.435, 0.0, 26.565]

## 3x5 pixel glyphs for A to Z, rows top to bottom, '#' is lit.
const GLYPHS := {
	"A": ["###", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": ["###", "#..", "#..", "#..", "###"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
	"G": ["###", "#..", "#.#", "#.#", "###"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", "###"],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
	"O": ["###", "#.#", "#.#", "#.#", "###"], "P": ["###", "#.#", "###", "#..", "#.."],
	"Q": ["###", "#.#", "#.#", "###", "..#"], "R": ["###", "#.#", "##.", "#.#", "#.#"],
	"S": ["###", "#..", "###", "..#", "###"], "T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
}


func _init() -> void:
	_ensure_dirs()
	_make_atlas()
	_make_player_sheet()
	_make_icons()
	print("placeholders written")
	quit()


func _ensure_dirs() -> void:
	for dir in ["res://assets/tilesets/placeholder", "res://assets/sprites/player", "res://assets/sprites/icons/placeholder"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


func _make_atlas() -> void:
	var img := Image.create(TILE_W * 3, TILE_H, false, Image.FORMAT_RGBA8)
	_draw_diamond(img, Vector2i(0, 0), FLOOR_COLOR, EDGE_COLOR)
	_draw_diamond(img, Vector2i(TILE_W, 0), WALL_COLOR, EDGE_COLOR)
	_draw_diamond(img, Vector2i(TILE_W * 2, 0), PIT_COLOR, EDGE_COLOR)
	_save(img, "res://assets/tilesets/placeholder/atlas.png")


## Fills the 64x32 diamond at `origin` (top-left of its cell), with a 1 px edge.
func _draw_diamond(img: Image, origin: Vector2i, fill: Color, edge: Color) -> void:
	var cx := TILE_W * 0.5
	var cy := TILE_H * 0.5
	for y in TILE_H:
		for x in TILE_W:
			var dx := absf(x + 0.5 - cx) / cx
			var dy := absf(y + 0.5 - cy) / cy
			var d := dx + dy
			if d <= 1.0:
				var c := edge if d > 0.9 else fill
				img.set_pixel(origin.x + x, origin.y + y, c)


func _make_player_sheet() -> void:
	var img := Image.create(SPRITE * FACING_DEGREES.size(), SPRITE, false, Image.FORMAT_RGBA8)
	for i in FACING_DEGREES.size():
		var ox := i * SPRITE
		var center := Vector2(ox + SPRITE * 0.5, SPRITE * 0.5)
		_draw_body(img, ox, center)
		_draw_arrow(img, center, deg_to_rad(FACING_DEGREES[i]))
	_save(img, "res://assets/sprites/player/placeholder_sheet.png")


## A squat isometric diamond body (32 wide, 16 tall) sitting on a taller
## "post" so Y-sort has something readable. Simple and obviously placeholder.
func _draw_body(img: Image, ox: int, center: Vector2) -> void:
	for y in SPRITE:
		for x in SPRITE:
			var px := ox + x
			var dx := absf(x + 0.5 - SPRITE * 0.5) / 16.0
			var dy := absf(y + 0.5 - (center.y + 8.0)) / 8.0
			if dx + dy <= 1.0:
				img.set_pixel(px, y, BODY_COLOR)
			elif absf(x + 0.5 - SPRITE * 0.5) < 4.0 and y > 4 and y < center.y + 8.0:
				img.set_pixel(px, y, BODY_COLOR.darkened(0.3))


func _draw_arrow(img: Image, center: Vector2, angle: float) -> void:
	var dir := Vector2.RIGHT.rotated(angle)
	var start := center + Vector2(0, 8)
	for step in 20:
		var p := start + dir * step
		_plot(img, p, ARROW_COLOR)
		if step >= 15:
			var side := dir.orthogonal() * (20 - step)
			_plot(img, p + side, ARROW_COLOR)
			_plot(img, p - side, ARROW_COLOR)


func _plot(img: Image, p: Vector2, c: Color) -> void:
	var x := int(p.x)
	var y := int(p.y)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


func _make_icons() -> void:
	for letter in GLYPHS:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(ICON_BG)
		var rows: Array = GLYPHS[letter]
		for row in 5:
			var line: String = rows[row]
			for col in 3:
				if line[col] == "#":
					for sy in 2:
						for sx in 2:
							img.set_pixel(4 + col * 3 + sx, 3 + row * 2 + sy, ICON_FG)
		_save(img, "res://assets/sprites/icons/placeholder/%s.png" % letter)


func _save(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("failed to write %s: %s" % [path, error_string(err)])
