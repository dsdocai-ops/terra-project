extends GutTest
## Unit checks for CharacterData (SPEC-classes-characters "Data"): the exported
## fields exist with the types the spec gives, the defaults mean "unlocked by
## default" and "nothing attached", and story events are typed StringName ids.
## Owned by classes-characters. Sync: none (data).

## The fields the spec names, with the type each must have. `element` is a class name, or "21:" for StringName (Godot hint code).
const FIELDS: Array[Dictionary] = [
	{"name": &"passive_effect", "type": TYPE_OBJECT, "class": "GDScript"},
	{"name": &"ultimate", "type": TYPE_OBJECT, "class": "AbilityData"},
	{"name": &"unlock_flag", "type": TYPE_STRING_NAME},
	{"name": &"portrait", "type": TYPE_OBJECT, "class": "Texture2D"},
	{"name": &"sprite_frames", "type": TYPE_OBJECT, "class": "SpriteFrames"},
	{"name": &"story_events", "type": TYPE_ARRAY, "element": "21:"},
]


func _property_of(obj: Object, field: StringName) -> Dictionary:
	for prop: Dictionary in obj.get_property_list():
		if prop["name"] == field:
			return prop
	return {}


func test_character_data_is_a_content_resource() -> void:
	var data := CharacterData.new()
	assert_true(data is ContentData, "CharacterData extends ContentData")
	assert_true(data is Resource, "CharacterData is a Resource")


func test_each_spec_field_is_exported_with_its_type() -> void:
	var data := CharacterData.new()
	for field: Dictionary in FIELDS:
		var name: StringName = field["name"]
		var prop := _property_of(data, name)
		assert_false(prop.is_empty(), "CharacterData exports %s" % name)
		if prop.is_empty():
			continue
		assert_eq(prop["type"], field["type"], "%s has the spec's type" % name)
		if field.has("element"):
			assert_true(String(prop["hint_string"]).contains(field["element"]), "%s holds %s" % [name, field["element"]])
		if field.has("class"):
			assert_eq(String(prop["class_name"]), field["class"], "%s is a %s" % [name, field["class"]])


## Wren is unlocked by default, so her unlock flag is empty (spec table: "default").
func test_defaults_mean_unlocked_with_nothing_attached() -> void:
	var data := CharacterData.new()
	assert_eq(data.unlock_flag, &"", "unlock_flag is empty, so the character is unlocked by default")
	assert_true(data.story_events.is_empty(), "no story events by default")
	assert_null(data.passive_effect, "no passive by default")
	assert_null(data.ultimate, "no ultimate by default")
	assert_null(data.portrait, "no portrait by default")
	assert_null(data.sprite_frames, "no sprite frames by default")


func test_story_events_hold_dialogue_ids_and_the_ultimate_is_an_ability() -> void:
	var data := CharacterData.new()
	var ultimate := AbilityData.new()
	data.story_events = [&"wren.intro", &"wren.cave_in", &"wren.finale"]
	data.ultimate = ultimate
	data.unlock_flag = &"story.foreman_defeated"
	assert_eq(data.story_events.size(), 3, "three story events are held")
	assert_eq(data.story_events[1], &"wren.cave_in", "a story event reads back as its StringName id")
	assert_true(data.ultimate == ultimate, "the ultimate is the AbilityData assigned")
	assert_eq(data.unlock_flag, &"story.foreman_defeated", "unlock_flag reads back")
