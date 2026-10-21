extends GutTest
## `SaveManager.load()`'s third failure path — save-system, W5-B1 (PLAN G5).
##
## SPEC-save-system, "Loading and migration": "If parse fails, load `save.bak`; if
## that fails, start fresh and keep the corrupt file as `save.corrupt.<timestamp>`."
## And its own test row: "Unit `test_save_recovery.gd`: corrupt file falls back to
## `.bak`; missing file starts fresh; settings survive `reset_profile`."
##
## Four claims, kept apart because they fail for different reasons:
##
##   1. **a corrupt `save.json` falls back to `.bak`** and the profile the backup
##      holds is the one that loads — the save a crash mid-write would have left
##      behind is the one the player gets back;
##   2. **a missing `save.json` starts fresh** — a new machine, not a refusal,
##      because the refusal vocabulary is for files that exist and cannot be used;
##   3. **the corrupt file is kept** as `user://save.corrupt.<timestamp>` with its
##      bytes intact and a stamp that is a real time, so a player's broken save is
##      still there to look at;
##   4. **the settings survive `reset_profile()`** (the spec's own third clause).
##
## Plus the two states the spec leaves to this module's judgement, pinned because
## they are the ones that could destroy data: a save from a **newer build** is
## refused and left exactly where it is (never filed as corrupt, never renamed),
## and a recovery **writes nothing** — a load that repaired a file by writing over
## the backup would be a bug that only shows up after the second launch.
##
## Every case runs against the real files under `user://` through
## `SaveFileFixture`, so the suite never eats a real save.
##
## Owned by save-system. Sync: none — a local file per machine; the host never
## writes a client's profile.

## The refusal names, spelled out as the literal strings a reader sees in a log,
## so renaming one in the class is a failing case and not a silent pass.
const REFUSAL_TOO_NEW: StringName = &"save_is_from_a_newer_build"
const REFUSAL_CORRUPT: StringName = &"save_file_is_not_a_json_object"

## A file that is not JSON at all — the shape a crash mid-write leaves.
const TRUNCATED: String = "{ \"save_version\": 1, \"gold_banked\": 12, \"ora"

## Every profile a case loaded, in load order, from the `loaded` signal.
var _loaded: Array[PlayerProfile] = []
## How many times `saved` fired during the case — a load must never write.
var _saved_count: int = 0
## The files as they were before the case ran, handed back in `after_each`.
var _existing: Dictionary[String, PackedByteArray] = {}
## The corrupt files that existed before the case ran; the case's own are removed.
var _corrupt_before: Array[String] = []
## Every manager this case put in the tree, so each one is freed rather than left.
var _managers: Array[CountingSaveManager] = []


func before_each() -> void:
	_loaded.clear()
	_saved_count = 0
	_corrupt_before = SaveFileFixture.corrupt_files()
	_existing = SaveFileFixture.snapshot()
	SaveFileFixture.clear_live()
	SaveManager.profile = null
	if not SaveManager.loaded.is_connected(_on_loaded):
		SaveManager.loaded.connect(_on_loaded)
	if not SaveManager.saved.is_connected(_on_saved):
		SaveManager.saved.connect(_on_saved)


func after_each() -> void:
	if SaveManager.loaded.is_connected(_on_loaded):
		SaveManager.loaded.disconnect(_on_loaded)
	if SaveManager.saved.is_connected(_on_saved):
		SaveManager.saved.disconnect(_on_saved)
	await wait_process_frames(1)
	for manager: CountingSaveManager in _managers:
		if is_instance_valid(manager):
			manager.free()
	_managers.clear()
	SaveFileFixture.restore(_existing)
	SaveFileFixture.remove_corrupt_files_except(_corrupt_before)
	SaveManager.profile = null


func _on_loaded(profile: PlayerProfile) -> void:
	_loaded.append(profile)


func _on_saved() -> void:
	_saved_count += 1


## A manager added to the tree and left to start on its own: `add_child` runs the
## shipped `_ready()`, which is the startup path a relaunch takes. No profile is
## set here — reading one is the whole point.
func _start_a_manager() -> CountingSaveManager:
	var manager := CountingSaveManager.new()
	add_child(manager)
	_managers.append(manager)
	return manager


## Writes the two files a recovery needs: a good save at `PATH` holding `gold`,
## and the previous good save at `BACKUP_PATH`. Done through a real manager, so
## the file the case breaks is one the module itself wrote.
func _write_a_save_then_another(gold_kept: int, gold_current: int) -> void:
	var manager := _start_a_manager()
	manager.profile = PlayerProfile.defaults()
	manager.profile.gold_banked = gold_kept
	manager.profile.ore["iron"] = 4
	manager.save()
	await wait_process_frames(2)
	manager.profile.gold_banked = gold_current
	manager.profile.ore["iron"] = 9
	manager.save()
	await wait_process_frames(2)
	assert_eq(
		SaveFileFixture.profile_at(SaveFileFixture.BACKUP_PATH).gold_banked, gold_kept,
		"the case is set up: the backup holds the earlier save"
	)
	assert_eq(
		SaveFileFixture.profile_at(SaveFileFixture.SAVE_PATH).gold_banked, gold_current,
		"and the path holds the later one"
	)


## ---------------------------------------------------------------------------
## 1. A corrupt save falls back to the backup
## ---------------------------------------------------------------------------

func test_a_corrupt_save_falls_back_to_the_backup() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	SaveManager.load()
	assert_not_null(SaveManager.profile, "the load leaves a profile")
	assert_eq(SaveManager.profile.gold_banked, 30, "and it is the backup's save, not the current one")
	assert_eq(SaveManager.profile.ore_count(&"iron"), 4, "with every value the backup held")
	assert_true(SaveManager.recovered_from_backup, "the recovery says where the profile came from")
	assert_eq(
		SaveManager.load_refusal, REFUSAL_CORRUPT,
		"and names why the file at the path was not used"
	)


func test_json_that_is_not_an_object_is_corrupt_too() -> void:
	await _write_a_save_then_another(30, 60)
	# Valid JSON, and still not a save: the module's rule is "a JSON object", so
	# an array or a bare string is the same failure as a truncated file.
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, "[1, 2, 3]")
	SaveManager.load()
	assert_eq(SaveManager.profile.gold_banked, 30, "the backup's profile still loads")
	assert_eq(SaveManager.load_refusal, REFUSAL_CORRUPT, "and the file is refused by the same name")


func test_a_corrupt_save_with_no_backup_starts_fresh() -> void:
	var manager := _start_a_manager()
	manager.profile = PlayerProfile.defaults()
	manager.profile.gold_banked = 60
	manager.save()
	await wait_process_frames(2)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	SaveManager.load()
	assert_eq(
		SaveManager.profile.to_dict(), PlayerProfile.defaults().to_dict(),
		"nothing left to fall back to, so the player starts a new game"
	)
	assert_eq(SaveManager.load_refusal, REFUSAL_CORRUPT, "with the reason still named")
	assert_false(SaveManager.recovered_from_backup, "and no claim that a backup was used")


func test_a_corrupt_backup_is_kept_too_when_neither_file_can_be_read() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	SaveFileFixture.write_text(SaveFileFixture.BACKUP_PATH, "\"not a save either\"")
	SaveManager.load()
	assert_eq(
		SaveManager.profile.to_dict(), PlayerProfile.defaults().to_dict(),
		"two unreadable files start a fresh game"
	)
	assert_eq(SaveManager.corrupt_files_kept.size(), 2, "and neither unreadable file is thrown away")
	assert_false(SaveManager.recovered_from_backup, "no profile came from the backup")


## ---------------------------------------------------------------------------
## 2. A missing save starts fresh
## ---------------------------------------------------------------------------

func test_a_missing_save_starts_fresh() -> void:
	SaveManager.load()
	assert_not_null(SaveManager.profile, "a machine with no save still gets a profile")
	assert_eq(
		SaveManager.profile.to_dict(), PlayerProfile.defaults().to_dict(),
		"and it is a fresh one"
	)
	assert_eq(SaveManager.load_refusal, &"", "a new game is not a refusal — there was no file to refuse")
	assert_false(SaveManager.recovered_from_backup, "and no backup was involved")
	assert_true(SaveManager.corrupt_files_kept.is_empty(), "nothing was kept")
	assert_false(SaveFileFixture.exists(SaveFileFixture.SAVE_PATH), "and a load creates no file")


## A recovery *moves* the unreadable file aside, so the launch after it finds an
## empty path with the town still sitting in `save.bak`. Starting a new game over
## it would lose a save that is on disk and readable, which is the one thing this
## module exists to prevent — so the backup is consulted whenever `PATH` yields no
## profile, and this case is the launch-after-a-recovery.
func test_a_missing_save_with_a_backup_loads_the_backup() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.remove(SaveFileFixture.SAVE_PATH)
	SaveManager.load()
	assert_eq(SaveManager.profile.gold_banked, 30, "a backup with no file beside it is still a save")
	assert_true(SaveManager.recovered_from_backup, "reported as a recovery")
	assert_eq(
		SaveManager.load_refusal, &"", "and there is no refusal: no file was found at the path to refuse"
	)
	assert_true(SaveManager.corrupt_files_kept.is_empty(), "no file was unreadable, so nothing was kept")
	SaveManager.profile = null
	SaveManager.load()
	assert_eq(
		SaveManager.profile.gold_banked, 30, "a second launch on the same broken state recovers again"
	)
	assert_true(SaveManager.recovered_from_backup, "rather than starting over a town that is on disk")


## ---------------------------------------------------------------------------
## 3. The corrupt file is kept as `save.corrupt.<timestamp>`
## ---------------------------------------------------------------------------

func test_a_corrupt_save_is_kept_as_a_corrupt_file() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	SaveManager.load()
	assert_eq(SaveManager.corrupt_files_kept.size(), 1, "exactly one file was kept")
	var kept: String = SaveManager.corrupt_files_kept[0]
	assert_true(kept.begins_with(SaveFileFixture.CORRUPT_PREFIX), "under `save.corrupt.` in `user://`")
	assert_true(SaveFileFixture.exists(kept), "and it is really on disk")
	assert_eq(SaveFileFixture.text_at(kept), TRUNCATED, "with the bytes that could not be read")
	assert_false(
		SaveFileFixture.exists(SaveFileFixture.SAVE_PATH),
		"the unreadable file does not stay where it would be read again"
	)
	assert_eq(
		SaveFileFixture.profile_at(SaveFileFixture.BACKUP_PATH).gold_banked, 30,
		"and the backup is left alone"
	)


func test_the_kept_corrupt_name_carries_a_real_timestamp() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	SaveManager.load()
	assert_eq(SaveManager.corrupt_files_kept.size(), 1, "the case is set up")
	var stamp: String = SaveManager.corrupt_files_kept[0].trim_prefix(SaveFileFixture.CORRUPT_PREFIX).split(".")[0]
	var pieces: PackedStringArray = stamp.split("T")
	assert_eq(pieces.size(), 2, "`save.corrupt.<date>T<time>`, so a folder of them sorts by time")
	if pieces.size() != 2:
		return
	var clock: String = pieces[1]
	assert_eq(clock.length(), 6, "the time is HHMMSS — no colon, which a Windows path cannot hold")
	if clock.length() != 6:
		return
	var interpreted: int = Time.get_unix_time_from_datetime_string(
		"%sT%s:%s:%s" % [pieces[0], clock.substr(0, 2), clock.substr(2, 2), clock.substr(4, 2)]
	)
	assert_gt(interpreted, 0, "the stamp is a real date, not a placeholder")
	assert_almost_eq(
		float(interpreted), Time.get_unix_time_from_system(), 120.0,
		"and it is the clock at the moment of recovery (UTC, so it also parses back)"
	)


func test_two_corrupt_saves_in_the_same_second_both_survive() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	SaveManager.load()
	assert_eq(SaveManager.corrupt_files_kept.size(), 1, "the case is set up")
	var first: String = SaveManager.corrupt_files_kept[0]
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, "\"a different broken save\"")
	SaveManager.load()
	assert_eq(SaveManager.corrupt_files_kept.size(), 1, "the second recovery keeps its own file")
	var second: String = SaveManager.corrupt_files_kept[0]
	assert_ne(second, first, "and a second keep does not overwrite the first")
	assert_eq(SaveFileFixture.text_at(first), TRUNCATED, "the first file still holds its own bytes")
	assert_eq(
		SaveFileFixture.text_at(second), "\"a different broken save\"",
		"and the second holds its own"
	)


## ---------------------------------------------------------------------------
## The two states a recovery must never destroy
## ---------------------------------------------------------------------------

func test_a_save_from_a_newer_build_is_refused_and_left_where_it_is() -> void:
	var newer: String = "{\n\t\"save_version\": 99,\n\t\"gold_banked\": 5\n}"
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, newer)
	SaveManager.load()
	assert_eq(SaveManager.load_refusal, REFUSAL_TOO_NEW, "a newer build's save is refused by name")
	assert_eq(
		SaveManager.profile.to_dict(), PlayerProfile.defaults().to_dict(),
		"and this build does not pretend to read it"
	)
	assert_true(
		SaveManager.corrupt_files_kept.is_empty(),
		"a save this build is too old for is not filed as corrupt"
	)
	assert_eq(
		SaveFileFixture.text_at(SaveFileFixture.SAVE_PATH), newer,
		"and it is left byte for byte where it was, so the newer build still works"
	)


func test_a_good_save_beside_a_corrupt_backup_is_used_as_it_is() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.BACKUP_PATH, TRUNCATED)
	SaveManager.load()
	assert_eq(SaveManager.profile.gold_banked, 60, "the file at the path is the save")
	assert_eq(SaveManager.load_refusal, &"", "so there is no refusal to report")
	assert_true(SaveManager.corrupt_files_kept.is_empty(), "and the backup is not touched, let alone kept")
	assert_eq(
		SaveFileFixture.text_at(SaveFileFixture.BACKUP_PATH), TRUNCATED,
		"it is still exactly as it was found"
	)


func test_recovery_writes_nothing() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	var backup_before: PackedByteArray = SaveFileFixture.bytes_at(SaveFileFixture.BACKUP_PATH)
	SaveManager.load()
	assert_eq(_saved_count, 0, "a load never writes the profile back")
	assert_false(
		SaveFileFixture.exists(SaveFileFixture.TMP_PATH),
		"and does not leave a tmp file behind"
	)
	assert_eq(
		SaveFileFixture.bytes_at(SaveFileFixture.BACKUP_PATH), backup_before,
		"the backup a recovery just used is still the file the next launch will use"
	)


func test_recovery_announces_the_profile_it_loaded() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	SaveManager.load()
	assert_eq(_loaded.size(), 1, "`loaded` fires once per load")
	assert_eq(_loaded[0], SaveManager.profile, "with the profile the manager now holds")
	assert_eq(_loaded[0].gold_banked, 30, "which is the recovered one")


## ---------------------------------------------------------------------------
## The startup path a relaunch takes
## ---------------------------------------------------------------------------

func test_a_manager_that_starts_up_reads_the_file() -> void:
	var writer := _start_a_manager()
	writer.profile = PlayerProfile.defaults()
	writer.profile.gold_banked = 1234
	writer.profile.story_flags.append("act_2")
	writer.save()
	await wait_process_frames(2)
	var restarted := _start_a_manager()
	assert_not_null(restarted.profile, "a manager that starts in the tree reads the save by itself")
	assert_eq(restarted.profile.gold_banked, 1234, "and holds what was written")
	assert_eq(restarted.profile.story_flags, ["act_2"] as Array[String], "including the lists")
	assert_eq(restarted.load_refusal, &"", "with nothing to refuse")


func test_a_manager_that_starts_up_on_a_corrupt_save_recovers_too() -> void:
	await _write_a_save_then_another(30, 60)
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)
	var restarted := _start_a_manager()
	assert_eq(restarted.profile.gold_banked, 30, "a restart recovers the same way a manual load does")
	assert_true(restarted.recovered_from_backup, "and says so")
	assert_eq(restarted.corrupt_files_kept.size(), 1, "keeping the file it could not read")


## ---------------------------------------------------------------------------
## The spec's third clause: settings survive a reset
## ---------------------------------------------------------------------------

func test_settings_survive_reset_profile() -> void:
	var manager := _start_a_manager()
	manager.profile = PlayerProfile.defaults()
	manager.profile.settings[PlayerProfile.SETTINGS_SCREEN_SHAKE] = 0.25
	manager.profile.settings["audio"] = {"master": 0.5}
	manager.profile.gold_banked = 500
	manager.reset_profile()
	assert_eq(
		manager.profile.settings[PlayerProfile.SETTINGS_SCREEN_SHAKE], 0.25,
		"a new game keeps the screen shake the player chose"
	)
	assert_eq(
		(manager.profile.settings["audio"] as Dictionary).get("master"), 0.5,
		"and the audio volumes"
	)
	assert_eq(manager.profile.gold_banked, 0, "while the currencies are a new game's")
