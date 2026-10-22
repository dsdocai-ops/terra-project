class_name PlayerProfile
extends RefCounted
## Everything that survives a run: the one JSON profile per machine.
## Owned by `save-system` (SPEC-save-system's "What persists" table is the
## contract; `FIELDS` below is that table's names, in its own order).
##
## Sync: a local file per machine, never replicated. The host writes only its
## own profile; at run end it sends each peer that peer's own gains over
## `run_summary(peer_id, gains)` (SPEC-save-system "Co-op") and the peer merges
## them here with `merge_run_gains()`. Nothing in this class reads the scene
## tree, the network or the clock — `touch_timestamps()` is the one clock read
## and `SaveManager` is its only caller.
##
## `RefCounted`, not `Resource` (SPEC-save-system "Interfaces provided"): this
## object exists only to be written to and read from JSON, and a `Resource`
## would drag an editor path and a sub-resource cache into the save file.
##
## Boundary rule (SPEC-project, C12): a bare `Dictionary` or untyped `Array`
## lives at the JSON edge only. `to_dict()` hands out JSON-safe values and
## `from_dict()` coerces every one of them straight back into its typed field,
## because Godot's JSON parser returns every number as a `float` — so an `int`
## field read without coercion comes back a `float` and the save quietly drifts.
## Dictionary keys are `String` throughout (the ids are `StringName` in
## `data/`, converted at the accessor), because a JSON object's keys are
## strings and this way the round trip changes nothing.

## The save schema this build writes. SPEC-save-system pins it at 1; a bump
## needs a migration and a fixture in the same commit (its "Success criteria").
const CURRENT_VERSION: int = 1

## SPEC-save-system's "What persists" table, in the table's own order. A field
## the spec names and this class does not declare (or the other way round) is a
## failing test, and a save file missing one of these keys is defaulted.
const FIELDS: Array[StringName] = [
	&"save_version",
	&"created_at",
	&"last_saved_at",
	&"gold_banked",
	&"ore",
	&"echo_shards",
	&"town",
	&"skill_tree",
	&"respec_used_date",
	&"classes",
	&"characters_unlocked",
	&"weapons_unlocked",
	&"weapon_damage_tiers",
	&"relic_vault_pick",
	&"rune_library_pick",
	&"potions",
	&"story_flags",
	&"lore_unlocked",
	&"endings_seen",
	&"codex",
	&"achievements",
	&"cosmetics_unlocked",
	&"equipped_cosmetics",
	&"rescued_miners",
	&"map_room_deepest_rope",
	&"deep_mode_unlocked",
	&"heat_levels_unlocked",
	&"daily_dive_best",
	&"stats",
	&"settings",
]

## The fields `merge_run_gains()` unions rather than adds: a list that gains an
## entry keeps every entry it already had and never repeats one.
const UNION_FIELDS: Array[StringName] = [
	&"story_flags",
	&"lore_unlocked",
	&"endings_seen",
	&"achievements",
	&"cosmetics_unlocked",
	&"rescued_miners",
	&"characters_unlocked",
	&"weapons_unlocked",
]

## The starting unlocks, each from the spec that owns the content:
## SPEC-classes-characters "Unlocks: Warrior, Ranger, Mage at start" and Wren's
## unlock flag "default"; SPEC-weapons "Pickaxe, Crossbow, Lantern Staff
## unlocked at start". A fresh profile with none of these could not start a run.
const STARTING_CLASSES: Array[StringName] = [&"warrior", &"ranger", &"mage"]
const STARTING_CHARACTERS: Array[StringName] = [&"wren"]
const STARTING_WEAPONS: Array[StringName] = [&"pickaxe", &"crossbow", &"lantern_staff"]

## One `classes` entry's shape, from SPEC-save-system's example skeleton.
const CLASS_XP: String = "xp"
const CLASS_MASTERY: String = "mastery"
const CLASS_TREE: String = "tree"
const CLASS_UNLOCKED: String = "unlocked"

## The `codex` categories (SPEC-save-system's own four).
const CODEX_CATEGORIES: Array[StringName] = [&"relics", &"abilities", &"enemies", &"bosses"]

## The `stats` counters, and the one of them that is a best rather than a total.
const STAT_KEYS: Array[StringName] = [
	&"runs", &"deaths", &"extractions", &"kills", &"deepest_floor", &"playtime_seconds",
]
const STAT_DEEPEST_FLOOR: String = "deepest_floor"

## The `potions` keys (SPEC-save-system's own three).
const POTION_SLOTS: String = "slots"
const POTION_TYPES: String = "types"
const POTION_STARTING: String = "starting"

## The `settings` keys (SPEC-save-system's own four); `ui-hud` owns the values.
const SETTINGS_SCREEN_SHAKE: String = "screen_shake"

## `save-system`, stamped by `SaveManager` on every write.
var save_version: int = CURRENT_VERSION
var created_at: String = ""
var last_saved_at: String = ""

## `run-economy`.
var gold_banked: int = 0
var ore: Dictionary = {}
var echo_shards: int = 0

## `town`: building_id -> level (0 to 3). A building the map does not name is
## level 0 — the ids are `data/town/`'s, so a new building needs no change here.
var town: Dictionary = {}

## `progression-trees`.
var skill_tree: Dictionary = {}
var respec_used_date: String = ""

## `classes-characters` and `progression-trees`: class_id -> `{xp, mastery,
## tree, unlocked}`. `merge_run_gains()` adds `xp`; mastery is derived from it
## by `classes-characters`' own thresholds, not here.
var classes: Dictionary = {}

## `classes-characters`.
var characters_unlocked: Array[String] = []

## `weapons` and `town`: weapon_id -> damage tier.
var weapons_unlocked: Array[String] = []
var weapon_damage_tiers: Dictionary = {}

## `town`: the Relic Vault and Rune Library picks, empty when none is made.
var relic_vault_pick: StringName = &""
var rune_library_pick: StringName = &""

## `town`: `{slots, types, starting}` — the Alchemist's configuration.
var potions: Dictionary = {}

## `story-dialogue`.
var story_flags: Array[String] = []
var lore_unlocked: Array[String] = []
var endings_seen: Array[String] = []

## `relics`, `abilities`, `enemies-ai`, `bosses`: seen ids per category.
var codex: Dictionary = {}

## `endgame` and `town`.
var achievements: Array[String] = []
var cosmetics_unlocked: Array[String] = []
var equipped_cosmetics: Dictionary = {}

## `story-dialogue`.
var rescued_miners: Array[String] = []

## `run-economy`: how deep the Map Room may start a run.
var map_room_deepest_rope: int = 0

## `endgame`: how many heat levels are unlocked (heat itself is chosen by the
## host in the lobby and applied per run, SPEC-endgame); the modifier ids are
## that module's `HeatModifier` data.
var deep_mode_unlocked: bool = false
var heat_levels_unlocked: int = 0
var daily_dive_best: Dictionary = {}

## `run-economy`.
var stats: Dictionary = {}

## `ui-hud`.
var settings: Dictionary = {}


## A brand-new profile: every field at its spec value, no clock read, so two
## calls are identical and a test can compare them (SPEC-save-system "Loading
## and migration": "Missing keys get defaults from `PlayerProfile.defaults()`").
static func defaults() -> PlayerProfile:
	var profile: PlayerProfile = PlayerProfile.new()
	profile.save_version = CURRENT_VERSION
	profile.classes = _default_classes()
	profile.characters_unlocked = _copy_names(STARTING_CHARACTERS)
	profile.weapons_unlocked = _copy_names(STARTING_WEAPONS)
	profile.potions = _default_potions()
	profile.codex = _default_codex()
	profile.stats = _default_stats()
	profile.settings = _default_settings()
	return profile


## The JSON-safe form of this profile: plain `Array`s, `String` keys and
## `String` values, so `JSON.stringify()` has nothing to interpret.
func to_dict() -> Dictionary:
	return {
		"save_version": save_version,
		"created_at": created_at,
		"last_saved_at": last_saved_at,
		"gold_banked": gold_banked,
		"ore": _plain(ore),
		"echo_shards": echo_shards,
		"town": _plain(town),
		"skill_tree": _plain(skill_tree),
		"respec_used_date": respec_used_date,
		"classes": _plain(classes),
		"characters_unlocked": _plain(characters_unlocked),
		"weapons_unlocked": _plain(weapons_unlocked),
		"weapon_damage_tiers": _plain(weapon_damage_tiers),
		"relic_vault_pick": String(relic_vault_pick),
		"rune_library_pick": String(rune_library_pick),
		"potions": _plain(potions),
		"story_flags": _plain(story_flags),
		"lore_unlocked": _plain(lore_unlocked),
		"endings_seen": _plain(endings_seen),
		"codex": _plain(codex),
		"achievements": _plain(achievements),
		"cosmetics_unlocked": _plain(cosmetics_unlocked),
		"equipped_cosmetics": _plain(equipped_cosmetics),
		"rescued_miners": _plain(rescued_miners),
		"map_room_deepest_rope": map_room_deepest_rope,
		"deep_mode_unlocked": deep_mode_unlocked,
		"heat_levels_unlocked": heat_levels_unlocked,
		"daily_dive_best": _plain(daily_dive_best),
		"stats": _plain(stats),
		"settings": _plain(settings),
	}


## A profile from a parsed JSON object. Every key it names is read and coerced
## into its field's type; every key it does not name keeps `defaults()`' value,
## so a new field never needs a migration (SPEC-save-system, same clause). A key
## this build does not know is dropped rather than carried: `FIELDS` is the
## schema, and a value of the wrong type falls back to the default instead of
## reaching a typed field.
static func from_dict(d: Dictionary) -> PlayerProfile:
	var base: PlayerProfile = defaults()
	var profile: PlayerProfile = PlayerProfile.new()
	profile.save_version = _int_of(d, &"save_version", base.save_version)
	profile.created_at = _string_of(d, &"created_at", base.created_at)
	profile.last_saved_at = _string_of(d, &"last_saved_at", base.last_saved_at)
	profile.gold_banked = _int_of(d, &"gold_banked", base.gold_banked)
	profile.ore = _int_map_of(d, &"ore", base.ore)
	profile.echo_shards = _int_of(d, &"echo_shards", base.echo_shards)
	profile.town = _int_map_of(d, &"town", base.town)
	profile.skill_tree = _int_map_of(d, &"skill_tree", base.skill_tree)
	profile.respec_used_date = _string_of(d, &"respec_used_date", base.respec_used_date)
	profile.classes = _classes_of(d, &"classes", base.classes)
	profile.characters_unlocked = _strings_of(d, &"characters_unlocked", base.characters_unlocked)
	profile.weapons_unlocked = _strings_of(d, &"weapons_unlocked", base.weapons_unlocked)
	profile.weapon_damage_tiers = _int_map_of(d, &"weapon_damage_tiers", base.weapon_damage_tiers)
	profile.relic_vault_pick = _name_of(d, &"relic_vault_pick", base.relic_vault_pick)
	profile.rune_library_pick = _name_of(d, &"rune_library_pick", base.rune_library_pick)
	profile.potions = _potions_of(d, &"potions", base.potions)
	profile.story_flags = _strings_of(d, &"story_flags", base.story_flags)
	profile.lore_unlocked = _strings_of(d, &"lore_unlocked", base.lore_unlocked)
	profile.endings_seen = _strings_of(d, &"endings_seen", base.endings_seen)
	profile.codex = _codex_of(d, &"codex", base.codex)
	profile.achievements = _strings_of(d, &"achievements", base.achievements)
	profile.cosmetics_unlocked = _strings_of(d, &"cosmetics_unlocked", base.cosmetics_unlocked)
	profile.equipped_cosmetics = _string_map_of(d, &"equipped_cosmetics", base.equipped_cosmetics)
	profile.rescued_miners = _strings_of(d, &"rescued_miners", base.rescued_miners)
	profile.map_room_deepest_rope = _int_of(d, &"map_room_deepest_rope", base.map_room_deepest_rope)
	profile.deep_mode_unlocked = _bool_of(d, &"deep_mode_unlocked", base.deep_mode_unlocked)
	profile.heat_levels_unlocked = _int_of(d, &"heat_levels_unlocked", base.heat_levels_unlocked)
	profile.daily_dive_best = _int_map_of(d, &"daily_dive_best", base.daily_dive_best)
	profile.stats = _stats_of(d, &"stats", base.stats)
	profile.settings = _settings_of(d, &"settings", base.settings)
	return profile


## A copy of this profile that shares nothing with it.
func copy() -> PlayerProfile:
	return from_dict(to_dict())


## What a run's gains do to this profile — the merge half of SPEC-save-system's
## "Co-op": "the host sends each client its per-player gains (`echo_shards`,
## `class_xp`, `story_flags` newly set, codex entries, achievements) ... the
## client merges and saves. Gold and ore are split evenly and each banks their
## share." Additive and non-destructive by construction: nothing here assigns a
## value the gains did not name, so a field a run never touched is untouched.
##
## Recognised keys: `gold_banked`, `ore`, `echo_shards`, `class_id` with
## `class_xp`, the eight `UNION_FIELDS`, `codex`, `stats`,
## `map_room_deepest_rope`, `daily_dive_best`. Anything else is ignored, so a
## caller from a later week cannot corrupt the schema by sending an extra key.
func merge_run_gains(gains: Dictionary) -> void:
	gold_banked += _gain_int(gains, &"gold_banked")
	echo_shards += _gain_int(gains, &"echo_shards")
	_add_counts(ore, _gain(gains, &"ore"))

	var class_id: String = _gain_string(gains, &"class_id")
	var class_xp: int = _gain_int(gains, &"class_xp")
	if class_xp > 0 and not class_id.is_empty():
		_add_class_xp(class_id, class_xp)

	story_flags = _union_names(story_flags, _gain(gains, &"story_flags"))
	lore_unlocked = _union_names(lore_unlocked, _gain(gains, &"lore_unlocked"))
	endings_seen = _union_names(endings_seen, _gain(gains, &"endings_seen"))
	achievements = _union_names(achievements, _gain(gains, &"achievements"))
	cosmetics_unlocked = _union_names(cosmetics_unlocked, _gain(gains, &"cosmetics_unlocked"))
	rescued_miners = _union_names(rescued_miners, _gain(gains, &"rescued_miners"))
	characters_unlocked = _union_names(characters_unlocked, _gain(gains, &"characters_unlocked"))
	weapons_unlocked = _union_names(weapons_unlocked, _gain(gains, &"weapons_unlocked"))

	var codex_gains: Variant = _gain(gains, &"codex")
	if codex_gains is Dictionary:
		for raw_key: Variant in codex_gains as Dictionary:
			_union_codex(String(raw_key), (codex_gains as Dictionary)[raw_key])

	_add_stats(_gain(gains, &"stats"))
	map_room_deepest_rope = maxi(map_room_deepest_rope, _gain_int(gains, &"map_room_deepest_rope"))
	_add_bests(daily_dive_best, _gain(gains, &"daily_dive_best"))


## How much of an ore the profile holds. An ore the map does not name is zero,
## so a new ore in `data/ore/` needs no default here.
func ore_count(ore_id: StringName) -> int:
	return int(ore.get(String(ore_id), 0))


## A town building's level. A building the map does not name is level 0, the
## same rule as `ore_count()`.
func building_level(building_id: StringName) -> int:
	return int(town.get(String(building_id), 0))


## Stamps `created_at` the first time and `last_saved_at` on every call, both
## ISO-8601 UTC. `save-system` owns both fields and `SaveManager` is the caller.
func touch_timestamps() -> void:
	var now: String = now_iso()
	if created_at.is_empty():
		created_at = now
	last_saved_at = now


## The current UTC instant as `2026-10-20T23:04:43Z`.
static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"


## ---------------------------------------------------------------------------
## Defaults
## ---------------------------------------------------------------------------

static func _default_classes() -> Dictionary:
	var out: Dictionary = {}
	for class_id: StringName in STARTING_CLASSES:
		out[String(class_id)] = {
			CLASS_XP: 0,
			CLASS_MASTERY: 1,
			CLASS_TREE: {},
			CLASS_UNLOCKED: true,
		}
	return out


static func _default_codex() -> Dictionary:
	var out: Dictionary = {}
	for category: StringName in CODEX_CATEGORIES:
		var seen: Array[String] = []
		out[String(category)] = seen
	return out


static func _default_stats() -> Dictionary:
	var out: Dictionary = {}
	for key: StringName in STAT_KEYS:
		out[String(key)] = 0
	return out


static func _default_potions() -> Dictionary:
	var types: Array[String] = []
	var starting: Array[String] = []
	return {POTION_SLOTS: 0, POTION_TYPES: types, POTION_STARTING: starting}


static func _default_settings() -> Dictionary:
	return {"audio": {}, "video": {}, SETTINGS_SCREEN_SHAKE: 1.0, "bindings": {}}


## ---------------------------------------------------------------------------
## The JSON boundary
## ---------------------------------------------------------------------------

## JSON-safe copy: typed arrays become plain ones and `StringName`s become
## `String`s, recursively, because `codex`, `classes`, `stats` and `settings`
## nest one level deeper than the rest.
static func _plain(value: Variant) -> Variant:
	if value is Array:
		var items: Array = []
		for item: Variant in value as Array:
			items.append(_plain(item))
		return items
	if value is Dictionary:
		var source: Dictionary = value as Dictionary
		var out: Dictionary = {}
		for raw_key: Variant in source:
			out[String(raw_key)] = _plain(source[raw_key])
		return out
	if value is StringName:
		return String(value)
	return value


static func _copy_names(source: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for name: StringName in source:
		out.append(String(name))
	return out


## A read that accepts either spelling of the key, so a caller may build a gains
## dictionary with `String` keys and still be understood.
static func _gain(gains: Dictionary, key: StringName) -> Variant:
	if gains.has(key):
		return gains[key]
	return gains.get(String(key))


static func _gain_int(gains: Dictionary, key: StringName) -> int:
	return _int_value(_gain(gains, key), 0)


static func _gain_string(gains: Dictionary, key: StringName) -> String:
	var value: Variant = _gain(gains, key)
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""


## An `int` from anything a JSON file may hold for one, and `fallback` for
## anything else (`int("12")` is 12 and `int("not a number")` is 0).
static func _int_value(value: Variant, fallback: int) -> int:
	if value is int or value is float or value is bool or value is String:
		return int(value)
	return fallback


static func _bool_value(value: Variant, fallback: bool) -> bool:
	if value is bool:
		return value
	return fallback


static func _int_of(d: Dictionary, key: StringName, fallback: int) -> int:
	return _int_value(d.get(key), fallback)


static func _bool_of(d: Dictionary, key: StringName, fallback: bool) -> bool:
	return _bool_value(d.get(key), fallback)


static func _string_of(d: Dictionary, key: StringName, fallback: String) -> String:
	var value: Variant = d.get(key)
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return fallback


static func _name_of(d: Dictionary, key: StringName, fallback: StringName) -> StringName:
	var value: Variant = d.get(key)
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return fallback


static func _strings_of(d: Dictionary, key: StringName, fallback: Array[String]) -> Array[String]:
	var value: Variant = d.get(key)
	if not value is Array:
		return _to_strings(fallback)
	return _to_strings(value)


static func _to_strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if not value is Array:
		return out
	for item: Variant in value as Array:
		if item is String or item is StringName:
			out.append(String(item))
	return out


static func _int_map_of(d: Dictionary, key: StringName, fallback: Dictionary) -> Dictionary:
	var value: Variant = d.get(key)
	if not value is Dictionary:
		return fallback.duplicate(true)
	return _to_int_map(value)


static func _to_int_map(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not value is Dictionary:
		return out
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source:
		var raw_value: Variant = source[raw_key]
		if raw_value is int or raw_value is float or raw_value is bool or raw_value is String:
			out[String(raw_key)] = int(raw_value)
	return out


static func _string_map_of(d: Dictionary, key: StringName, fallback: Dictionary) -> Dictionary:
	var value: Variant = d.get(key)
	if not value is Dictionary:
		return fallback.duplicate(true)
	var source: Dictionary = value as Dictionary
	var out: Dictionary = {}
	for raw_key: Variant in source:
		var raw_value: Variant = source[raw_key]
		if raw_value is String or raw_value is StringName:
			out[String(raw_key)] = String(raw_value)
	return out


## `classes` over the defaults: a class the file does not name keeps its default
## entry, so the starting three stay unlocked even in a file that lost them.
static func _classes_of(d: Dictionary, key: StringName, fallback: Dictionary) -> Dictionary:
	var out: Dictionary = fallback.duplicate(true)
	var value: Variant = d.get(key)
	if not value is Dictionary:
		return out
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source:
		if source[raw_key] is Dictionary:
			out[String(raw_key)] = _class_entry(source[raw_key])
	return out


## One class entry in SPEC-save-system's skeleton shape, whatever the file held.
static func _class_entry(value: Variant) -> Dictionary:
	var source: Dictionary = value as Dictionary
	return {
		CLASS_XP: _int_value(source.get(CLASS_XP), 0),
		CLASS_MASTERY: _int_value(source.get(CLASS_MASTERY), 1),
		CLASS_TREE: _to_int_map(source.get(CLASS_TREE)),
		CLASS_UNLOCKED: _bool_value(source.get(CLASS_UNLOCKED), true),
	}


static func _codex_of(d: Dictionary, key: StringName, fallback: Dictionary) -> Dictionary:
	var out: Dictionary = fallback.duplicate(true)
	var value: Variant = d.get(key)
	if not value is Dictionary:
		return out
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source:
		if source[raw_key] is Array:
			out[String(raw_key)] = _to_strings(source[raw_key])
	return out


static func _stats_of(d: Dictionary, key: StringName, fallback: Dictionary) -> Dictionary:
	var out: Dictionary = fallback.duplicate(true)
	var value: Variant = d.get(key)
	if not value is Dictionary:
		return out
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source:
		var stat: String = String(raw_key)
		out[stat] = _int_value(source[raw_key], int(out.get(stat, 0)))
	return out


static func _potions_of(d: Dictionary, key: StringName, fallback: Dictionary) -> Dictionary:
	var out: Dictionary = fallback.duplicate(true)
	var value: Variant = d.get(key)
	if not value is Dictionary:
		return out
	var source: Dictionary = value as Dictionary
	if source.has(POTION_SLOTS):
		out[POTION_SLOTS] = _int_value(source[POTION_SLOTS], 0)
	if source.has(POTION_TYPES):
		out[POTION_TYPES] = _to_strings(source[POTION_TYPES])
	if source.has(POTION_STARTING):
		out[POTION_STARTING] = _to_strings(source[POTION_STARTING])
	return out


## `settings` is the one open dictionary in the profile — `ui-hud` owns its
## keys — so a key this build does not know is kept rather than dropped.
static func _settings_of(d: Dictionary, key: StringName, fallback: Dictionary) -> Dictionary:
	var out: Dictionary = fallback.duplicate(true)
	var value: Variant = d.get(key)
	if not value is Dictionary:
		return out
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source:
		var setting: String = String(raw_key)
		var raw_value: Variant = source[raw_key]
		if setting == SETTINGS_SCREEN_SHAKE and (raw_value is int or raw_value is float):
			out[setting] = float(raw_value)
		elif (
			raw_value is Dictionary or raw_value is Array
			or raw_value is String or raw_value is StringName
			or raw_value is int or raw_value is float or raw_value is bool
		):
			out[setting] = _plain(raw_value)
	return out


## ---------------------------------------------------------------------------
## The merge
## ---------------------------------------------------------------------------

static func _add_counts(target: Dictionary, value: Variant) -> void:
	if not value is Dictionary:
		return
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source:
		var key: String = String(raw_key)
		target[key] = int(target.get(key, 0)) + _int_value(source[raw_key], 0)


func _add_stats(value: Variant) -> void:
	if not value is Dictionary:
		return
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source:
		var key: String = String(raw_key)
		var amount: int = _int_value(source[raw_key], 0)
		if key == STAT_DEEPEST_FLOOR:
			stats[key] = maxi(int(stats.get(key, 0)), amount)
		else:
			stats[key] = int(stats.get(key, 0)) + amount


static func _add_bests(target: Dictionary, value: Variant) -> void:
	if not value is Dictionary:
		return
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source:
		var key: String = String(raw_key)
		target[key] = maxi(int(target.get(key, 0)), _int_value(source[raw_key], 0))


func _add_class_xp(class_id: String, amount: int) -> void:
	var existing: Variant = classes.get(class_id)
	var entry: Dictionary = {}
	if existing is Dictionary:
		entry = existing as Dictionary
	classes[class_id] = {
		CLASS_XP: _int_value(entry.get(CLASS_XP), 0) + amount,
		CLASS_MASTERY: _int_value(entry.get(CLASS_MASTERY), 1),
		CLASS_TREE: _to_int_map(entry.get(CLASS_TREE)),
		CLASS_UNLOCKED: _bool_value(entry.get(CLASS_UNLOCKED), true),
	}


## What is new in `value`, appended to `existing` and never repeated. One of the
## `UNION_FIELDS`; each is written out at the call site so the field keeps its
## declared type instead of going through a dynamic property set.
static func _union_names(existing: Array[String], value: Variant) -> Array[String]:
	var out: Array[String] = []
	out.assign(existing)
	if not value is Array:
		return out
	for item: Variant in value as Array:
		if item is String or item is StringName:
			var text: String = String(item)
			if not out.has(text):
				out.append(text)
	return out


func _union_codex(category: String, value: Variant) -> void:
	if not value is Array:
		return
	var seen: Array[String] = []
	var existing: Variant = codex.get(category)
	if existing is Array:
		seen = _to_strings(existing)
	for item: Variant in value as Array:
		if item is String or item is StringName:
			var text: String = String(item)
			if not seen.has(text):
				seen.append(text)
	codex[category] = seen
