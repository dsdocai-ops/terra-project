extends GutTest
## `SaveManager`'s write path — the debounced, atomic save — save-system, W5-B1
## (PLAN G3).
##
## SPEC-save-system, "When it saves": "Debounced: multiple calls within one frame
## write once. Writes are atomic: write to `user://save.json.tmp`, then rename
## over `user://save.json`. Keep `user://save.bak` from the previous successful
## save." And "Interfaces provided": `save()` (debounced, atomic),
## `reset_profile()` ("new game, keeps settings") and `export_debug()` ("JSON for
## debug console").
##
## Every case runs against the real files under `user://`, because that is the
## path the spec names and the one a crash would have to survive. The three files
## are snapshotted before and restored after each case, so the suite never eats a
## real save. The two internal seams the spec names — the tmp file existing at the
## moment it is promoted, and a write that cannot start — are observed through
## `CountingSaveManager`, a double that counts the writes instead of guessing them
## from a clock.
##
## Owned by save-system. Sync: none — a local file per machine; the host never
## writes a client's profile.

## The paths SPEC-save-system names, spelled out here rather than read off the
## class, so a rename in the class is a failing case and not a silent pass.
const SAVE_PATH: String = "user://save.json"
const TMP_PATH: String = "user://save.json.tmp"
const BACKUP_PATH: String = "user://save.bak"

## Every file a case may touch, so the snapshot covers all three.
const FILES: Array[String] = [SAVE_PATH, TMP_PATH, BACKUP_PATH]

## How many `saved` signals the case under test observed.
var _saved_count: int = 0
## The bytes of each of the three files as they were before the case ran.
var _existing: Dictionary[String, PackedByteArray] = {}
## Every double this case made, so each one is freed rather than left in the tree.
var _managers: Array[CountingSaveManager] = []


func before_each() -> void:
	_existing.clear()
	_managers.clear()
	for path: String in FILES:
		if FileAccess.file_exists(path):
			_existing[path] = FileAccess.get_file_as_bytes(path)
			_remove(path)
	SaveManager.profile = null
	_saved_count = 0


func after_each() -> void:
	# Drain any write the case left queued before cleaning up, or it would land
	# after the restore and leave a stray file behind for the next test file.
	await wait_process_frames(2)
	for manager: CountingSaveManager in _managers:
		if is_instance_valid(manager):
			manager.free()
	_managers.clear()
	for path: String in FILES:
		_remove(path)
	for path: String in _existing:
		_write_bytes(path, _existing[path])
	_existing.clear()
	SaveManager.profile = null


## A fresh double, in the tree so `_exit_tree()` can be observed, holding a
## default profile unless the case sets its own.
func _make() -> CountingSaveManager:
	var manager := CountingSaveManager.new()
	add_child(manager)
	manager.profile = PlayerProfile.defaults()
	_managers.append(manager)
	return manager


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


## The JSON object at `path` as a `Dictionary`, `{}` when the file is missing or
## is not a JSON object. The parse is the point: a half-written file returns `{}`.
func _json_at(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if json.data is Dictionary:
		return json.data as Dictionary
	return {}


## The profile a file holds, rebuilt through the class's own reader.
func _profile_at(path: String) -> PlayerProfile:
	return PlayerProfile.from_dict(_json_at(path))


func _on_saved() -> void:
	_saved_count += 1


## ---------------------------------------------------------------------------
## The paths the spec names
## ---------------------------------------------------------------------------

func test_the_class_names_the_three_paths_the_spec_names() -> void:
	assert_eq(SaveManager.PATH, SAVE_PATH, "SPEC: `user://save.json`")
	assert_eq(SaveManager.TMP_PATH, TMP_PATH, "SPEC: the write goes through `user://save.json.tmp`")
	assert_eq(SaveManager.BACKUP_PATH, BACKUP_PATH, "SPEC: `user://save.bak` from the previous save")
	assert_eq(SaveManager.SAVE_VERSION, 1, "the schema stays at 1 for week 5 (BRIEF A5)")


## ---------------------------------------------------------------------------
## Debounce: one frame is one write
## ---------------------------------------------------------------------------

func test_many_saves_in_one_frame_write_once() -> void:
	var manager := _make()
	for i: int in 50:
		manager.save()
	assert_eq(manager.write_count, 0, "the write is deferred to the end of the frame, not run inline")
	await wait_process_frames(2)
	assert_eq(manager.write_count, 1, "50 calls in one frame are one write")
	assert_true(FileAccess.file_exists(SAVE_PATH), "and that one write landed")


func test_the_shipped_singleton_writes_once_per_frame_and_says_so() -> void:
	SaveManager.profile = PlayerProfile.defaults()
	SaveManager.saved.connect(_on_saved)
	for i: int in 25:
		SaveManager.save()
	await wait_process_frames(2)
	SaveManager.saved.disconnect(_on_saved)
	assert_eq(_saved_count, 1, "25 calls in one frame emit `saved` once")
	assert_eq(_json_at(SAVE_PATH).get("save_version"), 1.0, "and the file on disk is this profile")


func test_a_later_frame_with_a_call_writes_again() -> void:
	var manager := _make()
	manager.save()
	await wait_process_frames(2)
	assert_eq(manager.write_count, 1, "the first frame wrote once")
	manager.save()
	await wait_process_frames(2)
	assert_eq(manager.write_count, 2, "a call in the next frame is a second write")


func test_a_frame_with_no_call_writes_nothing() -> void:
	var manager := _make()
	manager.save()
	await wait_process_frames(2)
	await wait_process_frames(3)
	assert_eq(manager.write_count, 1, "the debounce does not write on its own")


func test_the_coalesced_write_carries_the_final_state() -> void:
	var manager := _make()
	manager.profile.gold_banked = 1
	manager.save()
	manager.profile.gold_banked = 42
	manager.save()
	await wait_process_frames(2)
	assert_eq(manager.write_count, 1, "still one write")
	assert_eq(_profile_at(SAVE_PATH).gold_banked, 42, "the frame's write is the state at the end of the frame")


func test_a_save_with_no_profile_writes_nothing() -> void:
	var manager := _make()
	manager.profile = null
	manager.save()
	await wait_process_frames(2)
	assert_eq(manager.write_count, 0, "nothing to write, so nothing is written")
	assert_false(FileAccess.file_exists(SAVE_PATH), "and no file is created")


func test_a_pending_save_is_flushed_when_the_manager_leaves_the_tree() -> void:
	var manager := _make()
	manager.save()
	assert_eq(manager.write_count, 0, "deferred, nothing yet")
	remove_child(manager)
	assert_eq(manager.write_count, 1, "quitting with a pending save flushes it")
	await wait_process_frames(2)
	assert_eq(manager.write_count, 1, "and the queued flush does not write it a second time")
	manager.free()


## ---------------------------------------------------------------------------
## Atomicity: tmp, rename, backup
## ---------------------------------------------------------------------------

func test_a_completed_save_leaves_valid_json_at_the_path() -> void:
	var manager := _make()
	manager.profile.gold_banked = 12
	manager.profile.ore["copper"] = 3
	manager.save()
	await wait_process_frames(2)
	assert_true(FileAccess.file_exists(SAVE_PATH), "the save file exists")
	assert_eq(
		_profile_at(SAVE_PATH).to_dict(), manager.profile.to_dict(),
		"and it reads back as the profile that was saved"
	)


func test_the_write_goes_through_the_tmp_path_then_a_rename() -> void:
	var manager := _make()
	manager.save()
	await wait_process_frames(2)
	assert_eq(manager.promote_count, 1, "the tmp file is promoted exactly once")
	assert_true(manager.tmp_existed_at_promote, "the data went through `user://save.json.tmp` first")
	assert_true(manager.tmp_gone_after_promote, "and the promotion moved it rather than copying it")


func test_no_tmp_file_survives_a_successful_save() -> void:
	var manager := _make()
	manager.save()
	await wait_process_frames(2)
	assert_false(FileAccess.file_exists(TMP_PATH), "the tmp file is gone once the save succeeded")
	assert_true(FileAccess.file_exists(SAVE_PATH), "and the save file is there")


func test_the_previous_good_save_is_kept_at_the_backup_path() -> void:
	var manager := _make()
	manager.profile.gold_banked = 10
	manager.save()
	await wait_process_frames(2)
	assert_false(FileAccess.file_exists(BACKUP_PATH), "the first save has no previous file to keep")
	manager.profile.gold_banked = 20
	manager.save()
	await wait_process_frames(2)
	assert_eq(_profile_at(SAVE_PATH).gold_banked, 20, "the new save is at the path")
	assert_eq(_profile_at(BACKUP_PATH).gold_banked, 10, "and the previous good save is at the backup")


func test_a_corrupt_save_is_not_rolled_into_the_backup() -> void:
	var manager := _make()
	manager.profile.gold_banked = 10
	manager.save()
	await wait_process_frames(2)
	manager.profile.gold_banked = 20
	manager.save()
	await wait_process_frames(2)
	assert_eq(_profile_at(BACKUP_PATH).gold_banked, 10, "the backup holds the last good save")
	_write_text(SAVE_PATH, "{ truncated half a fi")
	manager.profile.gold_banked = 30
	manager.save()
	await wait_process_frames(2)
	assert_eq(_profile_at(SAVE_PATH).gold_banked, 30, "the new save landed")
	assert_eq(
		_profile_at(BACKUP_PATH).gold_banked, 10,
		"and the backup still holds the last *good* save, not the corrupt one"
	)


func test_a_tmp_file_that_did_not_land_intact_is_never_promoted() -> void:
	var manager := _make()
	manager.profile.gold_banked = 10
	manager.save()
	await wait_process_frames(2)
	var writes := manager.write_count
	var promotions := manager.promote_count
	manager.corrupt_tmp_write = true
	manager.profile.gold_banked = 99
	manager.saved.connect(_on_saved)
	manager.save()
	await wait_process_frames(2)
	manager.saved.disconnect(_on_saved)
	assert_eq(manager.write_count, writes + 1, "the write ran")
	assert_eq(manager.promote_count, promotions, "but a tmp file that does not parse is not promoted")
	assert_eq(_profile_at(SAVE_PATH).gold_banked, 10, "so the previous save is untouched")
	assert_eq(_saved_count, 0, "and no `saved` is announced for a write that did not land")


func test_a_write_that_cannot_start_leaves_the_previous_save_intact() -> void:
	var manager := _make()
	manager.profile.gold_banked = 10
	manager.save()
	await wait_process_frames(2)
	var promotions := manager.promote_count
	manager.fail_tmp_write = true
	manager.profile.gold_banked = 99
	manager.save()
	await wait_process_frames(2)
	assert_eq(manager.promote_count, promotions, "nothing is promoted when the tmp write failed")
	assert_eq(_profile_at(SAVE_PATH).gold_banked, 10, "the previous save survives a write that could not start")
	assert_eq(_profile_at(BACKUP_PATH).gold_banked, 0, "and the backup is not touched either")


func test_a_save_stamps_the_timestamps_the_spec_gives_this_module() -> void:
	var manager := _make()
	assert_eq(manager.profile.created_at, "", "a fresh profile has no clock on it yet")
	manager.save()
	await wait_process_frames(2)
	var written := _profile_at(SAVE_PATH)
	assert_ne(written.created_at, "", "the write stamps `created_at`")
	assert_ne(written.last_saved_at, "", "and `last_saved_at`")
	assert_eq(written.created_at, manager.profile.created_at, "and the live profile agrees with the file")


## ---------------------------------------------------------------------------
## reset_profile: defaults, keeping the settings
## ---------------------------------------------------------------------------

func test_reset_profile_yields_a_default_profile() -> void:
	var manager := _make()
	manager.profile.gold_banked = 500
	manager.profile.echo_shards = 12
	manager.profile.ore["iron"] = 4
	manager.profile.story_flags.append("act_2")
	manager.reset_profile()
	var expected := PlayerProfile.defaults()
	expected.settings = manager.profile.settings.duplicate(true)
	assert_eq(manager.profile.to_dict(), expected.to_dict(), "everything but the settings is a fresh profile")


func test_reset_profile_keeps_the_previous_settings() -> void:
	var manager := _make()
	manager.profile.gold_banked = 500
	manager.profile.settings[PlayerProfile.SETTINGS_SCREEN_SHAKE] = 0.25
	manager.profile.settings["audio"] = {"master": 0.5}
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


func test_reset_profile_with_no_profile_still_yields_defaults() -> void:
	var manager := _make()
	manager.profile = null
	manager.reset_profile()
	assert_not_null(manager.profile, "a reset always leaves a profile")
	assert_eq(manager.profile.to_dict(), PlayerProfile.defaults().to_dict(), "and it is a fresh one")


func test_reset_profile_schedules_a_save() -> void:
	var manager := _make()
	manager.profile.gold_banked = 500
	manager.reset_profile()
	await wait_process_frames(2)
	assert_eq(manager.write_count, 1, "a reset is written once, like any other save")
	assert_eq(_profile_at(SAVE_PATH).gold_banked, 0, "and the file on disk is the new game")


## ---------------------------------------------------------------------------
## export_debug: parseable JSON of the live profile
## ---------------------------------------------------------------------------

func test_export_debug_is_parseable_json_of_the_live_profile() -> void:
	var manager := _make()
	manager.profile.gold_banked = 7
	manager.profile.ore["pearl"] = 2
	var parsed: Variant = JSON.parse_string(manager.export_debug())
	assert_true(parsed is Dictionary, "export_debug() returns JSON that parses to an object")
	if not parsed is Dictionary:
		return
	assert_eq(
		PlayerProfile.from_dict(parsed as Dictionary).to_dict(), manager.profile.to_dict(),
		"and it is the live profile"
	)


func test_export_debug_does_not_stamp_the_timestamps() -> void:
	var manager := _make()
	manager.export_debug()
	assert_eq(manager.profile.created_at, "", "reading the profile for debug does not write to it")
	assert_eq(manager.profile.last_saved_at, "", "and does not claim a save happened")


func test_export_debug_with_no_profile_is_still_parseable() -> void:
	var manager := _make()
	manager.profile = null
	var parsed: Variant = JSON.parse_string(manager.export_debug())
	assert_true(parsed is Dictionary, "a manager with no profile still returns JSON")
	if not parsed is Dictionary:
		return
	assert_true((parsed as Dictionary).is_empty(), "and it is an empty object rather than a half one")
