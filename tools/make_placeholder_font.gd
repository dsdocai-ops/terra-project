extends SceneTree
## Generates the placeholder pixel font at assets/fonts/placeholder_pixel_5x7.*:
## a PNG glyph atlas plus a BMFont-format .fnt, which Godot's built-in
## font_data_bmfont importer turns into a FontFile (pixel font, 8 px tall,
## 5 px advance). Owned by art-audio (ui-hud consumes it).
## Sync: none.
##
## Why it exists: SPEC-ui-hud wants a CC0 pixel font "e.g. m5x7 or similar" in
## the theme. Fetching the real m5x7 needs itch.io's JS-gated download, so this
## tool ships a generated glyph set that is entirely our own work (CC0 by
## construction). art-audio's W2-B8 replaces it with sourced OFL fonts and
## credits them in CREDITS.md.
##
## Run from the repo root, then run a headless import and commit both files
## (plus their .import files):
##   godot --headless --path . -s tools/make_placeholder_font.gd
##   godot --headless --path . --import

const ATLAS_PATH := "res://assets/fonts/placeholder_pixel_5x7.png"
const FNT_PATH := "res://assets/fonts/placeholder_pixel_5x7.fnt"
const GLYPH_W := 5
const GLYPH_H := 7
const CELL_W := 6
const CELL_H := 8
const GLYPHS_PER_ROW := 16
const ADVANCE := 5

## 7 rows of 5 bits per glyph, most significant bit first (public-domain style
## 5x7 uppercase patterns; lowercase letters reuse the uppercase patterns, a
## common placeholder-font trick).
const GLYPHS: Dictionary = {
	0x20: ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	0x2D: ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	0x2E: ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
	0x2F: ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
	0x30: ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	0x31: ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	0x32: ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
	0x33: ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
	0x34: ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	0x35: ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	0x36: ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	0x37: ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	0x38: ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	0x39: ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	0x3A: ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
	0x3F: ["01110", "10001", "00001", "00110", "00100", "00000", "00100"],
	0x5F: ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
	0x41: ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	0x42: ["11110", "10001", "11110", "10001", "10001", "10001", "11110"],
	0x43: ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	0x44: ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	0x45: ["11111", "10000", "11110", "10000", "10000", "10000", "11111"],
	0x46: ["11111", "10000", "11110", "10000", "10000", "10000", "10000"],
	0x47: ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	0x48: ["10001", "10001", "11111", "10001", "10001", "10001", "10001"],
	0x49: ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
	0x4A: ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
	0x4B: ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	0x4C: ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	0x4D: ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	0x4E: ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	0x4F: ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	0x50: ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	0x51: ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	0x52: ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	0x53: ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	0x54: ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	0x55: ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	0x56: ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	0x57: ["10001", "10001", "10101", "10101", "10101", "11011", "10001"],
	0x58: ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	0x59: ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	0x5A: ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
}


func _init() -> void:
	var rows: int = ceili(GLYPHS.size() / float(GLYPHS_PER_ROW))
	var atlas := Image.create(GLYPHS_PER_ROW * CELL_W, rows * CELL_H, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))

	var index := 0
	var fnt := _fnt_header(GLYPHS.size())
	for char_code: int in GLYPHS.keys():
		var cell_x: int = index % GLYPHS_PER_ROW
		var cell_y: int = index / GLYPHS_PER_ROW
		_paint_glyph(atlas, char_code, cell_x * CELL_W, cell_y * CELL_H)
		fnt += _fnt_char(char_code, cell_x * CELL_W, cell_y * CELL_H)
		index += 1

	var png_err := atlas.save_png(ATLAS_PATH)
	if png_err != OK:
		push_error("could not save %s: %s" % [ATLAS_PATH, error_string(png_err)])
		quit(1)
		return
	var file := FileAccess.open(FNT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("could not open %s" % FNT_PATH)
		quit(1)
		return
	file.store_string(fnt)
	file.close()
	print("placeholder pixel font written to %s + %s (%d glyphs) — run --import next" % [ATLAS_PATH, FNT_PATH, GLYPHS.size()])
	quit()


func _fnt_header(char_count: int) -> String:
	var atlas_w := GLYPHS_PER_ROW * CELL_W
	var atlas_h := ceili(GLYPHS.size() / float(GLYPHS_PER_ROW)) * CELL_H
	var lines := PackedStringArray([
		"info face=\"placeholder_pixel_5x7\" size=8 bold=0 italic=0 charset=\"\" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1",
		"common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0" % [CELL_H, GLYPH_H + 1, atlas_w, atlas_h],
		"page id=0 file=\"placeholder_pixel_5x7.png\"",
		"chars count=%d" % char_count,
	])
	return "\n".join(lines) + "\n"


func _fnt_char(char_code: int, x: int, y: int) -> String:
	return "char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=1 xadvance=%d page=0 chnl=15\n" % [char_code, x, y, GLYPH_W, GLYPH_H, ADVANCE]


func _paint_glyph(atlas: Image, char_code: int, origin_x: int, origin_y: int) -> void:
	var rows_pattern: Array = GLYPHS[char_code]
	for row: int in rows_pattern.size():
		var bits: String = rows_pattern[row]
		for col: int in bits.length():
			if bits[col] == "1":
				atlas.set_pixel(origin_x + col, origin_y + row, Color.WHITE)