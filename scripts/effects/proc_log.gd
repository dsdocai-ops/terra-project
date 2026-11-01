class_name ProcLog
extends RefCounted
## The last procs delivered through `Effect.deal_damage`, newest first, for the
## `effects` debug overlay (SPEC-debug-tools, week 4). Owned by effect-system.
##
## Sync: host only in practice. The production callers are relic effects
## (scripts/effects/relics/), which run on the host, so the store is written
## there; no client mirror exists. It lives in scripts/effects/ rather than scripts/debug/
## because the release export excludes scripts/debug/* and `Effect` calls it.

## How many procs the store keeps; older ones are dropped.
const CAPACITY: int = 20

## Newest first. Each entry: {source: StringName, depth: int, damage: int}.
static var _recent: Array[Dictionary] = []


## Adds one proc to the front of the store and drops the oldest past CAPACITY.
static func record(source: StringName, depth: int, damage: int) -> void:
	_recent.push_front({"source": source, "depth": depth, "damage": damage})
	if _recent.size() > CAPACITY:
		_recent.resize(CAPACITY)


## A copy of the store, newest first. Changing the copy changes nothing here.
static func recent() -> Array[Dictionary]:
	return _recent.duplicate()


## Empties the store. Tests and a new run use it; nothing else does.
static func clear() -> void:
	_recent.clear()


## One line per entry, in the order given: "source  depth N  dmg M".
static func format_lines(entries: Array[Dictionary]) -> String:
	if entries.is_empty():
		return "procs: none yet"
	var lines := PackedStringArray()
	for entry: Dictionary in entries:
		lines.append("%s  depth %d  dmg %d" % [entry["source"], entry["depth"], entry["damage"]])
	return "\n".join(lines)
