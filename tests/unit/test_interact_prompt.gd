extends GutTest


func test_prompt_text_names_the_key_and_the_action() -> void:
	assert_eq(InteractPrompt.prompt_for("F", "Open"), "[F] Open")


func test_key_name_reads_the_interact_binding() -> void:
	assert_eq(InteractPrompt.key_name(), "F")


class FakeInteractable:
	extends Area2D
	var prompt_text: String = "Open"
	var used_by: Node = null

	func interact(player: Node) -> void:
		used_by = player


func _spawn(at: Vector2, text: String = "Open", layer: int = 32) -> FakeInteractable:
	var item := FakeInteractable.new()
	item.prompt_text = text
	item.collision_layer = layer
	item.collision_mask = 0
	item.position = at
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	item.add_child(shape)
	add_child_autofree(item)
	return item


func test_nearest_finds_a_usable_interactable_in_reach_and_prefers_the_closest() -> void:
	var near := _spawn(Vector2(10, 0))
	_spawn(Vector2(40, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(InteractPrompt.nearest(self_node(), Vector2.ZERO), near)


func test_nearest_ignores_far_ones_empty_prompts_and_other_layers() -> void:
	_spawn(Vector2(300, 0))
	_spawn(Vector2(5, 0), "")
	_spawn(Vector2(5, 5), "Open", 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_null(InteractPrompt.nearest(self_node(), Vector2.ZERO))


func self_node() -> Node2D:
	var holder := Node2D.new()
	add_child_autofree(holder)
	return holder


func test_room_furniture_spreads_items_instead_of_stacking_them() -> void:
	assert_eq(RoomFurniture.spot(0, 1), Vector2.ZERO)
	var spots: Array[Vector2] = []
	for index: int in 3:
		spots.append(RoomFurniture.spot(index, 3))
	assert_ne(spots[0], spots[1])
	assert_ne(spots[1], spots[2])
	assert_ne(spots[0], spots[2])
