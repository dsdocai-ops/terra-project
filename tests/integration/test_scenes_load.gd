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
