extends GutTest
## `PlayerProfile` — the one JSON profile per machine — save-system, W5-B1
## (PLAN G2).
##
## SPEC-save-system, "Testing": "Unit `test_save_round_trip.gd`: `defaults()` to
## dict to JSON to dict to profile equals original; every field present." and,
## under "Loading and migration": "Missing keys get defaults from
## `PlayerProfile.defaults()` so new fields never need a migration unless
## semantics change."
##
## The field list is **parsed out of the spec's own table** rather than retyped,
## so a field the spec names and the class does not have fails here, and so does
## a field on the class the spec does not name. The round trip runs through a
## real `JSON.stringify` / `JSON.parse_string` pair, because that is the boundary
## where an `int` silently becomes a `float` (measured: Godot's JSON parser
## returns every number as a float) and a typed `Array[String]` becomes untyped.
##
## Owned by save-system. Sync: none (a local file; the host never writes a
## client's profile).

const SPEC_PATH: String = "res://specs/SPEC-save-system.md"
const PROFILE_PATH: String = "res://scripts/autoload/player_profile.gd"

## The type every field must still have after a JSON round trip. Kept here as a
## second copy of `PlayerProfile.FIELDS`' shape so a field added to the class
## without a type is a failing case, not a silent `Variant`.
const FIELD_TYPES: Dictionary[StringName, int] = {
	&"save_version": TYPE_INT,
	&"created_at": TYPE_STRING,
	&"last_saved_at": TYPE_STRING,
	&"gold_banked": TYPE_INT,
	&"ore": TYPE_DICTIONARY,
	&"echo_shards": TYPE_INT,
	&"town": TYPE_DICTIONARY,
	&"skill_tree": TYPE_DICTIONARY,
	&"respec_used_date": TYPE_STRING,
	&"classes": TYPE_DICTIONARY,
	&"characters_unlocked": TYPE_ARRAY,
	&"weapons_unlocked": TYPE_ARRAY,
	&"weapon_damage_tiers": TYPE_DICTIONARY,
	&"relic_vault_pick": TYPE_STRING_NAME,
	&"rune_library_pick": TYPE_STRING_NAME,
	&"potions": TYPE_DICTIONARY,
	&"story_flags": TYPE_ARRAY,
	&"lore_unlocked": TYPE_ARRAY,
	&"endings_seen": TYPE_ARRAY,
	&"codex": TYPE_DICTIONARY,
	&"achievements": TYPE_ARRAY,
	&"cosmetics_unlocked": TYPE_ARRAY,
	&"equipped_cosmetics": TYPE_DICTIONARY,
	&"rescued_miners": TYPE_ARRAY,
	&"map_room_deepest_rope": TYPE_INT,
	&"deep_mode_unlocked": TYPE_BOOL,
	&"heat_levels_unlocked": TYPE_INT,
	&"daily_dive_best": TYPE_DICTIONARY,
	&"stats": TYPE_DICTIONARY,
	&"settings": TYPE_DICTIONARY,
}

## The dictionary fields whose values are counters, so the JSON round trip has
## to bring them back as `int` and not as the float the parser hands over.
const INT_VALUED_DICTS: Array[StringName] = [
	&"ore", &"town", &"skill_tree", &"weapon_damage_tiers", &"daily_dive_best", &"stats",
]


## ---------------------------------------------------------------------------
## Helpers
## ---------------------------------------------------------------------------

## Every field name in SPEC-save-system's "What persists" table, in file order.
## Only a valid identifier counts: the same cells carry backticked type notes
## like `{xp, mastery, tree: {node_id: ranks}, unlocked}` next to the names.
func _spec_fields() -> Array[String]:
	var out: Array[String] = []
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	assert_not_null(file, "%s is readable" % SPEC_PATH)
	if file == null:
		return out
	var in_table: bool = false
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.begins_with("### What persists"):
			in_table = true
			continue
		if not in_table:
			continue
		if line.is_empty():
			continue
		if not line.begins_with("|"):
			break
		var cells: PackedStringArray = line.split("|")
		if cells.size() < 2:
			continue
		var cell: String = cells[1].strip_edges()
		if cell.is_empty() or cell == "Field" or cell.begins_with("---"):
			continue
		for span: String in _backticked(cell):
			var name: String = span.split(":")[0].strip_edges()
			if name.is_valid_identifier() and not out.has(name):
				out.append(name)
	file.close()
	return out


## The backtick-quoted spans of a table cell, in order.
func _backticked(text: String) -> Array[String]:
	var parts: PackedStringArray = text.split("`")
	var out: Array[String] = []
	var index: int = 1
	while index < parts.size():
		out.append(parts[index])
		index += 2
	return out


## The real serialisation boundary: dict -> JSON text -> parsed dict.
func _through_json(data: Dictionary) -> Dictionary:
	var text: String = JSON.stringify(data)
	assert_ne(text, "", "the profile stringifies")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "and parses back as a JSON object")
	return parsed as Dictionary


func _field_names() -> Array[String]:
	var names: Array[String] = []
	for key: Variant in PlayerProfile.defaults().to_dict().keys():
		names.append(String(key))
	names.sort()
	return names


## A profile with every one of the spec's fields set to something distinctive,
## so a field that fails to round-trip is visible rather than merely equal to
## its default.
func _populated() -> PlayerProfile:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.save_version = PlayerProfile.CURRENT_VERSION
	profile.created_at = "2026-10-20T08:15:00Z"
	profile.last_saved_at = "2026-10-20T09:45:30Z"
	profile.gold_banked = 4321
	profile.ore = {"copper": 12, "heartstone": 3}
	profile.echo_shards = 77
	profile.town = {"blacksmith": 2, "tavern": 3}
	profile.skill_tree = {"echo_1": 3, "echo_2": 1}
	profile.respec_used_date = "2026-10-19"
	# All three starting classes, because that is an invariant of the type: a
	# profile always carries at least the three SPEC-classes-characters unlocks
	# (see `test_a_profile_that_lost_a_starting_class_gets_it_back`).
	profile.classes = {
		"warrior": {"xp": 250, "mastery": 3, "tree": {"rage_1": 2}, "unlocked": true},
		"ranger": {"xp": 40, "mastery": 1, "tree": {}, "unlocked": true},
		"mage": {"xp": 0, "mastery": 1, "tree": {}, "unlocked": true},
	}
	profile.characters_unlocked = ["wren", "brann"]
	profile.weapons_unlocked = ["pickaxe", "crossbow", "lantern_staff", "longsword"]
	profile.weapon_damage_tiers = {"pickaxe": 2, "crossbow": 1}
	profile.relic_vault_pick = &"ember_boots"
	profile.rune_library_pick = &"flame_dash"
	profile.potions = {"slots": 2, "types": ["heal", "cleanse"], "starting": ["heal"]}
	profile.story_flags = ["story.foreman_defeated"]
	profile.lore_unlocked = ["lore.pit_1"]
	profile.endings_seen = ["ending.keeper"]
	profile.codex = {
		"relics": ["ember_boots"], "abilities": ["flame_dash"],
		"enemies": ["crawler"], "bosses": ["warden"],
	}
	profile.achievements = ["first_extraction"]
	profile.cosmetics_unlocked = ["hat_miner"]
	profile.equipped_cosmetics = {"hat": "hat_miner"}
	profile.rescued_miners = ["miner_03"]
	profile.map_room_deepest_rope = 17
	profile.deep_mode_unlocked = true
	profile.heat_levels_unlocked = 4
	profile.daily_dive_best = {"2026-10-18": 12345}
	profile.stats = {
		"runs": 9, "deaths": 4, "extractions": 5,
		"kills": 1234, "deepest_floor": 17, "playtime_seconds": 36000,
	}
	profile.settings = {
		"audio": {"master": 0.8}, "video": {"scale": 2.0},
		"screen_shake": 0.5, "bindings": {"interact": "F"},
	}
	return profile


## ---------------------------------------------------------------------------
## The spec's field table is the contract
## ---------------------------------------------------------------------------

func test_the_spec_table_parses_to_the_specs_own_fields() -> void:
	var spec: Array[String] = _spec_fields()
	assert_eq(spec.size(), 30, "SPEC-save-system's table names 30 fields: %s" % [spec])
	assert_true(spec.has("gold_banked"), "and the parse reached the currency rows")
	assert_false(spec.has("xp"), "and stopped at the names: `{xp, mastery, ...}` is a type note, not a field")


func test_the_profile_declares_exactly_the_specs_fields() -> void:
	var spec: Array[String] = _spec_fields()
	spec.sort()
	var declared: Array[String] = []
	for name: StringName in PlayerProfile.FIELDS:
		declared.append(String(name))
	declared.sort()
	assert_eq(declared, spec, "PlayerProfile.FIELDS is the spec's table, name for name")


func test_to_dict_writes_exactly_the_specs_fields() -> void:
	var spec: Array[String] = _spec_fields()
	spec.sort()
	assert_eq(_field_names(), spec, "to_dict() writes every field the spec names and nothing else")


func test_every_field_has_a_declared_type() -> void:
	var spec: Array[String] = _spec_fields()
	spec.sort()
	var known: Array[String] = []
	for name: StringName in FIELD_TYPES:
		known.append(String(name))
	known.sort()
	assert_eq(known, spec, "every field has a type this file checks after the round trip")


## ---------------------------------------------------------------------------
## The type and the place
## ---------------------------------------------------------------------------

func test_the_profile_is_ref_counted_and_not_a_resource() -> void:
	# `assert_false(profile is Resource)` will not even compile — the parser
	# rejects a check the declared type already answers — so the base type is
	# read off the script instead.
	var profile: PlayerProfile = PlayerProfile.new()
	var script: Script = profile.get_script()
	assert_not_null(script, "it is a script class")
	assert_eq(script.resource_path, PROFILE_PATH, "and it lives beside the autoload")
	assert_eq(
		script.get_instance_base_type(),
		&"RefCounted",
		"it extends RefCounted, so a save is JSON and not an editor resource"
	)
	assert_true(profile is RefCounted, "and so it is reference counted")


func test_the_profiles_version_is_the_save_files_version() -> void:
	assert_eq(PlayerProfile.CURRENT_VERSION, SaveManager.SAVE_VERSION, "the profile and the file agree on the schema")


## ---------------------------------------------------------------------------
## defaults()
## ---------------------------------------------------------------------------

func test_defaults_takes_the_specs_own_shapes_and_starting_unlocks() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	assert_eq(profile.save_version, 1, "a new profile is at the current schema version")
	assert_eq(profile.created_at, "", "defaults() is pure: SaveManager stamps the clock, not this")
	assert_eq(profile.last_saved_at, "")
	assert_eq(profile.gold_banked, 0)
	assert_eq(profile.ore, {}, "the ore ids live in data/ore/, so the map starts empty")
	assert_eq(profile.town, {}, "and the building ids in data/town/, so the map starts empty")
	assert_eq(profile.codex.keys().size(), 4, "codex: relics, abilities, enemies, bosses")
	assert_eq(profile.codex["relics"], [], "each category starts empty")
	assert_eq(profile.stats.keys().size(), 6, "stats: runs, deaths, extractions, kills, deepest_floor, playtime_seconds")
	assert_eq(profile.stats["deepest_floor"], 0)
	assert_eq(profile.settings.keys().size(), 4, "settings: audio, video, screen_shake, bindings")
	assert_eq(profile.settings["screen_shake"], 1.0, "the spec skeleton's own default")
	assert_eq(profile.potions.keys().size(), 3, "potions: slots, types, starting")
	assert_eq(profile.potions["slots"], 0, "an Alchemist at level 0 holds no potion")
	assert_eq(profile.map_room_deepest_rope, 0)
	assert_false(profile.deep_mode_unlocked)
	assert_eq(profile.characters_unlocked, ["wren"] as Array[String], "Wren's unlock flag is 'default' (SPEC-classes-characters)")
	assert_eq(
		profile.weapons_unlocked,
		["pickaxe", "crossbow", "lantern_staff"] as Array[String],
		"SPEC-weapons: 'Pickaxe, Crossbow, Lantern Staff unlocked at start'"
	)
	assert_eq(profile.classes.keys().size(), 3, "SPEC-classes-characters: 'Warrior, Ranger, Mage at start'")
	for class_id: StringName in PlayerProfile.STARTING_CLASSES:
		assert_true(profile.classes.has(String(class_id)), "%s is unlocked on a fresh profile" % class_id)
		assert_eq(
			profile.classes[String(class_id)],
			{"xp": 0, "mastery": 1, "tree": {}, "unlocked": true},
			"and takes the spec skeleton's entry shape"
		)


## ---------------------------------------------------------------------------
## The round trip
## ---------------------------------------------------------------------------

func test_defaults_round_trips_through_json_unchanged() -> void:
	var original: PlayerProfile = PlayerProfile.defaults()
	var restored: PlayerProfile = PlayerProfile.from_dict(_through_json(original.to_dict()))
	assert_eq(restored.to_dict(), original.to_dict(), "defaults() survives dict -> JSON -> dict -> profile")


func test_a_populated_profile_round_trips_field_for_field() -> void:
	var original: PlayerProfile = _populated()
	var restored: PlayerProfile = PlayerProfile.from_dict(_through_json(original.to_dict()))
	assert_eq(restored.to_dict(), original.to_dict(), "the whole profile, as written")
	for name: StringName in PlayerProfile.FIELDS:
		assert_eq(restored.get(name), original.get(name), "%s survives the round trip" % name)


func test_the_round_trip_preserves_every_fields_type() -> void:
	var restored: PlayerProfile = PlayerProfile.from_dict(_through_json(_populated().to_dict()))
	for name: StringName in FIELD_TYPES:
		assert_eq(typeof(restored.get(name)), FIELD_TYPES[name], "%s keeps its type" % name)


func test_the_round_trip_preserves_the_nested_value_types() -> void:
	var restored: PlayerProfile = PlayerProfile.from_dict(_through_json(_populated().to_dict()))
	for name: StringName in INT_VALUED_DICTS:
		var values: Dictionary = restored.get(name)
		assert_gt(values.size(), 0, "%s carries its entries" % name)
		for key: Variant in values:
			assert_eq(typeof(values[key]), TYPE_INT, "%s.%s is an int, not the float JSON hands over" % [name, key])
	var codex_relics: Array[String] = restored.codex["relics"]
	assert_eq(codex_relics, ["ember_boots"] as Array[String], "a codex category is a string list again")
	assert_true(codex_relics.is_typed(), "and typed, not a bare Array")
	assert_eq(codex_relics.get_typed_builtin(), TYPE_STRING, "of String")
	var flags: Array[String] = restored.story_flags
	assert_true(flags.is_typed(), "so is a top-level list")
	var warrior: Dictionary = restored.classes["warrior"]
	assert_eq(typeof(warrior["xp"]), TYPE_INT, "a class entry's xp is an int")
	assert_eq(typeof(warrior["mastery"]), TYPE_INT, "and so is its mastery")
	assert_eq(warrior["tree"], {"rage_1": 2}, "and its tree survives")
	assert_eq(typeof(restored.potions["slots"]), TYPE_INT, "a potion slot count is an int")
	assert_eq(restored.potions["types"], ["heal", "cleanse"] as Array[String], "and the type list is intact")
	assert_eq(typeof(restored.settings["screen_shake"]), TYPE_FLOAT, "screen_shake stays a float")


## ---------------------------------------------------------------------------
## from_dict(): defaults for what is missing, no crash on what is wrong
## ---------------------------------------------------------------------------

func test_a_missing_key_falls_back_to_defaults() -> void:
	var fresh: PlayerProfile = PlayerProfile.from_dict({})
	assert_eq(fresh.to_dict(), PlayerProfile.defaults().to_dict(), "an empty object is a fresh profile")
	var partial: PlayerProfile = PlayerProfile.from_dict({"gold_banked": 12})
	var expected: PlayerProfile = PlayerProfile.defaults()
	expected.gold_banked = 12
	assert_eq(partial.to_dict(), expected.to_dict(), "a partial file keeps its own values and defaults the rest")


func test_a_missing_nested_key_keeps_the_nested_default() -> void:
	var loaded: PlayerProfile = PlayerProfile.from_dict({
		"codex": {"relics": ["ember_boots"]},
		"stats": {"runs": 4},
		"settings": {"screen_shake": 0.0},
	})
	assert_eq(loaded.codex["relics"], ["ember_boots"] as Array[String], "the given category is kept")
	assert_eq(loaded.codex["abilities"], [], "a category the file does not name is defaulted")
	assert_eq(loaded.stats["runs"], 4, "the given counter is kept")
	assert_eq(loaded.stats["deaths"], 0, "a counter the file does not name is defaulted")
	assert_eq(loaded.settings["screen_shake"], 0.0, "the given setting is kept")
	assert_eq(loaded.settings["bindings"], {}, "a setting the file does not name is defaulted")


func test_a_profile_that_lost_a_starting_class_gets_it_back() -> void:
	var loaded: PlayerProfile = PlayerProfile.from_dict({"classes": {"warrior": {"xp": 40}}})
	assert_eq(loaded.classes.keys().size(), 3, "the starting three are restored, so a run can still be started")
	assert_eq(
		loaded.classes["warrior"],
		{"xp": 40, "mastery": 1, "tree": {}, "unlocked": true},
		"the entry the file did carry is kept, with its missing sub-keys defaulted"
	)
	assert_eq(
		loaded.classes["ranger"],
		{"xp": 0, "mastery": 1, "tree": {}, "unlocked": true},
		"and a class the file does not name takes the default entry"
	)


func test_a_wrongly_typed_value_lands_on_the_default_rather_than_crashing() -> void:
	var loaded: PlayerProfile = PlayerProfile.from_dict({
		"ore": null,
		"characters_unlocked": "wren",
		"gold_banked": "not a number",
		"deep_mode_unlocked": 7,
		"created_at": 12,
	})
	assert_eq(loaded.ore, {}, "a null map reads as empty")
	assert_eq(loaded.characters_unlocked, ["wren"] as Array[String], "a scalar where a list belongs keeps the default")
	assert_eq(loaded.gold_banked, 0, "a string of no digits reads as zero")
	assert_eq(loaded.deep_mode_unlocked, false, "a number where a flag belongs keeps the default")
	assert_eq(loaded.created_at, "", "and a number where a timestamp belongs keeps the default")


func test_an_unknown_key_is_ignored_rather_than_carried_into_the_profile() -> void:
	var loaded: PlayerProfile = PlayerProfile.from_dict({"gold_banked": 3, "a_field_from_a_later_week": "red"})
	assert_eq(loaded.gold_banked, 3, "a field this build knows is read")
	assert_false(loaded.to_dict().has("a_field_from_a_later_week"), "and one it does not know is not written back")


func test_an_absent_ore_or_building_reads_as_zero() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	assert_eq(profile.ore_count(&"copper"), 0, "an ore the map does not name is zero")
	assert_eq(profile.building_level(&"blacksmith"), 0, "and a building absent from the town map is level 0")
	profile.ore = {"copper": 4}
	profile.town = {"blacksmith": 2}
	assert_eq(profile.ore_count(&"copper"), 4, "a named ore reads its count")
	assert_eq(profile.building_level(&"blacksmith"), 2, "a named building reads its level")
	assert_eq(profile.building_level(&"tavern"), 0, "and an unnamed one is still 0")


## ---------------------------------------------------------------------------
## The timestamps
## ---------------------------------------------------------------------------

func test_touch_timestamps_stamps_both_and_never_moves_created_at() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.touch_timestamps()
	assert_eq(profile.created_at.length(), 20, "created_at is an ISO-8601 UTC stamp: %s" % profile.created_at)
	assert_true(profile.created_at.ends_with("Z"), "marked UTC")
	assert_eq(profile.last_saved_at, profile.created_at, "a first write sets both")
	var created: String = profile.created_at
	profile.touch_timestamps()
	assert_eq(profile.created_at, created, "created_at is written once and never moved")
	assert_eq(profile.last_saved_at.length(), 20, "last_saved_at is refreshed on every write")


## ---------------------------------------------------------------------------
## merge_run_gains(): the co-op banking path
## ---------------------------------------------------------------------------

func test_merge_run_gains_adds_the_currencies() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.gold_banked = 100
	profile.ore = {"copper": 5}
	profile.echo_shards = 2
	profile.merge_run_gains({"gold_banked": 50, "ore": {"copper": 3, "iron": 1}, "echo_shards": 7})
	assert_eq(profile.gold_banked, 150, "gold adds to the bank")
	assert_eq(profile.ore, {"copper": 8, "iron": 1}, "ore adds per id and creates an id the map did not have")
	assert_eq(profile.echo_shards, 9, "Echo Shards add")


func test_merge_run_gains_adds_class_xp_without_touching_the_rest_of_the_class() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.classes = {"warrior": {"xp": 100, "mastery": 3, "tree": {"rage_1": 2}, "unlocked": true}}
	profile.merge_run_gains({"class_id": &"warrior", "class_xp": 40})
	var warrior: Dictionary = profile.classes["warrior"]
	assert_eq(warrior["xp"], 140, "class XP adds")
	assert_eq(warrior["mastery"], 3, "mastery is classes-characters' to derive from XP, not this merge's")
	assert_eq(warrior["tree"], {"rage_1": 2}, "the class tree is untouched")
	assert_eq(warrior["unlocked"], true, "and so is the unlock")
	profile.merge_run_gains({"class_id": &"ranger", "class_xp": 10})
	assert_eq(
		profile.classes["ranger"],
		{"xp": 10, "mastery": 1, "tree": {}, "unlocked": true},
		"a class the profile had no entry for takes the spec skeleton's shape"
	)


func test_merge_run_gains_unions_the_lists_without_repeating_an_entry() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.story_flags = ["story.foreman_defeated"]
	profile.merge_run_gains({
		"story_flags": ["story.foreman_defeated", "story.reached_biome_4"],
		"lore_unlocked": ["lore.pit_1"],
		"achievements": ["first_extraction"],
		"rescued_miners": ["miner_03"],
		"endings_seen": ["ending.keeper"],
		"characters_unlocked": ["brann"],
		"weapons_unlocked": ["longsword"],
		"cosmetics_unlocked": ["hat_miner"],
	})
	assert_eq(
		profile.story_flags,
		["story.foreman_defeated", "story.reached_biome_4"] as Array[String],
		"a flag already set is not repeated and a new one is appended"
	)
	assert_eq(profile.lore_unlocked, ["lore.pit_1"] as Array[String], "lore unlocks are kept")
	assert_eq(profile.achievements, ["first_extraction"] as Array[String], "achievements are kept")
	assert_eq(profile.rescued_miners, ["miner_03"] as Array[String], "rescued miners are kept")
	assert_eq(profile.endings_seen, ["ending.keeper"] as Array[String], "endings are kept")
	assert_eq(profile.characters_unlocked, ["wren", "brann"] as Array[String], "a newly unlocked character joins Wren")
	assert_eq(
		profile.weapons_unlocked,
		["pickaxe", "crossbow", "lantern_staff", "longsword"] as Array[String],
		"and so does a newly unlocked weapon"
	)
	assert_eq(profile.cosmetics_unlocked, ["hat_miner"] as Array[String], "cosmetics are kept")


func test_merge_run_gains_unions_every_field_the_union_list_names() -> void:
	var profile: PlayerProfile = _populated()
	var before: Dictionary = profile.to_dict()
	var gains: Dictionary = {}
	for field: StringName in PlayerProfile.UNION_FIELDS:
		gains[field] = ["added_%s" % field]
	profile.merge_run_gains(gains)
	for field: StringName in PlayerProfile.UNION_FIELDS:
		var after: Array = profile.get(field)
		var was: Array = before[String(field)]
		assert_true(after.has("added_%s" % field), "%s gained the entry the run set" % field)
		assert_eq(after.size(), was.size() + 1, "%s grew by exactly one, so nothing was replaced" % field)


func test_merge_run_gains_unions_the_codex_by_category() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.codex = {"relics": ["ember_boots"], "abilities": [], "enemies": [], "bosses": ["warden"]}
	profile.merge_run_gains({"codex": {
		"relics": ["ember_boots", "storm_sandals"],
		"abilities": ["flame_dash"],
		"enemies": ["crawler"],
	}})
	assert_eq(
		profile.codex["relics"],
		["ember_boots", "storm_sandals"] as Array[String],
		"a relic already seen is not repeated"
	)
	assert_eq(profile.codex["abilities"], ["flame_dash"] as Array[String], "a new category is filled")
	assert_eq(profile.codex["enemies"], ["crawler"] as Array[String], "so is another")
	assert_eq(profile.codex["bosses"], ["warden"] as Array[String], "a category the gains do not name is left alone")


func test_merge_run_gains_adds_stats_but_takes_the_best_of_a_record() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.stats = {
		"runs": 3, "deaths": 1, "extractions": 2,
		"kills": 500, "deepest_floor": 12, "playtime_seconds": 100,
	}
	profile.map_room_deepest_rope = 9
	profile.daily_dive_best = {"2026-10-18": 12000}
	profile.merge_run_gains({
		"stats": {
			"runs": 1, "deaths": 0, "extractions": 1,
			"kills": 120, "deepest_floor": 7, "playtime_seconds": 900,
		},
		"map_room_deepest_rope": 6,
		"daily_dive_best": {"2026-10-18": 9000, "2026-10-19": 5000},
	})
	assert_eq(profile.stats["runs"], 4, "runs add")
	assert_eq(profile.stats["kills"], 620, "kills add")
	assert_eq(profile.stats["playtime_seconds"], 1000, "playtime adds")
	assert_eq(profile.stats["deepest_floor"], 12, "deepest_floor is a best, not a sum")
	assert_eq(profile.map_room_deepest_rope, 9, "and so is the Map Room's deepest rope")
	assert_eq(
		profile.daily_dive_best,
		{"2026-10-18": 12000, "2026-10-19": 5000},
		"a Daily Dive score only replaces a worse one for the same day"
	)
	profile.merge_run_gains({"stats": {"deepest_floor": 15}, "map_room_deepest_rope": 11})
	assert_eq(profile.stats["deepest_floor"], 15, "a deeper run raises the record")
	assert_eq(profile.map_room_deepest_rope, 11, "and so does a deeper rope")
	assert_eq(profile.stats["runs"], 4, "a gains dict that names one stat leaves the others alone")


func test_merge_run_gains_never_clobbers_a_value_it_was_not_given() -> void:
	var profile: PlayerProfile = _populated()
	var before: Dictionary = profile.to_dict()
	profile.merge_run_gains({})
	assert_eq(profile.to_dict(), before, "an empty gains dict is a no-op")
	profile.merge_run_gains({"gold_banked": 1, "a_key_from_a_later_week": 5})
	assert_eq(profile.gold_banked, 4322, "the one key it knows is applied")
	assert_eq(profile.to_dict().keys().size(), before.keys().size(), "and nothing new is written into the profile")
	assert_eq(profile.town, before["town"], "a field the gains do not name is left exactly as it was")
