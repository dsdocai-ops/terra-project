extends GutTest
## Tests for Iso (scripts/iso.gd). Owned by foundation.
## Screen-space math is checked against a real TileMapLayer so the helper can
## never drift from what Godot paints.

const TILE_SIZE := Vector2i(64, 32)

var _layer: TileMapLayer


func before_each() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = TILE_SIZE
	_layer = TileMapLayer.new()
	_layer.tile_set = tile_set
	add_child_autofree(_layer)


func test_to_screen_matches_tilemaplayer_map_to_local() -> void:
	for x in range(-8, 9):
		for y in range(-8, 9):
			var tile := Vector2i(x, y)
			assert_eq(Iso.to_screen(tile), _layer.map_to_local(tile), "tile %s" % tile)


func test_to_tile_matches_tilemaplayer_local_to_map() -> void:
	for x in range(-8, 9):
		for y in range(-8, 9):
			var tile := Vector2i(x, y)
			var center := _layer.map_to_local(tile)
			assert_eq(Iso.to_tile(center), _layer.local_to_map(center), "center of %s" % tile)


func test_to_tile_matches_local_to_map_for_off_center_points() -> void:
	# Points near diamond edges and corners are where rounding could differ.
	# Points exactly on an edge (|dx|/32 + |dy|/16 == 1) are excluded: Godot
	# resolves those ties by its own half-open convention, and a real position
	# never lands on one.
	var offsets: Array[Vector2] = [
		Vector2(31, 0), Vector2(-31, 0), Vector2(0, 15), Vector2(0, -15),
		Vector2(15.9, 7.9), Vector2(-15.9, -7.9), Vector2(15, -7), Vector2(-15, 7),
		Vector2(29, 1), Vector2(1, 15), Vector2(31.9, 0), Vector2(0, 15.9),
	]
	for x in range(-4, 5):
		for y in range(-4, 5):
			var center := _layer.map_to_local(Vector2i(x, y))
			for offset in offsets:
				var p := center + offset
				assert_eq(Iso.to_tile(p), _layer.local_to_map(p), "point %s" % p)


func test_to_tile_matches_local_to_map_for_random_points() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 5000:
		var p := Vector2(rng.randf_range(-600, 600), rng.randf_range(-400, 400))
		assert_eq(Iso.to_tile(p), _layer.local_to_map(p), "point %s" % p)


func test_round_trip_over_grid_including_negatives() -> void:
	for x in range(-32, 33):
		for y in range(-32, 33):
			var tile := Vector2i(x, y)
			assert_eq(Iso.to_tile(Iso.to_screen(tile)), tile, "round trip %s" % tile)


func test_origin_tile_center() -> void:
	assert_eq(Iso.to_screen(Vector2i.ZERO), Vector2(32, 16))


func test_tile_axes_point_down_right_and_down_left() -> void:
	var origin := Iso.to_screen(Vector2i.ZERO)
	assert_eq(Iso.to_screen(Vector2i(1, 0)) - origin, Vector2(32, 16), "+x axis")
	assert_eq(Iso.to_screen(Vector2i(0, 1)) - origin, Vector2(-32, 16), "+y axis")


func test_input_to_world_cardinals_are_screen_aligned() -> void:
	assert_almost_eq(Iso.input_to_world(Vector2(0, -1)), Vector2(0, -1), Vector2(0.001, 0.001), "W is screen up")
	assert_almost_eq(Iso.input_to_world(Vector2(0, 1)), Vector2(0, 1), Vector2(0.001, 0.001), "S is screen down")
	assert_almost_eq(Iso.input_to_world(Vector2(-1, 0)), Vector2(-1, 0), Vector2(0.001, 0.001), "A is screen left")
	assert_almost_eq(Iso.input_to_world(Vector2(1, 0)), Vector2(1, 0), Vector2(0.001, 0.001), "D is screen right")


func test_input_to_world_diagonals_follow_tile_axes() -> void:
	var plus_x_axis := Vector2(32, 16).normalized()
	var plus_y_axis := Vector2(-32, 16).normalized()
	assert_almost_eq(Iso.input_to_world(Vector2(1, 1)), plus_x_axis, Vector2(0.001, 0.001), "S+D along +x tile axis")
	assert_almost_eq(Iso.input_to_world(Vector2(-1, 1)), plus_y_axis, Vector2(0.001, 0.001), "S+A along +y tile axis")
	assert_almost_eq(Iso.input_to_world(Vector2(-1, -1)), -plus_x_axis, Vector2(0.001, 0.001), "W+A along -x tile axis")
	assert_almost_eq(Iso.input_to_world(Vector2(1, -1)), -plus_y_axis, Vector2(0.001, 0.001), "W+D along -y tile axis")


func test_input_to_world_all_eight_directions_have_equal_length() -> void:
	var dirs: Array[Vector2] = [
		Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1),
	]
	for d in dirs:
		assert_almost_eq(Iso.input_to_world(d).length(), 1.0, 0.001, "length for input %s" % d)


func test_input_to_world_preserves_partial_magnitude() -> void:
	var half := Iso.input_to_world(Vector2(0.5, 0))
	assert_almost_eq(half.length(), 0.5, 0.001, "half-stick keeps half speed")


func test_input_to_world_zero_is_zero() -> void:
	assert_eq(Iso.input_to_world(Vector2.ZERO), Vector2.ZERO)
