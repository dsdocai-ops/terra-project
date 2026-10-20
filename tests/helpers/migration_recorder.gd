class_name MigrationRecorder
extends RefCounted
## A test double for SPEC-save-system's migration functions: each step it is
## asked for records the version it ran at, so the *order* the chain stepped
## through is observable rather than assumed. Used by
## `tests/unit/test_save_migrations.gd` (PLAN G4); never used in a game scene.
##
## Its steps are real `Dictionary -> Dictionary` functions, so the runner under
## test is the shipped one and only the *content* of the chain is synthetic. A
## chain that ran out of order, skipped a version, or ran a step more than once
## shows up in `log` — which is the whole claim SPEC-save-system's "run
## `migrations[version]` in order" makes.
##
## Sync: none — a test double.

## The versions the chain stepped through, in the order it stepped through them.
var log: Array[int] = []

## When >= 0, the step for this version returns something that is not a
## `Dictionary`, so the "a migration must hand back an object" case has a way to
## happen.
var broken_version: int = -1

## When true (the default), each step hands back a **copy** with a running total
## in `stepped_through`, so a chain that re-ran an earlier step is visible in the
## value as well as in the log.
var marks_data: bool = true


## A chain with one step for each of `versions`, keyed by the version it migrates
## *from* — SPEC-save-system's own keying.
func table_for(versions: Array[int]) -> Dictionary:
	var out: Dictionary = {}
	for version: int in versions:
		out[version] = Callable(self, "_step").bind(version)
	return out


## What a case reads back to prove the steps threaded one at a time.
func stepped_through(data: Dictionary) -> int:
	return int(data.get("stepped_through", 0))


func _step(data: Variant, version: int) -> Variant:
	log.append(version)
	if version == broken_version:
		return null
	if not data is Dictionary:
		return null
	if not marks_data:
		return data
	var out: Dictionary = (data as Dictionary).duplicate(true)
	out["stepped_through"] = int(out.get("stepped_through", 0)) + version
	return out
