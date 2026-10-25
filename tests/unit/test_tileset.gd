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
	assert_eq(_source.get_tiles_count(), 2 + Tiles.FLOOR_VARIANTS.size())


func test_every_floor_variant_is_walkable_without_collision() -> void:
	for coords: Vector2i in Tiles.FLOOR_VARIANTS:
		assert_true(_source.has_tile(coords), "floor variant %s" % coords)
		var data := _source.get_tile_data(coords, 0)
		assert_true(data.get_custom_data(Tiles.WALKABLE), "variant %s walkable" % coords)
		assert_eq(data.get_collision_polygons_count(0), 0, "variant %s does not collide" % coords)


func test_floor_at_is_deterministic_and_uses_every_variant() -> void:
	var seen: Dictionary[Vector2i, int] = {}
	for x in range(-10, 10):
		for y in range(-10, 10):
			var cell := Vector2i(x, y)
			var variant := Tiles.floor_at(cell)
			assert_eq(Tiles.floor_at(cell), variant, "same cell, same variant")
			seen[variant] = seen.get(variant, 0) + 1
	assert_eq(seen.size(), Tiles.FLOOR_VARIANTS.size(), "a 20x20 room shows every variant")
	for variant: Vector2i in seen:
		assert_gt(seen[variant], 50, "variant %s is not starved" % variant)


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


func test_atlas_texture_is_three_by_two_64x96_cells() -> void:
	var tex := _source.texture
	assert_not_null(tex, "atlas texture")
	assert_eq(tex.get_size(), Vector2(192, 192))
	assert_eq(_source.texture_region_size, Vector2i(64, 96), "v2 64x96 cells (SPEC-art-audio D2) leave room for a 32 px wall above its diamond")
