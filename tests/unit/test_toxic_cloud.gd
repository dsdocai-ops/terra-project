extends GutTest
## Tests for Toxic Cloud's growth (SPEC-abilities section 8, Poison): the cloud grows
## over the cast's life, and a cast with no life does not grow it, so the growth
## never divides by a zero life. Owned by abilities. Sync: host only. The cast is
## driven by hand and physics processing is left on, as in the cast's own scene.

const DATA_PATH: String = "res://data/abilities/toxic_cloud.tres"

var _data: AbilityData


func before_each() -> void:
	_data = load(DATA_PATH) as AbilityData


func _radius_of(zone: Zone) -> float:
	var shape := zone.get_node("Shape") as CollisionShape2D
	return (shape.shape as CircleShape2D).radius


func test_a_cast_with_no_life_keeps_its_cloud_at_the_start_size() -> void:
	var cast := _data.cast_scene.instantiate() as ToxicCloudCast
	cast.setup(null, _data, 1, Vector2.ZERO, Vector2.RIGHT)
	cast.life_seconds = 0.0
	add_child_autofree(cast)
	var cloud: Zone = null
	for child: Node in cast.get_children():
		if child is Zone:
			cloud = child as Zone
	assert_not_null(cloud, "the cast spawns its cloud")
	if cloud == null:
		return
	var start: float = _radius_of(cloud)
	cast.advance(0.1)
	assert_almost_eq(_radius_of(cloud), start, 0.001, "with no life the cloud does not grow, and no division by the zero life runs")
	assert_almost_eq(start, ToxicCloudCast.RADIUS * ToxicCloudCast.START_SHARE, 0.001, "the cloud starts at its start share")


func test_a_cast_that_never_entered_the_tree_advances_with_no_cloud() -> void:
	var cast := _data.cast_scene.instantiate() as ToxicCloudCast
	cast.setup(null, _data, 1, Vector2.ZERO, Vector2.RIGHT)
	cast.advance(0.1)
	var zones: int = 0
	for child: Node in cast.get_children():
		if child is Zone:
			zones += 1
	assert_eq(zones, 0, "a cast that never ran _perform spawns no cloud, and its advance does not fail")
	cast.free()


func test_a_cloud_freed_before_the_cast_does_not_fail_the_advance() -> void:
	var cast := _data.cast_scene.instantiate() as ToxicCloudCast
	cast.setup(null, _data, 1, Vector2.ZERO, Vector2.RIGHT)
	add_child_autofree(cast)
	for child: Node in cast.get_children():
		if child is Zone:
			child.free()
	cast.advance(0.1)
	assert_true(is_instance_valid(cast), "the cast survives an advance after its cloud is gone")
