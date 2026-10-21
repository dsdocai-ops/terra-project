extends Node
## The child process `tests/integration/test_save_survives_restart.gd` launches to
## prove a profile written by one process is read back by the next one (PLAN G5;
## SPEC-save-system's "Integration: save, quit, relaunch headless, profile equal").
##
## It is a **scene**, not a `-s` script: a `-s` main loop does not run the
## project's autoloads — measured, not assumed, the first probe this goal wrote
## failed to compile with `Identifier not found: SaveManager` — and the whole
## point of the probe is to exercise the *shipped* startup path rather than a
## private one. So this file calls nothing to read the save: `SaveManager`'s own
## `_ready()` does it, exactly as it would in the game, and the probe only reports
## what that left behind.
##
## One machine-readable line, then exit 0. `pid` is in the payload because it is
## what makes the relaunch a *separate process* rather than an in-process
## re-read: the test asserts it differs from its own.
##
## Owned by `save-system`; a test harness file, never part of a shipped scene.

## The prefix the test greps for. The JSON object follows it on the same line.
const MARKER: String = "SAVE_RELAUNCH_PROBE"


func _ready() -> void:
	var profile: PlayerProfile = SaveManager.profile
	var payload: Dictionary = {
		"pid": OS.get_process_id(),
		"path": SaveManager.PATH,
		"refusal": String(SaveManager.load_refusal),
		"recovered_from_backup": SaveManager.recovered_from_backup,
		"corrupt_files_kept": SaveManager.corrupt_files_kept,
		"profile": {} if profile == null else profile.to_dict(),
	}
	print(MARKER + " " + JSON.stringify(payload))
	get_tree().quit()
