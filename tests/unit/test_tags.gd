extends GutTest
## `Tags` vocabulary and `ProjectileSpec` — effect-system, W4-B2 (goal G9).
##
## `Tags` is the closed vocabulary every relic, mutation, synergy, class
## passive and skill node is classified by, and `ProjectileSpec` is the
## argument type of `Effect.fire_projectile`. Both are interfaces the other
## Week 4 modules import, so this test pins them against
## `specs/SPEC-effect-system.md` itself rather than against a transcription:
## the tag set is parsed out of the spec's own "Tags and synergies" sentence at
## run time, so an invented tag, a dropped tag or a rename fails here instead
## of becoming a second vocabulary that quietly matches nothing.
##
## Sync: none. A closed vocabulary and a host-built value object.

const SPEC_PATH: String = "res://specs/SPEC-effect-system.md"
const TAGS_SCRIPT_PATH: String = "res://scripts/effects/tags.gd"
const PROJECTILE_SPEC_SCRIPT_PATH: String = "res://scripts/effects/projectile_spec.gd"
const VOCABULARY_MARKER: String = "Tag vocabulary (closed set"
const VOCABULARY_OPEN: String = "enum-like constants): `"
const ALL_CONSTANT: String = "ALL"
## The spec's tag count. Asserted separately from the parsed list so a silently
## truncated spec line cannot make a shrunken vocabulary look correct.
const SPEC_TAG_COUNT: int = 19
const PLACEHOLDER_PROJECTILE_SCENE: String = "res://scenes/network/placeholder_projectile.tscn"
## Every content folder whose `.tres` files declare `ContentData.tags`.
const CONTENT_ROOTS: Array[String] = [
	"res://data/relics",
	"res://data/mutations",
	"res://data/synergies",
	"res://data/ascensions",
]


func _spec_vocabulary() -> Array[StringName]:
	var file: FileAccess = FileAccess.open(SPEC_PATH, FileAccess.READ)
	assert_not_null(file, "the spec must be readable at %s" % SPEC_PATH)
	if file == null:
		return []
	var text: String = file.get_as_text()
	file.close()
	for raw_line: String in text.split("\n"):
		var line: String = raw_line
		if not line.contains(VOCABULARY_MARKER):
			continue
		var start: int = line.find(VOCABULARY_OPEN)
		assert_true(start >= 0, "the vocabulary sentence must carry the constants list")
		if start < 0:
			return []
		start += VOCABULARY_OPEN.length()
		var end: int = line.find("`", start)
		assert_true(end > start, "the constants list must be closed by a backtick")
		if end <= start:
			return []
		var tags: Array[StringName] = []
		for piece: String in line.substr(start, end - start).split(","):
			var tag: String = piece.strip_edges()
			if not tag.is_empty():
				tags.append(StringName(tag))
		return tags
	fail_test("the spec no longer contains its tag vocabulary sentence")
	return []


## A tag is valid when it is in the closed vocabulary; anything else (an
## invented tag, a typo, an empty name) is reported so a caller can name it.
func _invalid_tags(tags: Array[StringName]) -> Array[StringName]:
	var invalid: Array[StringName] = []
	for tag: StringName in tags:
		if not Tags.is_valid(tag):
			invalid.append(tag)
	return invalid


func test_spec_vocabulary_is_nineteen_tags() -> void:
	var spec: Array[StringName] = _spec_vocabulary()
	assert_eq(spec.size(), SPEC_TAG_COUNT, "SPEC-effect-system's closed set is 19 tags")
	assert_eq(spec.size(), _unique(spec).size(), "the spec lists each tag once")


func test_the_vocabulary_lives_where_the_spec_says() -> void:
	assert_true(ResourceLoader.exists(TAGS_SCRIPT_PATH), "scripts/effects/tags.gd")
	assert_true(ResourceLoader.exists(PROJECTILE_SPEC_SCRIPT_PATH), "scripts/effects/projectile_spec.gd")


func test_tags_constants_are_exactly_the_spec_vocabulary() -> void:
	var spec: Array[StringName] = _spec_vocabulary()
	var constants: Dictionary = _tags_script().get_script_constant_map()
	var actual: Array[StringName] = []
	for key: String in constants.keys():
		if key == ALL_CONSTANT:
			continue
		var raw: Variant = constants[key]
		assert_eq(typeof(raw), TYPE_STRING_NAME, "Tags.%s must be a StringName constant" % key)
		actual.append(raw as StringName)
	# neither an invented tag nor a missing one
	for tag: StringName in actual:
		assert_true(spec.has(tag), "Tags.%s (%s) is not in the spec's vocabulary" % [String(tag).to_upper(), tag])
	for tag: StringName in spec:
		assert_true(actual.has(tag), "the spec tag '%s' has no Tags constant" % tag)
	assert_eq(actual.size(), SPEC_TAG_COUNT, "exactly 19 tag constants besides ALL")


func test_each_tag_constant_is_the_uppercased_tag_name() -> void:
	var constants: Dictionary = _tags_script().get_script_constant_map()
	for tag: StringName in _spec_vocabulary():
		var constant_name: String = String(tag).to_upper()
		assert_true(constants.has(constant_name), "Tags.%s must exist" % constant_name)
		if constants.has(constant_name):
			assert_eq(constants[constant_name] as StringName, tag, "Tags.%s" % constant_name)


func test_all_is_a_typed_deduplicated_array_of_the_vocabulary() -> void:
	var all: Array[StringName] = Tags.ALL
	assert_eq(typeof(Tags.ALL), TYPE_ARRAY, "ALL is an array")
	assert_eq(all.size(), SPEC_TAG_COUNT, "ALL carries all 19 tags")
	assert_eq(all.size(), _unique(all).size(), "ALL has no duplicates")
	for tag: StringName in all:
		assert_true(_spec_vocabulary().has(tag), "ALL entry '%s' is in the spec" % tag)


func test_is_valid_accepts_every_spec_tag_and_rejects_anything_else() -> void:
	for tag: StringName in _spec_vocabulary():
		assert_true(Tags.is_valid(tag), "'%s' is valid" % tag)
	assert_false(Tags.is_valid(&"lifesteal"), "an invented tag is not valid")
	assert_false(Tags.is_valid(&"FIRE"), "the vocabulary is lower-case; 'FIRE' is not a tag")
	assert_false(Tags.is_valid(&""), "an empty name is not a tag")


func test_invalid_tags_reports_an_invented_tag_and_nothing_else() -> void:
	# The negative control for the cross-link check below: the helper's failing
	# path is observed here, so an empty result there means "all valid" rather
	# than "the helper never looks".
	var mixed: Array[StringName] = [Tags.FIRE, &"lifesteal", Tags.DODGE]
	var reported: Array[StringName] = _invalid_tags(mixed)
	assert_eq(reported.size(), 1, "exactly the invented tag is reported")
	assert_true(reported.has(&"lifesteal"), "and it is the invented one")
	assert_eq(_invalid_tags(Tags.ALL).size(), 0, "every vocabulary tag passes the same helper")


func test_content_data_tags_are_validated_against_the_vocabulary() -> void:
	var good: ContentData = ContentData.new()
	good.tags = [Tags.FIRE, Tags.DODGE]
	assert_eq(_invalid_tags(good.tags).size(), 0, "a content Resource with real tags passes")
	var bad: ContentData = ContentData.new()
	bad.tags = [Tags.ON_HIT, &"not_a_tag"]
	assert_true(_invalid_tags(bad.tags).has(&"not_a_tag"), "a content Resource with an invented tag is reported")


func test_every_landed_content_resource_uses_only_vocabulary_tags() -> void:
	var checked: int = 0
	var problems: Array[String] = []
	for root: String in CONTENT_ROOTS:
		assert_not_null(DirAccess.open(root), "the content folder %s must exist" % root)
		for path: String in _tres_files(root):
			var resource: Resource = load(path)
			assert_not_null(resource, "%s must load" % path)
			if resource == null or not (resource is ContentData):
				continue
			checked += 1
			var content: ContentData = resource
			for tag: StringName in _invalid_tags(content.tags):
				problems.append("%s declares '%s'" % [path, tag])
	assert_eq(problems.size(), 0, "no content Resource uses a tag outside the vocabulary: %s" % str(problems))
	print("[tags] checked %d content Resource(s) under data/ for vocabulary tags" % checked)


func test_projectile_spec_extends_refcounted_with_the_specs_fields() -> void:
	var spec: ProjectileSpec = ProjectileSpec.new()
	assert_true(spec is RefCounted, "ProjectileSpec is a value object, not a node")
	var names: Array[String] = []
	for prop: Dictionary in spec.get_script().get_script_property_list():
		# only the script's own `var`s: the list also carries the script
		# property itself and anything inherited
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		names.append(str(prop["name"]))
	var expected: Array[String] = ["scene", "speed", "damage", "element", "pierce", "bounce"]
	for field: String in expected:
		assert_true(names.has(field), "ProjectileSpec must declare '%s'" % field)
	assert_eq(names.size(), expected.size(), "and no field beyond the spec's six: %s" % str(names))


func test_projectile_spec_defaults_are_neutral() -> void:
	var spec: ProjectileSpec = ProjectileSpec.new()
	assert_null(spec.scene, "no scene by default")
	assert_eq(spec.speed, 0.0, "speed")
	assert_eq(spec.damage, 0.0, "damage")
	assert_eq(spec.element, HitInfo.Element.NONE, "element")
	assert_eq(spec.pierce, 0, "pierce")
	assert_eq(spec.bounce, 0, "bounce")


func test_projectile_spec_round_trips_through_a_dictionary() -> void:
	var scene: PackedScene = load(PLACEHOLDER_PROJECTILE_SCENE)
	assert_not_null(scene, "the placeholder projectile scene must exist")
	var spec: ProjectileSpec = ProjectileSpec.new(
		scene, 240.0, 12.5, HitInfo.Element.STORM, 2, 3
	)
	var copy: ProjectileSpec = ProjectileSpec.from_dict(spec.to_dict())
	assert_not_null(copy.scene, "the scene survives the round trip")
	assert_eq(copy.scene.resource_path, scene.resource_path, "the same scene comes back")
	assert_eq(copy.speed, 240.0, "speed")
	assert_eq(copy.damage, 12.5, "damage")
	assert_eq(copy.element, HitInfo.Element.STORM, "element")
	assert_eq(copy.pierce, 2, "pierce")
	assert_eq(copy.bounce, 3, "bounce")


func test_projectile_spec_dictionary_uses_plain_types_for_the_spawner() -> void:
	var spec: ProjectileSpec = ProjectileSpec.new(
		load(PLACEHOLDER_PROJECTILE_SCENE), 120.0, 7.0, HitInfo.Element.FIRE, 1, 0
	)
	var data: Dictionary = spec.to_dict()
	assert_eq(typeof(data["scene_path"]), TYPE_STRING, "the scene travels as a resource path")
	assert_eq(typeof(data["speed"]), TYPE_FLOAT, "speed")
	assert_eq(typeof(data["damage"]), TYPE_FLOAT, "damage")
	assert_eq(typeof(data["element"]), TYPE_INT, "the element travels as its enum value")
	assert_eq(typeof(data["pierce"]), TYPE_INT, "pierce")
	assert_eq(typeof(data["bounce"]), TYPE_INT, "bounce")


func test_projectile_spec_from_dict_is_costless_about_a_missing_scene() -> void:
	var empty: ProjectileSpec = ProjectileSpec.from_dict({})
	assert_null(empty.scene, "no scene path means no scene")
	assert_eq(empty.speed, 0.0, "and neutral numbers")
	var missing: ProjectileSpec = ProjectileSpec.from_dict({"scene_path": "res://nope/absent.tscn"})
	assert_null(missing.scene, "an absent scene path leaves the spec sceneless instead of erroring")
	assert_eq(missing.pierce, 0, "the rest of the spec still arrives")


func test_projectile_spec_from_dict_refuses_an_unknown_element() -> void:
	var out_of_range: ProjectileSpec = ProjectileSpec.from_dict({"element": 99})
	assert_eq(out_of_range.element, HitInfo.Element.NONE, "an unknown element degrades to NONE")
	var negative: ProjectileSpec = ProjectileSpec.from_dict({"element": -3})
	assert_eq(negative.element, HitInfo.Element.NONE, "a negative element degrades to NONE")
	var real: ProjectileSpec = ProjectileSpec.from_dict({"element": int(HitInfo.Element.BLOOD)})
	assert_eq(real.element, HitInfo.Element.BLOOD, "a real element survives")


func _tags_script() -> GDScript:
	return load(TAGS_SCRIPT_PATH) as GDScript


func _unique(tags: Array[StringName]) -> Array[StringName]:
	var seen: Array[StringName] = []
	for tag: StringName in tags:
		if not seen.has(tag):
			seen.append(tag)
	return seen


func _tres_files(root: String) -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return paths
	for file_name: String in dir.get_files():
		if file_name.ends_with(".tres"):
			paths.append(root.path_join(file_name))
	return paths
