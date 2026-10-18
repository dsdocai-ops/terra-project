extends GutTest
## Tests for scenes/main/world.tscn. Owned by foundation.

const WORLD_SCENE := "res://scenes/main/world.tscn"

var _world: World


func before_each() -> void:
	var packed := load(WORLD_SCENE) as PackedScene
	assert_not_null(packed, "world scene loads")
	if packed == null:
		return
	_world = packed.instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)


func test_node_layout_matches_spec() -> void:
	assert_not_null(_world.get_node_or_null("Floor"), "Floor")
	assert_not_null(_world.get_node_or_null("Walls"), "Walls")
	assert_not_null(_world.get_node_or_null("Entities"), "Entities")
	assert_not_null(_world.get_node_or_null("Players"), "Players")
	assert_not_null(_world.get_node_or_null("Camera"), "Camera")
	assert_not_null(_world.get_node_or_null("FX"), "FX")


func test_typed_references_point_at_children() -> void:
	assert_eq(_world.floor_layer, _world.get_node("Floor"))
	assert_eq(_world.walls_layer, _world.get_node("Walls"))
	assert_eq(_world.entities, _world.get_node("Entities"))
	assert_eq(_world.players, _world.get_node("Players"))
	assert_eq(_world.camera, _world.get_node("Camera"))
	assert_eq(_world.fx, _world.get_node("FX"))


func test_y_sort_on_world_walls_and_entities_but_not_fx() -> void:
	assert_true(_world.y_sort_enabled, "World")
	assert_true(_world.walls_layer.y_sort_enabled, "Walls")
	assert_true(_world.entities.y_sort_enabled, "Entities")
	assert_false(_world.fx.y_sort_enabled, "FX")


func test_layers_use_the_shared_tileset() -> void:
	assert_eq(_world.floor_layer.tile_set.resource_path, "res://assets/tilesets/placeholder_iso.tres")
	assert_eq(_world.walls_layer.tile_set, _world.floor_layer.tile_set)
	assert_true(_world.walls_layer.collision_enabled, "walls collide")


func test_paint_test_floor_fills_interior_and_rings_walls() -> void:
	_world.paint_test_floor(20)
	assert_eq(_world.floor_layer.get_used_cells().size(), 20 * 20, "floor cells")
	assert_eq(_world.walls_layer.get_used_cells().size(), 22 * 4 - 4, "wall ring cells")
	assert_true(_world.is_walkable(Vector2i(5, 5)), "interior walkable")
	assert_false(_world.is_walkable(Vector2i(-1, 5)), "wall not walkable")
	assert_false(_world.is_walkable(Vector2i(50, 50)), "void not walkable")


func test_paint_test_floor_is_idempotent() -> void:
	_world.paint_test_floor(10)
	_world.paint_test_floor(10)
	assert_eq(_world.floor_layer.get_used_cells().size(), 100)


func test_debug_test_floor_paints_on_ready_by_default() -> void:
	var packed := load(WORLD_SCENE) as PackedScene
	var fresh := packed.instantiate() as World
	add_child_autofree(fresh)
	assert_gt(fresh.floor_layer.get_used_cells().size(), 0, "default scene has a test floor")
