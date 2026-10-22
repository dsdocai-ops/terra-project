class_name CountingSaveManager
extends "res://scripts/autoload/save_manager.gd"
## Test double for `SaveManager`'s write path: it counts the writes and the
## promotions, and can be told to fail the tmp write. Used by
## `tests/unit/test_save_manager.gd` (PLAN G3); never used in a game scene.
##
## It extends the shipped script rather than copying it, so the debounce, the
## serialisation and the backup roll under test are the real ones — only the two
## seams the spec names ("write to `user://save.json.tmp`, then rename over
## `user://save.json`") are observed, by overriding `_write_tmp()` and
## `_promote_tmp()`. A count taken here is a count of the code path that ran,
## not a guess from a clock.
##
## Sync: none — a test double. The real manager's file is local per machine.

## How many times the atomic write actually ran.
var write_count: int = 0
## How many times the tmp file was promoted over `PATH`.
var promote_count: int = 0
## Whether the tmp file still existed at the moment it was promoted — the
## assertion that the data really went through `PATH + ".tmp"` first.
var tmp_existed_at_promote: bool = false
## Whether the tmp file was gone the moment the promotion returned — the
## assertion that the promotion moved it rather than copying it.
var tmp_gone_after_promote: bool = false
## When true, `_write_tmp()` reports failure without writing anything, so the
## "a write that cannot start leaves the previous save alone" case has a way to
## happen.
var fail_tmp_write: bool = false
## When true, `_write_tmp()` reports success but writes text that is not JSON,
## so the "a tmp file that did not land intact is never promoted" case has a way
## to happen.
var corrupt_tmp_write: bool = false


func _write_atomic() -> bool:
	write_count += 1
	return super()


func _write_tmp(text: String) -> bool:
	if fail_tmp_write:
		return false
	if corrupt_tmp_write:
		var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string("{ not json at all")
		file.close()
		return true
	return super(text)


func _promote_tmp() -> bool:
	promote_count += 1
	tmp_existed_at_promote = FileAccess.file_exists(TMP_PATH)
	var promoted := super()
	tmp_gone_after_promote = not FileAccess.file_exists(TMP_PATH)
	return promoted
