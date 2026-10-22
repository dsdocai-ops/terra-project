extends Node
## Persistent profile on disk. Owned by save-system (week 5 fills it in).
##
## SPEC-save-system, "When it saves": "`SaveManager.save()` is called by:
## `run-economy` on return to town (after banking), `town` and
## `progression-trees` after any purchase, `ui-hud` on settings change and on
## quit, `story-dialogue` when a flag that unlocks something is set. Debounced:
## multiple calls within one frame write once. Writes are atomic: write to
## `user://save.json.tmp`, then rename over `user://save.json`. Keep
## `user://save.bak` from the previous successful save."
##
## The debounce is one deferred flush per frame, not a timer: the callers above
## fire in bursts (a purchase writes several fields, a quit writes the settings
## once more), and what matters is that the file on disk is the profile at the
## end of the frame, written once. A write that cannot start or that does not
## land intact leaves `PATH` exactly as it was — the previous save is never
## replaced by a half one.
##
## `load()` runs at startup (`_ready()`) and reads `PATH`, steps the migration
## chain (`SaveMigrations`) and hands the result to `PlayerProfile.from_dict()`,
## which is where a key the file does not have becomes its `defaults()` value — so
## a field added by a later build arrives without a migration.
##
## SPEC-save-system, "On startup": "If parse fails, load `save.bak`; if that
## fails, start fresh and keep the corrupt file as `save.corrupt.<timestamp>`."
## So a load has four outcomes, and every one of them is observable:
##
##   * the file reads — the profile it holds, and no refusal;
##   * there is no file and no backup — a fresh profile, and no refusal either,
##     because the refusal vocabulary is for files that exist and cannot be used;
##   * the file parses but this build cannot migrate it — refused by name, fresh
##     profile, and the file is **left exactly where it is**, because moving a
##     newer build's save aside would destroy the only copy of that town;
##   * the file is not a save at all — kept as `user://save.corrupt.<timestamp>`,
##     then `BACKUP_PATH` is tried, and only if that fails too does the player
##     start fresh (the unreadable backup is kept as well).
##
## A load never writes: it repairs nothing and rewrites nothing, so the backup it
## just recovered from is still there for the next launch.
##
## Sync: local file per machine; the host never writes a client's profile.

signal saved()
signal loaded(profile: PlayerProfile)

const SAVE_VERSION: int = 1
const PATH: String = "user://save.json"
## The file a write goes through, so `PATH` is only ever one rename away from a
## complete file and never holds a half-written one.
const TMP_PATH: String = PATH + ".tmp"
## The previous successful save, kept for `load()`'s fallback (G5).
const BACKUP_PATH: String = "user://save.bak"
## The file at `PATH` is not a JSON object — truncated, or not a save at all.
const REFUSAL_CORRUPT_FILE: StringName = &"save_file_is_not_a_json_object"
## Where a file this build cannot read is kept: `save.corrupt.<timestamp>`, the
## name SPEC-save-system's recovery sentence gives it.
const CORRUPT_PREFIX: String = "user://save.corrupt."

## The live profile; null until `load()` or a caller sets one.
var profile: PlayerProfile = null

## Why the last `load()` did not use the file it found: empty when it did, and
## otherwise the name of the rule that stopped it — one of `SaveMigrations`'
## refusal names, or `REFUSAL_CORRUPT_FILE`. Read-only state; `ui-hud` may show
## it, and nothing in gameplay decides anything from it.
var load_refusal: StringName = SaveMigrations.REFUSAL_NONE

## True when the last `load()` used `BACKUP_PATH` because the file at `PATH`
## could not be read as a save. Read-only state; the UI owns what it says about
## it, and nothing in gameplay decides anything from it.
var recovered_from_backup: bool = false

## Where the last `load()` kept each file it could not read, as the
## `user://save.corrupt.<timestamp>` path it was moved to. Empty on a clean load.
## Read-only state, and the reason a recovery is not a silent one.
var corrupt_files_kept: Array[String] = []


## What one attempt at one save file produced. A file is either a profile, or a
## named reason it is not one, or it was not there at all — and the three are kept
## apart because `load()` does something different for each.
class Read extends RefCounted:
	## The profile the file held, or null when it could not be used.
	var profile: PlayerProfile = null
	## Why the file could not be used; empty when `profile` is set.
	var reason: StringName = SaveMigrations.REFUSAL_NONE
	## True when there was no file at the path — a new game, not a refusal.
	var file_missing: bool = false


## True when the profile has changed since the last completed write.
var _dirty: bool = false
## True when a write is already queued for the end of this frame.
var _flush_scheduled: bool = false


## Queues one write for the end of this frame. A second call in the same frame
## changes nothing but the state that write will carry.
func save() -> void:
	if profile == null:
		return
	_dirty = true
	if _flush_scheduled:
		return
	_flush_scheduled = true
	_flush.call_deferred()


## SPEC-save-system's "On startup: read file, parse JSON, check `save_version`."
## The first frame of the game is the one that has to find last session's town, so
## the read happens here rather than waiting for a caller that might never come.
##
## A `-s` main loop does not add autoloads, so a test that wants a restart makes a
## *scene* (`tests/fixtures/save_relaunch_probe.tscn`).
func _ready() -> void:
	# `self.` because a bare `load()` is the engine's global `load(path)`.
	self.load()


## Reads `PATH`, steps the migrations and fills the profile's missing keys from
## the defaults (SPEC-save-system, "Loading and migration"). A read that cannot be
## trusted never becomes half a profile: the caller gets a fresh one, the reason
## on `load_refusal`, and — when there was a file that could not be read — the
## path it was kept at on `corrupt_files_kept`.
##
## The outcomes are spelled out in this script's header. Two orderings are
## deliberate. A file that parses but refuses to migrate is returned to its own
## path untouched, while a file that is not a save at all is moved aside and the
## backup is tried — a newer build's save is the one thing here that must never be
## treated as damage. And the backup is consulted whenever `PATH` yielded no
## profile, **including when `PATH` holds no file at all**: a recovery moves the
## unreadable file aside, so the launch after it would otherwise find an empty
## path and start a new game over a town that is still sitting in `save.bak`.
## `load_refusal` keeps its one meaning through both — the reason `PATH` could not
## be used — and names nothing when the path was simply empty.
func load() -> void:
	load_refusal = SaveMigrations.REFUSAL_NONE
	recovered_from_backup = false
	corrupt_files_kept.clear()
	var primary := _read_profile_at(PATH)
	if primary.profile != null:
		profile = primary.profile
		loaded.emit(profile)
		return
	if primary.reason != REFUSAL_CORRUPT_FILE and not primary.file_missing:
		# The file parses and this build cannot migrate it. Refused by name, and
		# left exactly where it is: it is the only copy of that town.
		load_refusal = primary.reason
		_fresh_profile()
		return
	if primary.reason == REFUSAL_CORRUPT_FILE:
		# Not a save at all: keep it, then fall back to the previous good one.
		load_refusal = REFUSAL_CORRUPT_FILE
		_keep_corrupt(PATH)
	var backup := _read_profile_at(BACKUP_PATH)
	if backup.profile != null:
		recovered_from_backup = true
		profile = backup.profile
		loaded.emit(profile)
		return
	if backup.reason == REFUSAL_CORRUPT_FILE:
		_keep_corrupt(BACKUP_PATH)
	_fresh_profile()


## The profile a machine with nothing usable at either path starts with. Emitted
## like any other load, so a listener never has to wonder whether one happened.
func _fresh_profile() -> void:
	profile = PlayerProfile.defaults()
	loaded.emit(profile)


## One attempt at one file: the migration chain runs here and nowhere else, and
## `PlayerProfile.from_dict()` is what fills each key the file does not have.
func _read_profile_at(path: String) -> Read:
	var read := Read.new()
	if not FileAccess.file_exists(path):
		read.file_missing = true
		return read
	var parsed: Variant = _parse_object(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		read.reason = REFUSAL_CORRUPT_FILE
		return read
	var outcome := SaveMigrations.migrate(parsed as Dictionary)
	read.reason = outcome.reason
	if outcome.ok():
		read.profile = PlayerProfile.from_dict(outcome.data)
	return read


## Moves a file this build cannot read to `user://save.corrupt.<timestamp>` and
## records where it went. The file is *moved* rather than copied so it cannot be
## read again as if it were the save — a player who relaunches gets the same
## recovery, not the same failure. Returns the new path, or "" when there was
## nothing to keep or the move failed.
func _keep_corrupt(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var kept := _free_corrupt_path()
	if DirAccess.rename_absolute(path, kept) != OK:
		return ""
	corrupt_files_kept.append(kept)
	return kept


## The name the next kept file takes: `save.corrupt.<date>T<time>`, UTC so the
## stamp parses back with `Time.get_unix_time_from_datetime_string()` and a folder
## of them sorts, with no colon — which a Windows path cannot hold. A second keep
## inside the same second takes `.2`, `.3` … so an earlier one is never lost.
func _free_corrupt_path() -> String:
	var base := CORRUPT_PREFIX + Time.get_datetime_string_from_system(true, false).replace(":", "")
	var candidate := base
	var nth: int = 2
	while FileAccess.file_exists(candidate):
		candidate = "%s.%d" % [base, nth]
		nth += 1
	return candidate


## A new game: `PlayerProfile.defaults()` with the settings carried over, so a
## reset never costs the player their audio and video choices.
func reset_profile() -> void:
	var kept: Dictionary = {}
	if profile != null:
		kept = profile.settings.duplicate(true)
	var fresh := PlayerProfile.defaults()
	fresh.settings.merge(kept, true)
	profile = fresh
	save()


## JSON dump for the debug console. Read-only: it stamps no timestamp.
func export_debug() -> String:
	if profile == null:
		return "{}"
	return JSON.stringify(profile.to_dict(), "\t")


## Writes the pending profile, once per frame, at the end of it.
func _flush() -> void:
	_flush_scheduled = false
	if not _dirty:
		return
	_dirty = false
	# A write that could not land leaves the profile dirty, so the next `save()`
	# — or the quit below — tries again instead of the change going quiet.
	if not _write_atomic():
		_dirty = true


## A quit with a write still queued — `ui-hud` saves on quit — must not lose it,
## so leaving the tree flushes it here instead of waiting for a frame that will
## never come. The queued `_flush` then finds nothing dirty and writes nothing.
func _exit_tree() -> void:
	if _dirty:
		_flush()


## One atomic write: serialise, write `TMP_PATH`, check it landed intact, roll
## the previous good save to `BACKUP_PATH`, then rename `TMP_PATH` over `PATH`.
## Returns false, and leaves `PATH` alone, at the first step that fails.
##
## The order is what makes the save crash-safe: until the roll, `PATH` is the
## previous save and the new one is only ever a tmp file; after it, the previous
## save is at `BACKUP_PATH`. So at every instant one of the two holds a complete
## save — the only window is the rename itself, and a rename that fails leaves
## the previous save where `load()`'s fallback (G5) looks for it.
func _write_atomic() -> bool:
	var text := _serialize()
	if text.is_empty():
		return false
	if not _write_tmp(text):
		return false
	if not _parse_object(FileAccess.get_file_as_string(TMP_PATH)) is Dictionary:
		return false
	_roll_backup()
	if not _promote_tmp():
		return false
	saved.emit()
	return true


## The profile as the JSON text `PATH` holds, with the clock stamped on it —
## `created_at` and `last_saved_at` are this module's fields (SPEC-save-system).
func _serialize() -> String:
	if profile == null:
		return ""
	profile.touch_timestamps()
	return JSON.stringify(profile.to_dict(), "\t")


func _write_tmp(text: String) -> bool:
	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	return true


## Rolls the existing save aside as the backup, but only when it is a save this
## build can read: a corrupt file is never promoted into the fallback.
func _roll_backup() -> void:
	if not FileAccess.file_exists(PATH):
		return
	if not _parse_object(FileAccess.get_file_as_string(PATH)) is Dictionary:
		return
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	DirAccess.rename_absolute(PATH, BACKUP_PATH)


func _promote_tmp() -> bool:
	return DirAccess.rename_absolute(TMP_PATH, PATH) == OK


## `text` as the JSON object it holds, or `null` when it is not one. A `JSON`
## instance rather than `JSON.parse_string()`: a half-written file is the case
## this module exists to survive, and `parse_string()` answers it with an engine
## error on the console, which is not a state a save should be able to produce.
static func _parse_object(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
