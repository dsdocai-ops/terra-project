extends GutTest
## Tests for the placeholder isometric TileSet and the Tiles id constants.
## Owned by foundation.

const TILESET_PATH := "res://assets/tilesets/placeholder_iso.tres"

var _tile_set: TileSet
var _source: TileSetAtlasSource


func before_each() -> void:
	_tile_set = load(TILESET_PATH) as TileSet
	assert_not_null(_tile_set, "tileset loads")
	if _tile_set == null:
		return
	_source = _tile_set.get_source(Tiles.SOURCE) as TileSetAtlasSource


func test_shape_layout_and_size_are_isometric_64x32() -> void:
	assert_eq(_tile_set.tile_shape, TileSet.TILE_SHAPE_ISOMETRIC)
	assert_eq(_tile_set.tile_layout, TileSet.TILE_LAYOUT_DIAMOND_DOWN)
	assert_eq(_tile_set.tile_size, Vector2i(64, 32))


func test_has_floor_wall_and_pit_tiles() -> void:
	assert_not_null(_source, "atlas source 0 exists")
	assert_true(_source.has_tile(Tiles.FLOOR), "floor tile")
	assert_true(_source.has_tile(Tiles.WALL), "wall tile")
	assert_true(_source.has_tile(Tiles.PIT), "pit tile")
	assert_eq(_source.get_tiles_count(), 3)


func test_walkable_custom_data_layer() -> void:
	assert_eq(_tile_set.get_custom_data_layers_count(), 1)
	assert_eq(_tile_set.get_custom_data_layer_name(0), Tiles.WALKABLE)
	assert_eq(_tile_set.get_custom_data_layer_type(0), TYPE_BOOL)
	assert_true(_source.get_tile_data(Tiles.FLOOR, 0).get_custom_data(Tiles.WALKABLE), "floor walkable")
	assert_false(_source.get_tile_data(Tiles.WALL, 0).get_custom_data(Tiles.WALKABLE), "wall not walkable")
	assert_false(_source.get_tile_data(Tiles.PIT, 0).get_custom_data(Tiles.WALKABLE), "pit not walkable")


func test_wall_has_collision_and_floor_does_not() -> void:
	assert_eq(_tile_set.get_physics_layers_count(), 1)
	var wall := _source.get_tile_data(Tiles.WALL, 0)
	var floor_tile := _source.get_tile_data(Tiles.FLOOR, 0)
	assert_gt(wall.get_collision_polygons_count(0), 0, "wall collides")
	assert_eq(floor_tile.get_collision_polygons_count(0), 0, "floor does not collide")
	assert_eq(wall.get_collision_polygon_points(0, 0).size(), 4, "wall collision is the tile diamond")


func test_atlas_texture_is_three_tiles_wide() -> void:
	var tex := _source.texture
	assert_not_null(tex, "atlas texture")
	assert_eq(tex.get_size(), Vector2(192, 32))
