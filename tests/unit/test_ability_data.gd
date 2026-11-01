extends GutTest
## Data checks for the Week 5 abilities (SPEC-abilities "Testing", data-driven):
## each of the ten loads as AbilityData, its id matches its file name, its
## cooldown is positive, it has three ranks with rank 3 at least as strong as rank
## 1, its school, element and targeting are the spec's, and its cast scene
## instantiates as an AbilityCast. Owned by abilities. Sync: none.

const ABILITY_DIR: String = "res://data/abilities"
const ABILITY_COUNT: int = 10

## The ten files, with the school, element and targeting the spec gives each.
const ABILITIES: Array[Dictionary] = [
	{"id": &"meteor_call", "school": AbilityData.School.FIRE, "element": HitInfo.Element.FIRE, "targeting": AbilityData.AbilityTargeting.CURSOR_POINT},
	{"id": &"flame_dash", "school": AbilityData.School.FIRE, "element": HitInfo.Element.FIRE, "targeting": AbilityData.AbilityTargeting.CURSOR_DIRECTION},
	{"id": &"glacier_spike", "school": AbilityData.School.FROST, "element": HitInfo.Element.FROST, "targeting": AbilityData.AbilityTargeting.CURSOR_DIRECTION},
	{"id": &"chain_lightning", "school": AbilityData.School.STORM, "element": HitInfo.Element.STORM, "targeting": AbilityData.AbilityTargeting.NEAREST_ENEMY},
	{"id": &"thunder_step", "school": AbilityData.School.STORM, "element": HitInfo.Element.STORM, "targeting": AbilityData.AbilityTargeting.CURSOR_POINT},
	{"id": &"shadow_clones", "school": AbilityData.School.SHADOW, "element": HitInfo.Element.SHADOW, "targeting": AbilityData.AbilityTargeting.SELF},
	{"id": &"toxic_cloud", "school": AbilityData.School.POISON, "element": HitInfo.Element.POISON, "targeting": AbilityData.AbilityTargeting.CURSOR_POINT},
	{"id": &"stone_skin", "school": AbilityData.School.EARTH, "element": HitInfo.Element.EARTH, "targeting": AbilityData.AbilityTargeting.SELF},
	{"id": &"black_hole", "school": AbilityData.School.VOID, "element": HitInfo.Element.VOID, "targeting": AbilityData.AbilityTargeting.CURSOR_POINT},
	{"id": &"barrier_dome", "school": AbilityData.School.UTILITY, "element": HitInfo.Element.NONE, "targeting": AbilityData.AbilityTargeting.CURSOR_POINT},
]


func _path_of(id: StringName) -> String:
	return "res://data/abilities/%s.tres" % id


func _load_ability(id: StringName) -> AbilityData:
	return load(_path_of(id)) as AbilityData


func test_each_file_loads_as_ability_data_with_a_matching_id() -> void:
	for expected: Dictionary in ABILITIES:
		var id: StringName = expected["id"]
		var data := _load_ability(id)
		assert_not_null(data, "%s loads as AbilityData" % id)
		if data != null:
			assert_eq(data.id, id, "%s has its file name as its id" % id)


## Scans the folder, not the list above, so a new `.tres` in it is checked with
## no edit here: each file loads, its id is unique, and its id is its file name.
func test_ids_are_unique_across_the_folder() -> void:
	var dir := DirAccess.open(ABILITY_DIR)
	assert_not_null(dir, "the abilities folder opens")
	if dir == null:
		return
	var seen: Array[StringName] = []
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var data := load("%s/%s" % [ABILITY_DIR, file_name]) as AbilityData
		assert_not_null(data, "%s loads as AbilityData" % file_name)
		if data == null:
			continue
		assert_false(seen.has(data.id), "%s has an id no other file has" % file_name)
		assert_eq("%s.tres" % data.id, file_name, "%s is named for its id" % file_name)
		seen.append(data.id)
	for expected: Dictionary in ABILITIES:
		assert_true(seen.has(expected["id"]), "the folder holds %s" % expected["id"])


func test_cooldowns_are_positive_and_each_ability_has_a_cast_scene() -> void:
	for expected: Dictionary in ABILITIES:
		var data := _load_ability(expected["id"])
		if data == null:
			continue
		assert_gt(data.cooldown, 0.0, "%s has a cooldown above 0" % data.id)
		assert_not_null(data.cast_scene, "%s sets its cast scene" % data.id)


func test_each_ability_has_three_ranks_and_rank_3_is_at_least_rank_1() -> void:
	for expected: Dictionary in ABILITIES:
		var data := _load_ability(expected["id"])
		if data == null:
			continue
		assert_eq(data.ranks.size(), AbilityData.MAX_RANK, "%s has three ranks" % data.id)
		var rank_1: AbilityRank = data.rank_data(1)
		var rank_3: AbilityRank = data.rank_data(3)
		if rank_1 == null or rank_3 == null:
			continue
		assert_gte(rank_3.damage_mult, rank_1.damage_mult, "%s rank 3 deals at least rank 1" % data.id)
		assert_gte(rank_3.size_mult, rank_1.size_mult, "%s rank 3 is at least as big as rank 1" % data.id)


func test_school_element_and_targeting_are_the_specs() -> void:
	for expected: Dictionary in ABILITIES:
		var data := _load_ability(expected["id"])
		if data == null:
			continue
		assert_eq(data.school, expected["school"], "%s is in its school" % data.id)
		assert_eq(data.element, expected["element"], "%s has its element" % data.id)
		assert_eq(data.targeting, expected["targeting"], "%s aims as the spec says" % data.id)


func test_each_cast_scene_instantiates_as_an_ability_cast() -> void:
	for expected: Dictionary in ABILITIES:
		var data := _load_ability(expected["id"])
		if data == null or data.cast_scene == null:
			continue
		var cast := data.cast_scene.instantiate() as AbilityCast
		assert_not_null(cast, "%s's cast scene is an AbilityCast" % data.id)
		if cast != null:
			cast.free()


## The flat folder holds exactly the ten Week 5 abilities (D-P1: Cave-In lives in
## a subfolder, so it does not count here).
func test_the_folder_holds_exactly_the_ten_week_5_abilities() -> void:
	var dir := DirAccess.open(ABILITY_DIR)
	assert_not_null(dir, "the abilities folder opens")
	if dir == null:
		return
	var count: int = 0
	for file_name: String in dir.get_files():
		if file_name.ends_with(".tres"):
			count += 1
	assert_eq(count, ABILITY_COUNT, "the flat folder holds ten .tres files")
	assert_eq(ABILITIES.size(), ABILITY_COUNT, "the expected list names ten abilities")


## Cave-In (Wren's ultimate, W5-G7) sits in the ultimates subfolder, so the flat
## count above does not see it. It loads as an ultimate with a cooldown and a cast.
func test_cave_in_loads_from_the_ultimates_folder_as_an_ultimate() -> void:
	var data := load("%s/ultimates/cave_in.tres" % ABILITY_DIR) as AbilityData
	assert_not_null(data, "cave_in.tres loads as AbilityData")
	if data == null:
		return
	assert_eq(data.id, &"cave_in", "Cave-In's id matches its file")
	assert_true(data.is_ultimate, "Cave-In is an ultimate")
	assert_gt(data.cooldown, 0.0, "Cave-In has a cooldown")
	assert_not_null(data.cast_scene, "Cave-In has a cast scene")
