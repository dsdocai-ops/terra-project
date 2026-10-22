extends GutTest
## A save survives a restart — save-system, W5-B1 (PLAN G5).
##
## SPEC-save-system's own integration row: "save, quit, relaunch headless, profile
## equal." Nothing in-process can prove that sentence: a profile that stayed in
## memory would pass every unit case in this repo, so this file launches a
## **second Godot process** headless (`tests/fixtures/save_relaunch_probe.tscn`)
## and compares the profile *that* process read with the one this one wrote.
##
## Three cases, and the second two exist because a single happy path is not
## evidence:
##
##   1. **the save survives** — a profile with distinctive values is written, the
##      manager is taken out of the tree with the write still queued (the shipped
##      quit path: SPEC-save-system's "`ui-hud` … on quit"), and the relaunched
##      process reads back exactly what was written. The child's process id is
##      asserted to differ from this one's, so "relaunched" is a measurement
##      rather than a claim.
##   2. **the negative control** — with no save on disk the same probe reports a
##      fresh profile, so case 1 cannot pass by reading something of its own.
##   3. **a corrupt save is recovered by the next launch** — the unit suite proves
##      the recovery rule in-process; this proves it on a real restart, which is
##      when a player would meet it.
##
## Every case leaves the three files as it found them (`SaveFileFixture`), so the
## suite never eats a real save.
##
## Owned by save-system. Sync: none — a local file per machine; the host never
## writes a client's profile.

## The probe scene and the prefix it prints its payload under.
const PROBE_SCENE: String = "res://tests/fixtures/save_relaunch_probe.tscn"
const MARKER: String = "SAVE_RELAUNCH_PROBE"

## A backstop for the child process: the probe quits itself on its own first
## frame, so this only ever fires when the probe **could not get that far** — an
## error in a `_ready()` it shares with the shipped autoload. Measured, not
## guessed: pointed at the previous revision of `save_manager.gd` (no
## `recovered_from_backup`), the probe errored on the missing property, never
## reached its own `get_tree().quit()`, and `OS.execute()` below blocked until the
## child was killed by hand — a suite that hangs instead of failing is worse than
## one that fails, because nothing in a log says why. The frame count is far more
## than the one frame the probe needs.
const CHILD_FRAME_BACKSTOP: int = 600

## The refusal name SPEC-save-system's recovery leaves on the manager, spelled out
## here as the literal a reader sees in a log.
const REFUSAL_CORRUPT: String = "save_file_is_not_a_json_object"

## A file that is not JSON at all — the shape a crash mid-write leaves.
const TRUNCATED: String = "{ \"save_version\": 1, \"gold_banked\": 12, \"ora"

## The distinctive currency the "survives" case is built on, asserted against
## this literal so a comparison of two empty profiles cannot pass.
const GOLD: int = 4321

var _existing: Dictionary[String, PackedByteArray] = {}
var _corrupt_before: Array[String] = []
var _managers: Array[CountingSaveManager] = []


func before_each() -> void:
	_corrupt_before = SaveFileFixture.corrupt_files()
	_existing = SaveFileFixture.snapshot()
	SaveFileFixture.clear_live()
	SaveManager.profile = null


func after_each() -> void:
	await wait_process_frames(1)
	for manager: CountingSaveManager in _managers:
		if is_instance_valid(manager):
			manager.free()
	_managers.clear()
	SaveFileFixture.restore(_existing)
	SaveFileFixture.remove_corrupt_files_except(_corrupt_before)
	SaveManager.profile = null


func _start_a_manager() -> CountingSaveManager:
	var manager := CountingSaveManager.new()
	add_child(manager)
	_managers.append(manager)
	return manager


## A profile whose every field is set to something no default holds, so "equal"
## is a claim about the whole save file and not about two fresh profiles.
func _distinctive_profile() -> PlayerProfile:
	var profile := PlayerProfile.defaults()
	profile.gold_banked = GOLD
	profile.echo_shards = 77
	profile.ore = {"copper": 9, "iron": 4, "heartstone": 5}
	profile.town = {"blacksmith": 2, "tavern": 1}
	profile.story_flags = ["act_2", "rescued_miner_1"]
	profile.map_room_deepest_rope = 17
	profile.characters_unlocked = ["wren"]
	profile.weapons_unlocked = ["pickaxe", "crossbow", "lantern_staff", "ember_blade"]
	profile.weapon_damage_tiers = {"pickaxe": 3}
	# `classes` keeps the three starting classes: `from_dict()` overlays them on
	# every load (a save that lost one gets it back), so the case adds a rank to
	# one rather than replacing the map — replacing it is a save the loader is
	# *meant* to correct, and comparing against it would fail for the right
	# reason on the wrong claim.
	var warrior: Dictionary = profile.classes["warrior"]
	warrior["xp"] = 320
	warrior["mastery"] = 2
	profile.classes["warrior"] = warrior
	profile.codex = {"relics": ["ember_boots"], "abilities": [], "enemies": [], "bosses": []}
	profile.potions = {"slots": 2, "types": ["heal"], "starting": []}
	profile.stats = {
		"runs": 6, "deaths": 4, "extractions": 2, "kills": 189,
		"deepest_floor": 14, "playtime_seconds": 3900,
	}
	profile.settings = {
		"audio": {"master": 0.5}, "video": {}, "screen_shake": 0.25, "bindings": {},
	}
	return profile


## Runs the probe scene in a separate Godot process and returns its payload. The
## child's whole output goes into the log on any failure, so a case that cannot
## get a payload says why.
func _relaunch() -> Dictionary:
	var output: Array = []
	var code: int = OS.execute(
		OS.get_executable_path(),
		PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--quit-after", str(CHILD_FRAME_BACKSTOP), PROBE_SCENE,
		]),
		output,
		true
	)
	var text: String = ""
	for chunk: Variant in output:
		text += str(chunk) + "\n"
	assert_eq(code, 0, "the relaunched process exited cleanly\n%s" % text)
	for raw_line: String in text.split("\n"):
		if not raw_line.begins_with(MARKER + " "):
			continue
		var parsed: Variant = JSON.parse_string(raw_line.substr(MARKER.length() + 1))
		assert_true(parsed is Dictionary, "the probe printed a JSON object\n%s" % raw_line)
		if parsed is Dictionary:
			return parsed as Dictionary
	assert_true(false, "the relaunched process printed no %s line\n%s" % [MARKER, text])
	return {}


## ---------------------------------------------------------------------------
## 1. The save survives a restart
## ---------------------------------------------------------------------------

func test_a_save_survives_a_restart() -> void:
	var manager := _start_a_manager()
	manager.profile = _distinctive_profile()
	manager.save()
	assert_eq(manager.write_count, 0, "the write is still queued when the process is about to quit")
	remove_child(manager)
	await wait_process_frames(2)
	assert_eq(manager.write_count, 1, "quitting flushes the pending save exactly once")
	var expected: Dictionary = manager.profile.to_dict()
	assert_eq(expected["gold_banked"], GOLD, "the case is set up with distinctive values")
	assert_eq(
		SaveFileFixture.profile_at(SaveFileFixture.SAVE_PATH).to_dict(), expected,
		"and the file on disk holds the whole profile"
	)
	var written: PackedByteArray = SaveFileFixture.bytes_at(SaveFileFixture.SAVE_PATH)

	var child := _relaunch()
	assert_ne(int(child["pid"]), OS.get_process_id(), "a separate process read the save")
	assert_eq(str(child["path"]), SaveManager.PATH, "and it read the path the spec names")
	assert_eq(str(child["refusal"]), "", "the relaunch had nothing to refuse")
	assert_false(bool(child["recovered_from_backup"]), "no recovery was needed")
	assert_eq((child["corrupt_files_kept"] as Array).size(), 0, "and nothing was kept")
	var loaded := PlayerProfile.from_dict(child["profile"] as Dictionary)
	assert_eq(loaded.to_dict(), expected, "the relaunched process's profile equals what was written")
	assert_eq(loaded.gold_banked, GOLD, "including the distinctive currency")
	assert_eq(loaded.ore_count(&"heartstone"), 5, "and a non-default ore count")
	assert_eq(SaveFileFixture.bytes_at(SaveFileFixture.SAVE_PATH), written, "a load rewrites nothing")


## ---------------------------------------------------------------------------
## 2. The control: no save, no invention
## ---------------------------------------------------------------------------

func test_a_relaunch_with_no_save_reports_a_fresh_profile() -> void:
	assert_false(SaveFileFixture.exists(SaveFileFixture.SAVE_PATH), "the case is set up with no save")
	var child := _relaunch()
	assert_eq(str(child["refusal"]), "", "a machine with no save is not a refusal")
	assert_eq((child["corrupt_files_kept"] as Array).size(), 0, "and keeps nothing")
	var loaded := PlayerProfile.from_dict(child["profile"] as Dictionary)
	assert_eq(
		loaded.to_dict(), PlayerProfile.defaults().to_dict(),
		"the probe reports a fresh profile when there is nothing to read"
	)
	assert_ne(loaded.gold_banked, GOLD, "so case 1 could not have passed by reading this one")


## ---------------------------------------------------------------------------
## 3. A corrupt save is recovered by the next launch
## ---------------------------------------------------------------------------

func test_a_corrupt_save_is_recovered_by_the_next_launch() -> void:
	await _write_two_saves()
	SaveFileFixture.write_text(SaveFileFixture.SAVE_PATH, TRUNCATED)

	var child := _relaunch()
	assert_eq(str(child["refusal"]), REFUSAL_CORRUPT, "the relaunch names the file it could not read")
	assert_true(bool(child["recovered_from_backup"]), "and says it used the backup")
	var kept: Array = child["corrupt_files_kept"]
	assert_eq(kept.size(), 1, "keeping the file it could not read")
	if kept.size() == 1:
		assert_eq(
			SaveFileFixture.text_at(str(kept[0])), TRUNCATED,
			"with the bytes that were at the path"
		)
	var loaded := PlayerProfile.from_dict(child["profile"] as Dictionary)
	assert_eq(loaded.gold_banked, 1111, "and the player is back in the save before the broken one")
	assert_false(
		SaveFileFixture.exists(SaveFileFixture.SAVE_PATH),
		"the unreadable file does not stay where a second launch would read it again"
	)


## Two real writes through the module, so the file the case breaks is one the
## module itself wrote and the backup holds a complete earlier save.
func _write_two_saves() -> void:
	var manager := _start_a_manager()
	manager.profile = _distinctive_profile()
	manager.profile.gold_banked = 1111
	manager.save()
	await wait_process_frames(2)
	manager.profile.gold_banked = 2222
	manager.save()
	await wait_process_frames(2)
	assert_eq(
		SaveFileFixture.profile_at(SaveFileFixture.BACKUP_PATH).gold_banked, 1111,
		"the case is set up: the backup holds the earlier save"
	)
	assert_eq(
		SaveFileFixture.profile_at(SaveFileFixture.SAVE_PATH).gold_banked, 2222,
		"and the path holds the later one"
	)
