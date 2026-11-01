extends GutTest
## Unit checks for ClassData (SPEC-classes-characters "Data"): the exported
## fields exist with the types the spec gives, the defaults mean "start" and
## "nothing attached", and the typed arrays hold their element type. Owned by
## classes-characters. Sync: none (data).

## The fields the spec names, with the type each must have. `element` is the
## typed-array element: a class name, or "21:" for StringName (Godot's hint
## code). `class` is the Resource or Script class of an object field.
const FIELDS: Array[Dictionary] = [
	{"name": &"role", "type": TYPE_STRING},
	{"name": &"affinity_weapon_ids", "type": TYPE_ARRAY, "element": "21:"},
	{"name": &"affinity_effect", "type": TYPE_OBJECT, "class": "GDScript"},
	{"name": &"passive_effect", "type": TYPE_OBJECT, "class": "GDScript"},
	{"name": &"class_skill", "type": TYPE_OBJECT, "class": "PackedScene"},
	{"name": &"class_skill_alt", "type": TYPE_OBJECT, "class": "PackedScene"},
	{"name": &"ascensions", "type": TYPE_ARRAY, "element": "AscensionData"},
	{"name": &"ultimate_twist", "type": TYPE_OBJECT, "class": "GDScript"},
	{"name": &"base_stats", "type": TYPE_DICTIONARY},
	{"name": &"unlock_flag", "type": TYPE_STRING_NAME},
	{"name": &"free_weapon_id", "type": TYPE_STRING_NAME},
	{"name": &"class_resource_kind", "type": TYPE_STRING_NAME},
]


func _property_of(obj: Object, field: StringName) -> Dictionary:
	for prop: Dictionary in obj.get_property_list():
		if prop["name"] == field:
			return prop
	return {}


func test_class_data_is_a_content_resource() -> void:
	var data := ClassData.new()
	assert_true(data is ContentData, "ClassData extends ContentData")
	assert_true(data is Resource, "ClassData is a Resource")


func test_each_spec_field_is_exported_with_its_type() -> void:
	var data := ClassData.new()
	for field: Dictionary in FIELDS:
		var name: StringName = field["name"]
		var prop := _property_of(data, name)
		assert_false(prop.is_empty(), "ClassData exports %s" % name)
		if prop.is_empty():
			continue
		assert_eq(prop["type"], field["type"], "%s has the spec's type" % name)
		if field.has("element"):
			assert_true(String(prop["hint_string"]).contains(field["element"]), "%s holds %s" % [name, field["element"]])
		if field.has("class"):
			assert_eq(String(prop["class_name"]), field["class"], "%s is a %s" % [name, field["class"]])


## An empty unlock flag means the class is open at start (spec: "empty = start").
func test_defaults_mean_open_at_start_with_nothing_attached() -> void:
	var data := ClassData.new()
	assert_eq(data.unlock_flag, &"", "unlock_flag is empty, so the class is open at start")
	assert_eq(data.free_weapon_id, &"", "no free weapon by default")
	assert_eq(data.class_resource_kind, &"", "no class resource by default")
	assert_true(data.affinity_weapon_ids.is_empty(), "no affinity weapons by default")
	assert_true(data.ascensions.is_empty(), "no ascensions by default")
	assert_true(data.base_stats.is_empty(), "no base stats by default")
	assert_null(data.class_skill, "no class skill scene by default")
	assert_null(data.class_skill_alt, "no alternate class skill by default")
	assert_null(data.passive_effect, "no passive by default")
	assert_null(data.affinity_effect, "no affinity effect by default")
	assert_null(data.ultimate_twist, "no ultimate twist by default")


func test_values_assigned_to_each_field_read_back() -> void:
	var data := ClassData.new()
	var ascension := AscensionData.new()
	data.role = "melee bruiser"
	data.affinity_weapon_ids = [&"blades", &"heavy"]
	data.ascensions.append(ascension)
	data.base_stats = {StatBlock.Stat.MAX_HP: 120.0}
	data.unlock_flag = &"rescue.sly_nettie"
	data.free_weapon_id = &"pickaxe"
	data.class_resource_kind = &"scrap"
	assert_eq(data.role, "melee bruiser", "role reads back")
	assert_eq(data.affinity_weapon_ids, [&"blades", &"heavy"], "affinity ids read back")
	assert_eq(data.ascensions.size(), 1, "one ascension is held")
	assert_true(data.ascensions[0] == ascension, "the held ascension is the one appended")
	assert_eq(data.base_stats[StatBlock.Stat.MAX_HP], 120.0, "a base stat reads back by its Stat key")
	assert_eq(data.unlock_flag, &"rescue.sly_nettie", "unlock_flag reads back")
	assert_eq(data.free_weapon_id, &"pickaxe", "free_weapon_id reads back")
	assert_eq(data.class_resource_kind, &"scrap", "class_resource_kind reads back")
