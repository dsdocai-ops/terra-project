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
## `load()` is G4's: reading `PATH`, stepping the migrations, filling missing
## keys from `PlayerProfile.defaults()` and falling back to `BACKUP_PATH` all
## arrive there. Until then it only guarantees that a profile object exists.
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

## The live profile; null until `load()` (G4) or a caller sets one.
var profile: PlayerProfile = null

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


## Reads PATH on startup and runs migrations. G4 owns the chain.
func load() -> void:
	if profile == null:
		profile = PlayerProfile.defaults()
	loaded.emit(profile)


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
