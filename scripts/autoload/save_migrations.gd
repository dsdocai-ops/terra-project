class_name SaveMigrations
extends RefCounted
## Ordered, one-version-at-a-time migrations for the one profile file, and the
## refusal that stops a save from a newer build being read as an older one.
## Owned by `save-system` (SPEC-save-system, "Loading and migration").
##
## SPEC-save-system: "On startup: read file, parse JSON, check `save_version`.
## If lower than current, run `migrations[version]` in order; each migration is a
## function `Dictionary -> Dictionary` in `scripts/autoload/save_migrations.gd`.
## ... Missing keys get defaults from `PlayerProfile.defaults()` so new fields
## never need a migration unless semantics change."
##
## That sentence decides three things, and each is one place here:
##
##   1. **A step is keyed by the version it migrates *from*.** `table()[1]` takes
##      a version-1 save to version 2, so the key and the version in the file
##      are never off by one.
##   2. **The steps run in ascending order, one at a time, and all of them are
##      known before any of them runs.** A version with no step refuses the whole
##      chain and hands the caller its own dictionary back — a half-migrated save
##      is worse than one that did not load, because it looks like a save.
##   3. **A save from a *newer* build is refused by name.** Reading it as if it
##      were this build's would default every field this build lacks and the next
##      write would drop them for good. Refusing leaves the file exactly as the
##      newer build wrote it, so going back to that build still works.
##
## Missing keys are **not** this module's job: `PlayerProfile.from_dict()` fills
## each one from `defaults()`, which is why `table()` may stay empty across an
## additive schema change and only grows when a field's *meaning* changes.
##
## Sync: none. A local file per machine — nothing here reads the scene tree, the
## network or the clock, and `SaveManager.load()` is the only caller.

## The key the version lives under, spelled as SPEC-save-system's own JSON
## skeleton spells it.
const VERSION_KEY: String = "save_version"

## No refusal: the chain ran, or there was nothing to run.
const REFUSAL_NONE: StringName = &""
## The file names a version this build does not know. Never read, never written.
const REFUSAL_TOO_NEW: StringName = &"save_is_from_a_newer_build"
## A version in the range that has no step — a build defect, refused rather than
## skipped so a schema change cannot ship without its migration.
const REFUSAL_NO_MIGRATION: StringName = &"no_migration_for_version"
## A step handed back something that is not a `Dictionary`, so there is no save.
const REFUSAL_NOT_AN_OBJECT: StringName = &"migration_did_not_return_an_object"


## What one pass of the chain produced. `reason` is empty when `data` is the
## migrated save; otherwise it is the named refusal and `data` is the caller's
## own dictionary, untouched.
class Outcome extends RefCounted:
	var reason: StringName = &""
	var data: Dictionary = {}

	## True when the chain produced a save this build can read.
	func ok() -> bool:
		return reason.is_empty()


## The version this build writes, read off `PlayerProfile` so the two can never
## disagree (they are the same number SPEC-save-system pins).
static func current_version() -> int:
	return PlayerProfile.CURRENT_VERSION


## The migrations this build ships, keyed by the version a step migrates *from*.
##
## **Empty today, and that is correct**: the schema is still at version 1 and
## every week-5 field is on SPEC-save-system's own table (BRIEF A5), so no
## existing value has changed meaning. A bump adds its step here **and** a
## `tests/fixtures/save_v<N>.json` in the same commit — SPEC-save-system's third
## success criterion — and `test_every_version_below_current_has_a_migration_step`
## fails until it does.
static func table() -> Dictionary:
	return {}


## The versions `table()` has a step for, ascending. Read by the tests and by a
## later reader asking what this build can migrate.
static func versions() -> Array[int]:
	var out: Array[int] = []
	for raw_key: Variant in table():
		out.append(int(raw_key))
	out.sort()
	return out


## The version a raw save claims. A missing key — or one that is not a number —
## reads as the current version, which is SPEC-save-system's "missing keys get
## defaults" applied to this key: a save written before the field existed is this
## build's, not a refused one.
static func version_of(data: Dictionary) -> int:
	var raw: Variant = data.get(VERSION_KEY)
	if raw is int or raw is float:
		return int(raw)
	return current_version()


## The shipped chain over a raw save object.
static func migrate(data: Dictionary) -> Outcome:
	return run(data, version_of(data), current_version(), table())


## One ordered pass from `from_version` up to `to_version` over `migrations`.
##
## The input is never edited and never half-applied: the whole range is checked
## for a step **before** the first one runs, and the steps work on a copy, so a
## refusal hands `data` back exactly as it arrived.
static func run(
	data: Dictionary, from_version: int, to_version: int, migrations: Dictionary
) -> Outcome:
	var outcome := Outcome.new()
	outcome.data = data
	if from_version > to_version:
		outcome.reason = REFUSAL_TOO_NEW
		return outcome
	for version: int in range(from_version, to_version):
		if not migrations.get(version) is Callable:
			outcome.reason = REFUSAL_NO_MIGRATION
			return outcome
	var migrated: Dictionary = data.duplicate(true)
	for version: int in range(from_version, to_version):
		var step: Callable = migrations[version]
		var result: Variant = step.call(migrated)
		if not result is Dictionary:
			outcome.reason = REFUSAL_NOT_AN_OBJECT
			if OS.is_debug_build():
				push_warning(
					"[save] migration for version %d did not return a Dictionary" % version
				)
			return outcome
		migrated = result as Dictionary
	migrated[VERSION_KEY] = to_version
	outcome.data = migrated
	return outcome
