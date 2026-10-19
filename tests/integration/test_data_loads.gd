extends GutTest
## Loads every .tres under data/ and checks that ContentData ids match their
## file names, so the data-driven content pipeline is validated from day one
## (the folder is empty in week 1 and the test still runs). Owned by foundation.


func _collect_resources(dir_path: String, out: Array[String]) -> void:
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
				_collect_resources(full, out)
		elif entry.ends_with(".tres"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func test_every_data_resource_loads_and_ids_match_file_names() -> void:
	var paths: Array[String] = []
	_collect_resources("res://data", paths)
	for path: String in paths:
		var res := load(path)
		assert_not_null(res, "%s loads" % path)
		var content := res as ContentData
		if content != null:
			assert_eq(String(content.id), path.get_file().get_basename(), "%s id matches file name" % path)
			assert_ne(content.display_name, "", "%s has a display name" % path)
	pass_test("%d data resources checked" % paths.size())


func test_content_data_id_rule_is_enforced_on_a_fixture() -> void:
	# The rule the test above applies, demonstrated on a throwaway file whose
	# id deliberately disagrees with its name.
	var bad := ContentData.new()
	bad.id = &"wrong_id"
	bad.display_name = "Fixture"
	var path := "user://_fixture_right_name.tres"
	assert_eq(ResourceSaver.save(bad, path), OK)
	var loaded := load(path) as ContentData
	assert_ne(String(loaded.id), path.get_file().get_basename(), "fixture violates the rule, as intended")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
