extends GutTest
## `SaveManager.load()`'s migration chain — save-system, W5-B1 (PLAN G4).
##
## SPEC-save-system, "Loading and migration": "On startup: read file, parse JSON,
## check `save_version`. If lower than current, run `migrations[version]` in
## order; each migration is a function `Dictionary -> Dictionary` in
## `scripts/autoload/save_migrations.gd`. If parse fails, load `save.bak`; if
## that fails, start fresh and keep the corrupt file as `save.corrupt.<timestamp>`.
## Missing keys get defaults from `PlayerProfile.defaults()` so new fields never
## need a migration unless semantics change."
##
## This file is the four claims that sentence makes that are testable today:
##
##   1. the **version-1 fixture** at `tests/fixtures/save_v1.json` migrates to the
##      current version and comes out a valid profile — every field SPEC-save-system's
##      table names is present, and the values the fixture stated survive;
##   2. a save whose `save_version` is **above** this build's is **refused by
##      name**, never read as if it were this build's (reading it would default
##      the fields it lacks and the next write would throw the extra ones away);
##   3. **missing keys fall back to `PlayerProfile.defaults()`** with no migration
##      at all — proven against a chain that deliberately says nothing about the
##      field, which is the spec's "new fields never need a migration" clause;
##   4. the steps run **in ascending order, one at a time**, proved with a
##      recording chain (`MigrationRecorder`) rather than asserted about an empty
##      table.
##
## The corrupt-file half of that paragraph (`.bak`, then
## `save.corrupt.<timestamp>`) is G5's and has its own file; the cases here that
## touch a broken file pin only what this goal ships.
##
## Owned by save-system. Sync: none — a local file per machine; the host never
## writes a client's profile.

## The fixture's own path — spelled out here rather than built, so moving the file
## is a failing case.
const FIXTURE_PATH: String = "res://tests/fixtures/save_v1.json"

const SAVE_PATH: String = "user://save.json"
const TMP_PATH: String = "user://save.json.tmp"
const BACKUP_PATH: String = "user://save.bak"
const FILES: Array[String] = [SAVE_PATH, TMP_PATH, BACKUP_PATH]

## The refusal names, spelled out as the literal strings a reader sees in a log,
## so renaming one in the class is a failing case and not a silent pass.
const REFUSAL_TOO_NEW: StringName = &"save_is_from_a_newer_build"
const REFUSAL_NO_MIGRATION: StringName = &"no_migration_for_version"
const REFUSAL_NOT_AN_OBJECT: StringName = &"migration_did_not_return_an_object"
const REFUSAL_CORRUPT: StringName = &"save_file_is_not_a_json_object"

## Every profile a case loaded, in load order, from the `loaded` signal.
var _loaded: Array[PlayerProfile] = []
## The bytes of each of the three files as they were before the case ran.
var _existing: Dictionary[String, PackedByteArray] = {}


func before_each() -> void:
	_existing.clear()
	_loaded.clear()
	for path: String in FILES:
		if FileAccess.file_exists(path):
			_existing[path] = FileAccess.get_file_as_bytes(path)
			_remove(path)
	SaveManager.profile = null


func after_each() -> void:
	await wait_process_frames(1)
	for path: String in FILES:
		_remove(path)
	for path: String in _existing:
		_write_text(path, _existing[path].get_string_from_utf8())
	_existing.clear()
	SaveManager.profile = null
	if SaveManager.loaded.is_connected(_on_loaded):
		SaveManager.loaded.disconnect(_on_loaded)


func _on_loaded(profile: PlayerProfile) -> void:
	_loaded.append(profile)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


## The fixture's text exactly as the file holds it.
func _fixture_text() -> String:
	return FileAccess.get_file_as_string(FIXTURE_PATH)


func _fixture() -> Dictionary:
	var json := JSON.new()
	assert_eq(json.parse(_fixture_text()), OK, "the v1 fixture is valid JSON")
	if not json.data is Dictionary:
		return {}
	return json.data as Dictionary


## The fixture with `keys` removed — the shape a save written by a build that
## predates those fields has.
func _fixture_without(keys: Array[String]) -> Dictionary:
	var out: Dictionary = _fixture()
	for key: String in keys:
		out.erase(key)
	return out


## ---------------------------------------------------------------------------
## The version this build writes, and the chain that keeps up with it
## ---------------------------------------------------------------------------

func test_the_current_version_is_the_one_the_manager_and_the_profile_name() -> void:
	assert_eq(
		SaveMigrations.current_version(), SaveManager.SAVE_VERSION,
		"the migration chain and the manager agree on the version"
	)
	assert_eq(
		SaveMigrations.current_version(), PlayerProfile.CURRENT_VERSION,
		"and so does the profile class that writes the field"
	)


func test_every_version_below_current_has_a_migration_step() -> void:
	var expected: Array[int] = []
	for version: int in range(1, SaveMigrations.current_version()):
		expected.append(version)
	assert_eq(
		SaveMigrations.versions(), expected,
		"a version bump with no step here is a failing case, not a silent downgrade"
	)
	for version: int in SaveMigrations.versions():
		assert_true(
			SaveMigrations.table()[version] is Callable,
			"the step for version %d is a function" % version
		)


## ---------------------------------------------------------------------------
## The version-1 fixture
## ---------------------------------------------------------------------------

func test_the_v1_fixture_migrates_to_the_current_version() -> void:
	var data := _fixture()
	assert_eq(SaveMigrations.version_of(data), 1, "the fixture says it is version 1")
	var outcome := SaveMigrations.migrate(data)
	assert_true(outcome.ok(), "a version-1 save migrates without a refusal")
	assert_eq(
		outcome.data.get(SaveMigrations.VERSION_KEY), SaveMigrations.current_version(),
		"and comes out stamped with this build's version"
	)


func test_the_migrated_fixture_keeps_every_value_it_stated() -> void:
	var migrated := SaveMigrations.migrate(_fixture()).data
	var profile := PlayerProfile.from_dict(migrated)
	assert_eq(profile.gold_banked, 137, "gold")
	assert_eq(profile.ore_count(&"copper"), 12, "ore")
	assert_eq(profile.ore_count(&"iron"), 3, "each ore the file named")
	assert_eq(profile.echo_shards, 5, "echo shards")
	assert_eq(profile.building_level(&"blacksmith"), 2, "town levels")
	assert_eq(profile.building_level(&"tavern"), 1, "each building the file named")
	assert_eq(profile.map_room_deepest_rope, 7, "the map room depth")
	assert_eq(profile.created_at, "2026-10-01T09:00:00Z", "the timestamps")
	assert_eq(profile.last_saved_at, "2026-10-19T21:30:00Z", "both of them")
	assert_true(profile.story_flags.has("met_gruff"), "story flags")
	assert_eq(
		int((profile.classes["warrior"] as Dictionary)["xp"]), 340,
		"class xp"
	)
	assert_eq(
		int((profile.classes["warrior"] as Dictionary)["mastery"]), 3,
		"and the mastery the file carried"
	)
	assert_true((profile.codex["relics"] as Array).has("ember_boots"), "codex entries")
	assert_eq(profile.settings.get("screen_shake"), 0.5, "settings")
	assert_eq(
		(profile.settings["audio"] as Dictionary).get("master"), 0.8,
		"including the nested ones"
	)


func test_the_migrated_fixture_reads_back_as_a_profile_with_every_spec_field() -> void:
	# The chain hands back the save; the *reader* is what fills the keys the file
	# never had (SPEC-save-system: "Missing keys get defaults from
	# `PlayerProfile.defaults()`"), so this is the end-to-end claim — fixture
	# through the chain through `from_dict()` is a complete profile.
	var read := PlayerProfile.from_dict(SaveMigrations.migrate(_fixture()).data).to_dict()
	for field: StringName in PlayerProfile.FIELDS:
		assert_true(read.has(field), "the profile has `%s`" % field)
	assert_eq(
		read.size(), PlayerProfile.FIELDS.size(),
		"and exactly the spec's fields — nothing invented, nothing dropped"
	)


func test_the_chain_hands_back_every_key_the_fixture_had() -> void:
	var raw := _fixture()
	var migrated := SaveMigrations.migrate(raw).data
	for key: Variant in raw:
		assert_true(migrated.has(key), "the chain does not drop `%s`" % key)
	assert_eq(
		migrated.size(), raw.size(),
		"and it adds nothing but the version it stamped"
	)


func test_the_migrated_fixture_reads_back_as_a_profile_the_spec_describes() -> void:
	var migrated := SaveMigrations.migrate(_fixture()).data
	var profile := PlayerProfile.from_dict(migrated)
	assert_eq(
		profile.save_version, SaveMigrations.current_version(),
		"the version the reader sees is this build's"
	)
	assert_eq(
		profile.to_dict(), PlayerProfile.from_dict(profile.to_dict()).to_dict(),
		"and the migrated save is stable through another round trip"
	)


## ---------------------------------------------------------------------------
## Missing keys: defaults, with no migration at all
## ---------------------------------------------------------------------------

func test_a_key_the_fixture_never_had_arrives_from_defaults() -> void:
	var defaults := PlayerProfile.defaults()
	var erased: Array[String] = [
		"weapons_unlocked", "potions", "codex", "stats", "settings",
		"skill_tree", "achievements", "deep_mode_unlocked",
	]
	var migrated := SaveMigrations.migrate(_fixture_without(erased)).data
	var profile := PlayerProfile.from_dict(migrated)
	assert_eq(
		profile.weapons_unlocked, defaults.weapons_unlocked,
		"a key the save never had is the default, and no migration was written for it"
	)
	assert_eq(profile.potions, defaults.potions, "each missing key")
	assert_eq(profile.codex, defaults.codex, "all of them")
	assert_eq(profile.stats, defaults.stats, "without exception")
	assert_eq(profile.settings, defaults.settings, "including settings")
	assert_eq(profile.skill_tree, defaults.skill_tree, "and the empty maps")
	assert_eq(profile.deep_mode_unlocked, defaults.deep_mode_unlocked, "and the bools")


func test_every_key_the_fixture_omits_reads_as_the_default() -> void:
	# Driven by the fixture's *actual* omissions rather than a hand-written list,
	# and self-proving: if the fixture ever carried every field, this case would
	# assert nothing and say so.
	var raw := _fixture()
	var read := PlayerProfile.from_dict(SaveMigrations.migrate(raw).data).to_dict()
	var fallback := PlayerProfile.defaults().to_dict()
	var omitted: int = 0
	for field: StringName in PlayerProfile.FIELDS:
		if raw.has(field):
			continue
		omitted += 1
		assert_eq(
			read[field], fallback[field],
			"the fixture omits `%s`, so it reads as the default" % field
		)
	assert_true(omitted > 0, "the fixture really does omit %d keys" % omitted)


func test_a_new_field_arrives_from_defaults_even_when_a_migration_ignores_it() -> void:
	# The spec's sentence is about a *later* build: a migration runs, and a field
	# that build added is not mentioned by it at all. This is that shape, driven
	# through a chain that really ran.
	var recorder := MigrationRecorder.new()
	var raw: Dictionary = {"save_version": 1, "gold_banked": 4}
	var outcome := SaveMigrations.run(raw, 1, 3, recorder.table_for([1, 2]))
	assert_true(outcome.ok(), "the chain ran")
	var profile := PlayerProfile.from_dict(outcome.data)
	assert_eq(
		profile.weapons_unlocked, PlayerProfile.defaults().weapons_unlocked,
		"a field the migrations never mention still arrives from defaults()"
	)
	assert_eq(profile.gold_banked, 4, "and the values the save did carry survive the chain")


## ---------------------------------------------------------------------------
## Order: ascending, one step at a time
## ---------------------------------------------------------------------------

func test_migrations_run_in_ascending_order_one_at_a_time() -> void:
	var recorder := MigrationRecorder.new()
	var raw: Dictionary = {"save_version": 1}
	var outcome := SaveMigrations.run(raw, 1, 4, recorder.table_for([1, 2, 3]))
	assert_true(outcome.ok(), "a chain with every step runs")
	var expected: Array[int] = [1, 2, 3]
	assert_eq(recorder.log, expected, "each step ran once, in ascending version order")
	assert_eq(recorder.stepped_through(outcome.data), 6, "and threaded the data through 1 then 2 then 3")
	assert_eq(outcome.data.get(SaveMigrations.VERSION_KEY), 4, "the result is stamped version 4")


func test_a_migration_table_given_out_of_order_still_steps_ascending() -> void:
	var recorder := MigrationRecorder.new()
	var unordered: Dictionary = recorder.table_for([3, 1, 2])
	var outcome := SaveMigrations.run({"save_version": 1}, 1, 4, unordered)
	var expected: Array[int] = [1, 2, 3]
	assert_eq(recorder.log, expected, "the chain's order is the runner's, not the dictionary's")


func test_a_migration_chain_that_stops_before_the_target_runs_only_its_own_steps() -> void:
	var recorder := MigrationRecorder.new()
	var outcome := SaveMigrations.run({"save_version": 1}, 1, 3, recorder.table_for([1, 2, 3]))
	var expected: Array[int] = [1, 2]
	assert_eq(recorder.log, expected, "the step for version 3 is not run — the target is 3")
	assert_eq(outcome.data.get(SaveMigrations.VERSION_KEY), 3, "and the result is version 3")


func test_a_save_already_at_the_current_version_runs_no_migration() -> void:
	var recorder := MigrationRecorder.new()
	var raw: Dictionary = {"save_version": 2, "gold_banked": 9}
	var outcome := SaveMigrations.run(raw, 2, 2, recorder.table_for([1, 2, 3]))
	assert_true(outcome.ok(), "nothing to do is not a refusal")
	assert_eq(recorder.log.size(), 0, "no step ran")
	assert_eq(int(outcome.data.get("gold_banked")), 9, "and the save is what it was")


## ---------------------------------------------------------------------------
## Refusals: named, and never a silent downgrade
## ---------------------------------------------------------------------------

func test_a_save_from_a_newer_build_is_refused_by_name() -> void:
	var raw: Dictionary = {"save_version": 2, "gold_banked": 9}
	var outcome := SaveMigrations.migrate(raw)
	assert_false(outcome.ok(), "this build does not read a newer save as if it were its own")
	assert_eq(outcome.reason, REFUSAL_TOO_NEW, "and it says so by name")
	assert_eq(int(outcome.data.get("gold_banked")), 9, "the caller gets its own data back, not a stripped copy")


func test_a_version_with_no_migration_is_refused_by_name_and_applies_nothing() -> void:
	var recorder := MigrationRecorder.new()
	var raw: Dictionary = {"save_version": 1, "gold_banked": 9}
	var outcome := SaveMigrations.run(raw, 1, 3, recorder.table_for([1]))
	assert_false(outcome.ok(), "a missing step refuses the whole chain")
	assert_eq(outcome.reason, REFUSAL_NO_MIGRATION, "by name")
	assert_eq(recorder.log.size(), 0, "and no step ran, so the save is never half-migrated")


func test_a_migration_that_does_not_hand_back_an_object_is_refused_by_name() -> void:
	var recorder := MigrationRecorder.new()
	recorder.broken_version = 2
	var raw: Dictionary = {"save_version": 1, "gold_banked": 9}
	var outcome := SaveMigrations.run(raw, 1, 3, recorder.table_for([1, 2]))
	assert_false(outcome.ok(), "a chain that broke mid-way does not produce a save")
	assert_eq(outcome.reason, REFUSAL_NOT_AN_OBJECT, "by name")
	assert_eq(int(outcome.data.get("gold_banked")), 9, "and the caller's save is handed back untouched")


func test_a_refusal_leaves_the_dictionary_it_was_given_alone() -> void:
	var recorder := MigrationRecorder.new()
	var raw: Dictionary = {"save_version": 1, "gold_banked": 9}
	var before: Dictionary = raw.duplicate(true)
	SaveMigrations.run(raw, 1, 3, recorder.table_for([1]))
	SaveMigrations.run({"save_version": 99}, 99, 1, recorder.table_for([1]))
	assert_eq(raw, before, "a refused migration never edits the save it was handed")


## ---------------------------------------------------------------------------
## load(): the reader SPEC-save-system puts these on startup
## ---------------------------------------------------------------------------

func test_load_reads_the_v1_fixture_off_disk() -> void:
	_write_text(SAVE_PATH, _fixture_text())
	SaveManager.loaded.connect(_on_loaded)
	SaveManager.load()
	assert_eq(SaveManager.load_refusal, &"", "a version-1 save loads with no refusal")
	assert_not_null(SaveManager.profile, "and there is a profile")
	assert_eq(SaveManager.profile.gold_banked, 137, "carrying the file's values")
	assert_eq(SaveManager.profile.ore_count(&"iron"), 3, "all of them")
	assert_eq(
		SaveManager.profile.save_version, SaveManager.SAVE_VERSION,
		"stamped with this build's version"
	)
	assert_eq(_loaded.size(), 1, "`loaded` was announced once")
	assert_eq(_loaded[0], SaveManager.profile, "with the profile that was read")


func test_load_refuses_a_newer_save_by_name_and_leaves_it_on_disk() -> void:
	var text := JSON.stringify({"save_version": 99, "gold_banked": 12345})
	_write_text(SAVE_PATH, text)
	var before := FileAccess.get_file_as_bytes(SAVE_PATH)
	SaveManager.load()
	assert_eq(SaveManager.load_refusal, REFUSAL_TOO_NEW, "the refusal is named on the manager")
	assert_eq(
		SaveManager.profile.to_dict(), PlayerProfile.defaults().to_dict(),
		"and the running profile is a fresh one rather than a mis-read save"
	)
	assert_eq(
		FileAccess.get_file_as_bytes(SAVE_PATH), before,
		"the newer build's file is left byte for byte as it was"
	)


func test_load_with_no_save_file_starts_fresh() -> void:
	assert_false(FileAccess.file_exists(SAVE_PATH), "there is no save to read")
	SaveManager.load()
	assert_eq(
		SaveManager.profile.to_dict(), PlayerProfile.defaults().to_dict(),
		"a machine with no save starts on a fresh profile"
	)
	assert_eq(SaveManager.load_refusal, &"", "and that is not a refusal")


func test_load_reports_a_file_that_is_not_json_by_name() -> void:
	_write_text(SAVE_PATH, "{ truncated half a fi")
	SaveManager.load()
	assert_eq(
		SaveManager.load_refusal, REFUSAL_CORRUPT,
		"a file that is not a JSON object is named (G5 adds the .bak chain behind this)"
	)
	assert_eq(
		SaveManager.profile.to_dict(), PlayerProfile.defaults().to_dict(),
		"and a corrupt file never becomes a half-read profile"
	)


func test_load_clears_a_previous_refusal() -> void:
	_write_text(SAVE_PATH, "not json")
	SaveManager.load()
	assert_eq(SaveManager.load_refusal, REFUSAL_CORRUPT, "the first load refused")
	_write_text(SAVE_PATH, _fixture_text())
	SaveManager.load()
	assert_eq(SaveManager.load_refusal, &"", "a load that worked clears the reason from the last one")


func test_a_missing_version_key_reads_as_the_current_version() -> void:
	var raw: Dictionary = {"gold_banked": 6}
	assert_eq(
		SaveMigrations.version_of(raw), SaveMigrations.current_version(),
		"a save with no version key is this build's, per the spec's missing-key rule"
	)
	assert_true(SaveMigrations.migrate(raw).ok(), "so it is not refused as a newer or older file")
