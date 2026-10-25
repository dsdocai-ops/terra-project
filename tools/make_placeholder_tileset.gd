extends SceneTree
## Builds assets/tilesets/placeholder_iso.tres (the path scenes load) from the Collapsed Mines atlas that tools/art/gen_tiles.py draws: 64x64 cells, a 64x32 ground diamond centred in each, so a wall can rise above it.
## Owned by foundation. Sync: none.
##
## Run after tools/make_placeholders.gd and a `--import` (the atlas PNG must be
## imported before it can be loaded as a Texture2D):
##   godot --headless --path . -s tools/make_placeholder_tileset.gd
##
## Ids come from scripts/tiles.gd so every biome tileset stays compatible.

const DEFAULT_BIOME := "collapsed_mines"

## Which biome to build comes from the first user arg (`-- fungal_caverns`). The
## Collapsed Mines keep the path scenes already load; every other biome writes
## assets/tilesets/<biome>_iso.tres.
var _out_path: String = ""

## Collision diamond in tile-local space (origin at tile center).
const DIAMOND: Array[Vector2] = [Vector2(0, -16), Vector2(32, 0), Vector2(0, 16), Vector2(-32, 0)]
const TILE_COORDS: Array[Vector2i] = [Tiles.WALL, Tiles.PIT]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var biome: String = args[0] if args.size() > 0 else DEFAULT_BIOME
	_out_path = "res://assets/tilesets/placeholder_iso.tres" if biome == DEFAULT_BIOME else "res://assets/tilesets/%s_iso.tres" % biome
	var texture := load("res://assets/tilesets/%s/atlas.png" % biome) as Texture2D
	if texture == null:
		push_error("atlas not imported yet: run tools/art/gen_tiles.py then --import")
		quit(1)
		return

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = Vector2i(64, 32)
	tile_set.add_physics_layer()
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, Tiles.WALKABLE)
	tile_set.set_custom_data_layer_type(0, TYPE_BOOL)

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(64, 64)
	tile_set.add_source(source, Tiles.SOURCE)

	for coords: Vector2i in Tiles.FLOOR_VARIANTS:
		source.create_tile(coords)
		source.get_tile_data(coords, 0).set_custom_data(Tiles.WALKABLE, true)
	for coords: Vector2i in TILE_COORDS:
		source.create_tile(coords)

	source.get_tile_data(Tiles.PIT, 0).set_custom_data(Tiles.WALKABLE, false)

	var wall := source.get_tile_data(Tiles.WALL, 0)
	wall.set_custom_data(Tiles.WALKABLE, false)
	wall.add_collision_polygon(0)
	wall.set_collision_polygon_points(0, 0, PackedVector2Array(DIAMOND))

	var err := ResourceSaver.save(tile_set, _out_path)
	if err != OK:
		push_error("failed to save tileset: %s" % error_string(err))
		quit(1)
		return
	# Keep the existing UID across regenerations so scenes referencing the
	# tileset by UID stay valid; only mint one the first time.
	var uid := ResourceLoader.get_resource_uid(_out_path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	ResourceSaver.set_uid(_out_path, uid)
	print("tileset written to %s (%s)" % [_out_path, ResourceUID.id_to_text(uid)])
	quit()
