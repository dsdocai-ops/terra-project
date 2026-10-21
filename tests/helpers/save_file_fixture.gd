class_name SaveFileFixture
extends RefCounted
## Filesystem fixture for the `save-system` suites that run against the real
## files SPEC-save-system names (PLAN G5). Static only: it is never instantiated.
##
## Every path is spelled out here rather than read off `SaveManager`, so renaming
## one in the class is a failing case instead of a silent pass — and so a case can
## tell a file the *test* wrote from one the module wrote.
##
## The save-system suites run against `user://` on purpose: that is the path the
## spec names and the one a crash has to survive, so a double that wrote into a
## temp directory would prove nothing about it. `snapshot()`/`restore()` are how
## the suite avoids eating a real save, and the `save.corrupt.<timestamp>` files a
## recovery case creates are removed by name so they do not accumulate.
##
## Owned by `save-system`; a test harness file, never part of a shipped scene.

## The three paths SPEC-save-system names, as its own paragraphs spell them.
const SAVE_PATH: String = "user://save.json"
const TMP_PATH: String = "user://save.json.tmp"
const BACKUP_PATH: String = "user://save.bak"

## What a recovery keeps a file it cannot read as. The stamp follows the prefix.
const CORRUPT_PREFIX: String = "user://save.corrupt."

## The three files a save-system case may write, in the order `restore()` rewrites
## them: the save first, so a crash between two writes leaves a readable file.
const LIVE_PATHS: Array[String] = [SAVE_PATH, TMP_PATH, BACKUP_PATH]


## The bytes of each live path that exists right now, keyed by path. Hand it to
## `restore()` in `after_each` and the suite leaves the machine as it found it.
static func snapshot() -> Dictionary[String, PackedByteArray]:
	var out: Dictionary[String, PackedByteArray] = {}
	for path: String in LIVE_PATHS:
		if FileAccess.file_exists(path):
			out[path] = FileAccess.get_file_as_bytes(path)
	return out


## Removes every live path, then rewrites the ones `snapshot` held. Called from
## `after_each`, so it starts from a clean slate rather than assuming which files
## the case left behind.
static func restore(snapshot: Dictionary[String, PackedByteArray]) -> void:
	clear_live()
	for path: String in snapshot:
		write_bytes(path, snapshot[path])


## Deletes the three live paths, if they exist.
static func clear_live() -> void:
	for path: String in LIVE_PATHS:
		remove(path)


static func remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


static func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()


static func text_at(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func bytes_at(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


## The JSON object at `path` as a `Dictionary`, `{}` when the file is missing, is
## not JSON, or is JSON that is not an object. The parse is the point: a
## half-written file answers `{}` rather than throwing.
static func json_at(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text_at(path)) != OK:
		return {}
	if json.data is Dictionary:
		return json.data as Dictionary
	return {}


## The profile a file holds, rebuilt through the class's own reader.
static func profile_at(path: String) -> PlayerProfile:
	return PlayerProfile.from_dict(json_at(path))


## Every `save.corrupt.<timestamp>` file under `user://`, sorted, so a case can
## name the one it just created instead of listing the directory.
static func corrupt_files() -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(ProjectSettings.globalize_path("user://")):
		if name.begins_with(CORRUPT_PREFIX.get_file()):
			out.append("user://" + name)
	out.sort()
	return out


## Removes every corrupt file that `keep` does not name — the cleanup that stops a
## recovery case's leftovers accumulating in `user://` across runs.
static func remove_corrupt_files_except(keep: Array[String]) -> void:
	for path: String in corrupt_files():
		if not keep.has(path):
			remove(path)
