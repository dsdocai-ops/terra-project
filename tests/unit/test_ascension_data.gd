extends GutTest
## Unit checks for AscensionData (SPEC-classes-characters "Data"): the exported
## fields exist with the types the spec gives, and the Week 5 brief's rule holds:
## AscensionData is a resource only, so the data folder holds no entries yet.
## Owned by classes-characters. Sync: none (data).

const ASCENSION_DIR: String = "res://data/ascensions"

## The fields the spec names, with the type each must have.
const FIELDS: Array[Dictionary] = [
	{"name": &"class_id", "type": TYPE_STRING_NAME},
	{"name": &"tier1_effect", "type": TYPE_OBJECT, "class": "GDScript"},
	{"name": &"tier2_effect", "type": TYPE_OBJECT, "class": "GDScript"},
	{"name": &"tier2_name", "type": TYPE_STRING},
	{"name": &"description_t1", "type": TYPE_STRING},
	{"name": &"description_t2", "type": TYPE_STRING},
	{"name": &"replaces_class_skill", "type": TYPE_OBJECT, "class": "PackedScene"},
]


func _property_of(obj: Object, field: StringName) -> Dictionary:
	for prop: Dictionary in obj.get_property_list():
		if prop["name"] == field:
			return prop
	return {}


func test_ascension_data_is_a_content_resource() -> void:
	var data := AscensionData.new()
	assert_true(data is ContentData, "AscensionData extends ContentData")
	assert_true(data is Resource, "AscensionData is a Resource")


func test_each_spec_field_is_exported_with_its_type() -> void:
	var data := AscensionData.new()
	for field: Dictionary in FIELDS:
		var name: StringName = field["name"]
		var prop := _property_of(data, name)
		assert_false(prop.is_empty(), "AscensionData exports %s" % name)
		if prop.is_empty():
			continue
		assert_eq(prop["type"], field["type"], "%s has the spec's type" % name)
		if field.has("class"):
			assert_eq(String(prop["class_name"]), field["class"], "%s is a %s" % [name, field["class"]])


func test_replaces_class_skill_is_optional() -> void:
	var data := AscensionData.new()
	assert_null(data.replaces_class_skill, "an ascension replaces no class skill unless it sets one")
	assert_null(data.tier2_effect, "no tier 2 effect unless set")


## Week 5 scope (brief, Out of scope): AscensionData is defined as a resource
## only, with no entries. This check holds until the Week 7 Tier 1 content lands.
func test_the_ascension_folder_holds_no_entries_this_week() -> void:
	var dir := DirAccess.open(ASCENSION_DIR)
	assert_not_null(dir, "the ascensions folder opens")
	if dir == null:
		return
	var entries: PackedStringArray = []
	for file_name: String in dir.get_files():
		if file_name.ends_with(".tres"):
			entries.append(file_name)
	assert_true(entries.is_empty(), "no AscensionData entries are authored in Week 5 (found: %s)" % str(entries))
