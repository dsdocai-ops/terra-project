extends Node
## Persistent profile on disk. Owned by save-system (week 5 fills it in).
## Week 1 stub: API shape from SPEC-save-system.
## Sync: local file per machine; the host never writes a client's profile.

signal saved()
signal loaded(profile: RefCounted)

const SAVE_VERSION: int = 1
const PATH: String = "user://save.json"

## TODO(save-system): PlayerProfile.
var profile: RefCounted = null


## Debounced, atomic write of `profile` to PATH.
func save() -> void:
	pass


## Reads PATH on startup and runs migrations.
func load() -> void:
	pass


## New game; keeps settings.
func reset_profile() -> void:
	pass


## JSON dump for the debug console.
func export_debug() -> String:
	return "{}"
