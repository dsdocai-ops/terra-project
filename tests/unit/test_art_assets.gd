extends GutTest
## The generated pixel art is wired in: every biome has a loadable tileset with the
## shared tile ids, every Week 4 relic carries its icon, every pickup kind has a
## sprite, and every enemy has a SpriteFrames with all sixteen animations.
## Owned by art-audio. The drawing itself is reviewed from the capture screenshots.

const BIOMES: Array[String] = ["collapsed_mines", "fungal_caverns", "crystal_hollows", "drowned_city", "ember_forge", "the_heart"]
const ENEMY_DIR := "res://assets/sprites/enemies/"


func _tileset_path(biome: String) -> String:
	return "res://assets/tilesets/placeholder_iso.tres" if biome == "collapsed_mines" else "res://assets/tilesets/%s_iso.tres" % biome


func test_every_biome_has_a_tileset_with_the_shared_ids() -> void:
	for biome: String in BIOMES:
		var tile_set := load(_tileset_path(biome)) as TileSet
		assert_not_null(tile_set, "%s tileset loads" % biome)
		var source := tile_set.get_source(Tiles.SOURCE) as TileSetAtlasSource
		assert_eq(source.texture_region_size, Vector2i(64, 64), "%s cells" % biome)
		for coords: Vector2i in [Tiles.FLOOR, Tiles.WALL, Tiles.PIT]:
			assert_true(source.has_tile(coords), "%s has tile %s" % [biome, coords])
		for coords: Vector2i in Tiles.FLOOR_VARIANTS:
			assert_true(source.has_tile(coords), "%s has floor variant %s" % [biome, coords])
			assert_true(source.get_tile_data(coords, 0).get_custom_data(Tiles.WALKABLE), "%s variant %s walkable" % [biome, coords])
		assert_false(source.get_tile_data(Tiles.WALL, 0).get_custom_data(Tiles.WALKABLE))
		assert_eq(source.get_tile_data(Tiles.WALL, 0).get_collision_polygons_count(0), 1, "%s wall collides" % biome)


func test_every_relic_has_an_icon() -> void:
	for id: StringName in RelicData.WEEK_4_IDS:
		var data := RelicFlow.data_for(id)
		assert_not_null(data, "%s data" % id)
		assert_not_null(data.icon, "%s icon" % id)
		assert_eq(data.icon.get_size(), Vector2(16, 16), "%s icon is 16x16" % id)


func test_every_pickup_kind_has_a_sprite() -> void:
	for kind: StringName in Pickup.KINDS:
		assert_true(ResourceLoader.exists(Pickup.art_path_for(kind)), "%s sprite" % kind)


func test_a_pickup_shows_the_sprite_of_its_kind() -> void:
	var pickup := (load("res://scenes/pickups/pickup.tscn") as PackedScene).instantiate() as Pickup
	pickup.kind = Pickup.KIND_ECHO
	add_child_autofree(pickup)
	var body := pickup.get_node("Body") as Sprite2D
	assert_eq(body.texture.resource_path, Pickup.art_path_for(Pickup.KIND_ECHO))


func test_every_enemy_has_frames_for_all_facings() -> void:
	var ids: Array[String] = []
	for file: String in DirAccess.get_files_at(ENEMY_DIR):
		if file.ends_with("_frames.tres"):
			ids.append(file)
	assert_eq(ids.size(), 27, "the 27 base enemies of the design doc")
	for file: String in ids:
		var frames := load(ENEMY_DIR + file) as SpriteFrames
		assert_not_null(frames, file)
		for suffix: StringName in Facing.SUFFIXES:
			assert_true(frames.has_animation("idle_" + suffix), "%s idle_%s" % [file, suffix])
			assert_true(frames.has_animation("walk_" + suffix), "%s walk_%s" % [file, suffix])
		assert_eq(frames.get_frame_count(&"walk_s"), 6)
		assert_eq(frames.get_frame_count(&"idle_s"), 2)
