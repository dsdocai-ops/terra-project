extends GutTest
## Instantiates every .tscn under scenes/ to catch broken references, missing
## scripts, and parse errors early. Owned by foundation.


func _collect_scenes(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	assert_not_null(dir, "open %s" % dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_scenes(full, out)
		elif entry.ends_with(".tscn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func test_every_scene_instantiates() -> void:
	var scenes: Array[String] = []
	_collect_scenes("res://scenes", scenes)
	assert_gt(scenes.size(), 0, "found scenes")
	for path: String in scenes:
		var packed := load(path) as PackedScene
		assert_not_null(packed, "%s loads" % path)
		if packed == null:
			continue
		var node := packed.instantiate()
		assert_not_null(node, "%s instantiates" % path)
		if node != null:
			node.free()


## The enemies-ai base scene (W2-A9 G7b1) at the exact path the spec
## (SPEC-project folder layout, SPEC-enemies-ai) and the spawner's doc name:
## loads, instantiates as the `Enemy` script, and carries the wired base —
## the G7a1 machine states, the components the spawner's swap-in expects and
## the StateSync. The G7a2 pathing and G7a3 separation wiring on the script
## are exercised against this same scene by their unit suites.
func test_enemy_base_scene_loads_wired() -> void:
	var packed := load("res://scenes/enemies/enemy_base.tscn") as PackedScene
	assert_not_null(packed, "enemy_base.tscn loads")
	var node := packed.instantiate() as Node
	assert_not_null(node, "enemy_base.tscn instantiates")
	var enemy := node as Enemy
	assert_not_null(enemy, "enemy_base.tscn instantiates as the Enemy script")
	if enemy == null:
		if node != null:
			node.free()
		return
	assert_not_null(enemy.get_node_or_null("StatBlock"), "StatBlock")
	assert_not_null(enemy.get_node_or_null("Health"), "Health")
	assert_not_null(enemy.get_node_or_null("Hurtbox"), "Hurtbox")
	assert_not_null(enemy.get_node_or_null("Hitbox"), "Hitbox")
	assert_not_null(enemy.get_node_or_null("Telegraph"), "Telegraph")
	assert_not_null(enemy.get_node_or_null("StateSync"), "StateSync")
	var machine: Node = enemy.get_node("StateMachine")
	for state_name: String in ["Idle", "Chase", "Attack", "HitStun", "Stagger"]:
		assert_not_null(machine.get_node_or_null(NodePath(state_name)), "state %s" % state_name)
	enemy.free()


## The W3-A2 Room and Door nodes (G10b1): both load and instantiate. Neither
## has a .tscn — Floor._build_rooms builds every room and door in code — so
## the .tscn collector above cannot see them; the painted-floor wiring (a
## room's own scan closing its door nodes, the shapes opening and closing) is
## proven in tests/integration/test_room_door_scene.gd.
func test_room_and_door_nodes_load() -> void:
	var room_script: GDScript = load("res://scenes/dungeon/room.gd") as GDScript
	assert_not_null(room_script, "room.gd loads")
	var door_script: GDScript = load("res://scenes/dungeon/door.gd") as GDScript
	assert_not_null(door_script, "door.gd loads")
	var room := room_script.new() as Room
	assert_not_null(room, "Room instantiates as the Room script")
	assert_true(room is Node2D, "Room is a Node2D")
	if room != null:
		room.free()
	var door := door_script.new() as Door
	assert_not_null(door, "Door instantiates as the Door script")
	assert_true(door is StaticBody2D, "Door is a StaticBody2D")
	# In the tree the door builds its own collision and placeholder visual, and
	# set_closed moves both (the deferred shape needs one frame to land).
	add_child_autofree(door)
	door.set_closed(true)
	await wait_physics_frames(1)
	var shape: CollisionShape2D = null
	var visual: Polygon2D = null
	for child: Node in door.get_children():
		if child is CollisionShape2D:
			shape = child as CollisionShape2D
		elif child is Polygon2D:
			visual = child as Polygon2D
	assert_not_null(shape, "the door built its collision shape")
	assert_not_null(visual, "the door built its placeholder visual")
	assert_eq(door.get_child_count(), 2, "the door built exactly its shape and its visual")
	if shape != null:
		assert_false(shape.disabled, "a closed door's collision is live")
	if visual != null:
		assert_true(visual.visible, "a closed door shows its placeholder")


## The W3-A2 floor scene (G10b2): loads, instantiates as the `Floor` script, and
## the World builds its live floor from it. A floor 2 layout painted through the
## scene places the START, EXIT and ROPE placeholder markers on their rooms'
## anchors — the START marker on the very anchor the players teleport around.
## The marker placement logic alone (repaints, floor 1's two markers, no rope
## on floor 1) is tests/unit/test_floor_logic.gd's.
func test_floor_scene_loads_and_places_the_start_exit_and_rope_markers() -> void:
	var packed := load("res://scenes/dungeon/floor.tscn") as PackedScene
	assert_not_null(packed, "floor.tscn loads")
	var scene_floor := packed.instantiate() as Floor
	assert_not_null(scene_floor, "floor.tscn instantiates as the Floor script")
	if scene_floor != null:
		scene_floor.free()
	var world := (load("res://scenes/main/world.tscn") as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	var layout: FloorLayout = FloorGenerator.generate(42, 2, BiomeData.for_index(1), [] as Array[int])
	world.build_floor(layout)
	assert_eq(world.floor_node.scene_file_path, "res://scenes/dungeon/floor.tscn",
		"the World's live floor is the scene, not a bare Floor.new()")
	assert_eq(world.floor_node.markers.size(), 3, "all three markers are placed")
	var start: FloorMarker = world.floor_node.marker_of_type(FloorGenerator.RoomType.START)
	assert_not_null(start, "the START marker is placed")
	var exit_marker: FloorMarker = world.floor_node.marker_of_type(FloorGenerator.RoomType.EXIT)
	assert_not_null(exit_marker, "the EXIT marker is placed")
	var rope: FloorMarker = world.floor_node.marker_of_type(FloorGenerator.RoomType.ROPE)
	assert_not_null(rope, "the ROPE marker is placed on floor 2")
	if start != null:
		assert_eq(start.position, world.floor_node.start_position(),
			"the START marker sits where the players spawn")
		assert_eq(start.text(), "START", "the START marker's placeholder text")
		assert_eq(start.get_child_count(), 2, "the START marker built its diamond and its label")


## The W2-A10 placeholder sprites: each enemy's SpriteFrames under assets/
## load, and every animation's frame texture loads with them (G8a adds the
## Hollow Miner; G8b appends the other two). The drawing itself — the enemy
## shows its frames instead of the placeholder polygon — is the
## test_v2_sprites suite.
func test_w2_a10_enemy_placeholder_sprites_load() -> void:
	var paths: Array[String] = [
		"res://assets/sprites/enemies/hollow_miner_frames.tres",
		"res://assets/sprites/enemies/rock_tick_frames.tres",
		"res://assets/sprites/enemies/lantern_wisp_frames.tres",
	]
	for path: String in paths:
		var frames: SpriteFrames = load(path) as SpriteFrames
		assert_not_null(frames, "%s loads as SpriteFrames" % path)
		if frames == null:
			continue
		var animations := frames.get_animation_names()
		assert_gt(animations.size(), 0, "%s has animations" % path)
		for animation: String in animations:
			var texture: Texture2D = frames.get_frame_texture(StringName(animation), 0)
			assert_not_null(texture, "%s / %s frame 0 loads" % [path, animation])
