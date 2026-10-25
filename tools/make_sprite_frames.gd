extends SceneTree
## Builds a SpriteFrames .tres from a generated sheet (art-audio). Owned by
## art-audio. Sync: none.
##
## Sheet layout (tools/art/gen_character.py, gen_enemies.py, gen_sprites_v2.py):
## one row per facing in Facing.SUFFIXES order, columns 0..1 idle, 2..7 move.
## The frame size is read from the sheet (width / 8 columns, height / 8 rows),
## so v1 48x48 sheets and v2 64x96 / 64x64 sheets both work.
## Run after the generators and a `--import`:
##   godot --headless --path . -s tools/make_sprite_frames.gd -- <sheet.png> <out.tres>
## Both are res:// paths. Re-running keeps the output's UID.

const IDLE_FRAMES := 2
const MOVE_FRAMES := 6
const IDLE_SPEED := 3.0
const MOVE_SPEED := 10.0
## Enemies move with "walk" like the player so one animation name serves both.
const MOVE_ANIMATION := "walk_"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <sheet.png> <out.tres>")
		quit(1)
		return
	var sheet := load(args[0]) as Texture2D
	if sheet == null:
		push_error("sheet not imported yet: %s (run --import first)" % args[0])
		quit(1)
		return
	var frame_size := Vector2(
		float(sheet.get_width()) / float(IDLE_FRAMES + MOVE_FRAMES),
		float(sheet.get_height()) / float(Facing.count()))
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for row: int in Facing.count():
		var suffix: String = String(Facing.suffix(row))
		_add_animation(frames, sheet, frame_size, row, "idle_" + suffix, 0, IDLE_FRAMES, IDLE_SPEED)
		_add_animation(frames, sheet, frame_size, row, MOVE_ANIMATION + suffix, IDLE_FRAMES, MOVE_FRAMES, MOVE_SPEED)
	var err: int = ResourceSaver.save(frames, args[1])
	if err != OK:
		push_error("failed to save %s: %s" % [args[1], error_string(err)])
		quit(1)
		return
	var uid: int = ResourceLoader.get_resource_uid(args[1])
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	ResourceSaver.set_uid(args[1], uid)
	print("frames written to %s (%s)" % [args[1], ResourceUID.id_to_text(uid)])
	quit()


func _add_animation(frames: SpriteFrames, sheet: Texture2D, frame_size: Vector2, row: int, anim: String, first_column: int, count: int, speed: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, speed)
	frames.set_animation_loop(anim, true)
	for column: int in range(first_column, first_column + count):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(column * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y)
		frames.add_frame(anim, atlas)
