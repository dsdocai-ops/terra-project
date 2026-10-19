extends SceneTree
## Builds assets/tilesets/placeholder_iso.tres from the placeholder atlas.
## Owned by foundation. Sync: none.
##
## Run after tools/make_placeholders.gd and a `--import` (the atlas PNG must be
## imported before it can be loaded as a Texture2D):
##   godot --headless --path . -s tools/make_placeholder_tileset.gd
##
## Ids come from scripts/tiles.gd so every biome tileset stays compatible.

const ATLAS_PATH := "res://assets/tilesets/placeholder/atlas.png"
const OUT_PATH := "res://assets/tilesets/placeholder_iso.tres"

## Collision diamond in tile-local space (origin at tile center).
const DIAMOND: Array[Vector2] = [Vector2(0, -16), Vector2(32, 0), Vector2(0, 16), Vector2(-32, 0)]
const TILE_COORDS: Array[Vector2i] = [Tiles.FLOOR, Tiles.WALL, Tiles.PIT]


func _init() -> void:
	var texture := load(ATLAS_PATH) as Texture2D
	if texture == null:
		push_error("atlas not imported yet: run make_placeholders.gd then --import")
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
	source.texture_region_size = Vector2i(64, 32)
	tile_set.add_source(source, Tiles.SOURCE)

	for coords: Vector2i in TILE_COORDS:
		source.create_tile(coords)

	source.get_tile_data(Tiles.FLOOR, 0).set_custom_data(Tiles.WALKABLE, true)
	source.get_tile_data(Tiles.PIT, 0).set_custom_data(Tiles.WALKABLE, false)

	var wall := source.get_tile_data(Tiles.WALL, 0)
	wall.set_custom_data(Tiles.WALKABLE, false)
	wall.add_collision_polygon(0)
	wall.set_collision_polygon_points(0, 0, PackedVector2Array(DIAMOND))

	var err := ResourceSaver.save(tile_set, OUT_PATH)
	if err != OK:
		push_error("failed to save tileset: %s" % error_string(err))
		quit(1)
		return
	# Keep the existing UID across regenerations so scenes referencing the
	# tileset by UID stay valid; only mint one the first time.
	var uid := ResourceLoader.get_resource_uid(OUT_PATH)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	ResourceSaver.set_uid(OUT_PATH, uid)
	print("tileset written to %s (%s)" % [OUT_PATH, ResourceUID.id_to_text(uid)])
	quit()
