class_name DialogueData
extends Resource
## One NPC's or event's dialogue: entries keyed by id, each with lines,
## choices and conditions. Owned by story-dialogue (W6-B1, PLAN G2).
## Sync: none (data). Files parse once at startup; a file that breaks its
## schema is a test-suite failure, never a runtime surprise — the loader
## collects every violation into `LoadResult.errors` instead of stopping at
## the first one, so one broken file reports everything wrong with it in a
## single pass.
##
## The JSON shape, the condition language and every rule live in
## `specs/content/dialogue-schema.md`. Condition expressions stay raw
## Dictionaries on purpose: `StoryManager.evaluate()` (PLAN G3) owns their
## meaning; this class only checks their structure and that every flag they
## name is declared. The declared-flag table is a parameter, so the loader
## never reaches into the autoload and a test can pass its own.

## Where dialogue JSON lives. `flags.json` (the flag declaration) shares the
## folder but is not a dialogue file; the directory scan skips it by name.
const DIALOGUE_DIR: String = "res://data/dialogue"
const FLAGS_FILE_NAME: String = "flags.json"

## Entries are picked by descending priority (SPEC-story-dialogue): the
## highest-priority entry whose conditions pass is the NPC's current dialogue.
## Bounds keep a typo from sorting an entry into invisibility or above the
## whole set.
const PRIORITY_MIN: int = 0
const PRIORITY_MAX: int = 100

const ACT_MIN: int = 1
const ACT_MAX: int = 3

const TOP_LEVEL_KEYS: Array[String] = ["id", "portrait", "entries"]
const ENTRY_KEYS: Array[String] = ["id", "priority", "conditions", "lines", "choices", "on_end"]
const LINE_KEYS: Array[String] = ["speaker", "text", "emotion", "character_only"]
const CHOICE_KEYS: Array[String] = ["text", "goto", "set_flags", "end"]
const ON_END_KEYS: Array[String] = ["set_flags", "give"]

## How deep a condition expression may nest. A self-referencing or absurdly
## deep expression is a generator bug; the cap catches it at load time.
const MAX_CONDITION_DEPTH: int = 8

## Known `on_end.give` currencies (SPEC-run-economy); anything else is a typo
## that would silently hand a player nothing.
const GIVE_KEYS: Array[String] = ["gold", "ore", "echo_shards"]

## Condition operators. Composites nest; leaves read the world (PLAN G3
## implements their meaning). `town_level` and `random_chance` carry arguments
## inside the operator object; every other leaf is a bare value or flag name.
const COMPOSITE_OPS: Array[String] = ["all", "any", "not"]
const LEAF_OPS: Array[String] = [
	"flag", "flag_not", "character", "class", "town_level",
	"ore_min", "deepest_floor_min", "rescued", "act_min", "random_chance",
]

## An empty condition object passes (an entry with no `conditions` is always
## eligible); `{}` is that case, not an error.
const EMPTY_CONDITION: Dictionary = {}

## How many entries a dialogue may carry. Nothing in the design doc needs more;
## the cap turns a copy-paste accident into a loud schema error.
const MAX_ENTRIES: int = 64

## Line and choice text bounds. A line with no text renders nothing; a choice
## button cannot hold a paragraph.
const LINE_TEXT_MAX: int = 400
const CHOICE_TEXT_MAX: int = 80


## The typed shape the runtime reads: the whole file's id, its portrait path
## ("" when the file declares none), and every entry in file order. Plain
## containers (not inner Resources) — dialogue is read far more than edited,
## and the schema tests validate the JSON, not the Resource serialization.
class Entry extends RefCounted:
	var id: StringName = &""
	var priority: int = 0
	## Raw condition expression, consumed by StoryManager.evaluate().
	var conditions: Dictionary = EMPTY_CONDITION
	var lines: Array = []
	var choices: Array = []
	## Raw `on_end` object: optional `set_flags` (Array of String) and `give`
	## (Dictionary of currency -> amount). Typed into getters on demand.
	var on_end: Dictionary = EMPTY_CONDITION


## The outcome of one file load: the resource on success, and every schema
## violation as a human-readable line keyed to the file, whether it failed or
## not. The data-driven test prints the errors so a broken JSON says what is
## wrong with it, in one pass.
class LoadResult extends RefCounted:
	var path: String = ""
	var data: DialogueData = null
	var errors: PackedStringArray = []

	func ok() -> bool:
		return errors.is_empty() and data != null


var id: StringName = &""
## `res://` path of the portrait texture; "" when the file declares none. The
## loader checks the file exists when a path is given, so a typo in the field
## is a schema error, not a missing texture at talk time.
var portrait: String = ""
var entries: Array[Entry] = []


## The entry whose id is `entry_id`, or null. Choice `goto` targets resolve
## through this; the loader validates every goto at load time so a broken jump
## is caught by the test suite, not mid-conversation.
func entry(entry_id: StringName) -> Entry:
	for e: Entry in entries:
		if e.id == entry_id:
			return e
	return null


## Every entry id, in file order; the goto-validation error lines name them.
func entry_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for e: Entry in entries:
		ids.append(e.id)
	return ids


## Entries in descending priority order, ties broken by file order (the SPEC's
## selection rule: the highest-priority entry whose conditions pass is the
## NPC's current dialogue — with ties, the earlier entry wins, so the choice
## must not depend on the sorter's whim). Insertion rather than `sort_custom`,
## which makes no stability promise.
func entries_by_priority() -> Array[Entry]:
	var ordered: Array[Entry] = []
	for e: Entry in entries:
		var inserted := false
		for i: int in ordered.size():
			if e.priority > ordered[i].priority:
				ordered.insert(i, e)
				inserted = true
				break
		if not inserted:
			ordered.append(e)
	return ordered


## The priority order filtered to entries whose top-level `act_min` the given
## act satisfies. A pre-filter, not the selection itself: an `act_min` nested
## inside `all`/`any` stays in and waits for `StoryManager.evaluate()` (PLAN
## G3) to judge it against live state.
func entries_for_act(act_value: int) -> Array[Entry]:
	var result: Array[Entry] = []
	for e: Entry in entries_by_priority():
		var act_required: Variant = (e.conditions as Dictionary).get("act_min", ACT_MIN)
		if int(act_required) <= clampi(act_value, ACT_MIN, ACT_MAX):
			result.append(e)
	return result


# --- loading and schema validation ------------------------------------------


## Loads and validates `res://data/dialogue/<file_name>`. Never pushes an
## error or breaks: every problem lands in `result.errors` as
## "<file>: <what>", so the test suite can print the whole list for one file
## in a single pass. A missing or unparseable file produces a result with
## errors and no data.
static func load_file(file_name: String, declared_flags: Dictionary) -> LoadResult:
	var result := LoadResult.new()
	var path := DIALOGUE_DIR.path_join(file_name)
	result.path = path
	if not FileAccess.file_exists(path):
		result.errors.append("%s: file does not exist" % path)
		return result
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		result.errors.append("%s: JSON parse error at line %d: %s" % [
			path, json.get_error_line(), json.get_error_message(),
		])
		return result
	if not (json.data is Dictionary):
		result.errors.append("%s: top level must be an object" % path)
		return result
	result.data = _validate(json.data as Dictionary, file_name, declared_flags, result.errors)
	return result


## Loads every dialogue JSON in DIALOGUE_DIR (skipping flags.json). Used by the
## data-driven test and by startup; files are returned in directory order,
## which the test sorts before asserting on.
static func load_all(declared_flags: Dictionary) -> Array[LoadResult]:
	var results: Array[LoadResult] = []
	var dir := DirAccess.open(DIALOGUE_DIR)
	if dir == null:
		return results
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json") \
				and file_name != FLAGS_FILE_NAME:
			results.append(load_file(file_name, declared_flags))
		file_name = dir.get_next()
	dir.list_dir_end()
	return results


## Parses `raw` (already JSON-decoded) against the schema, appending every
## violation to `errors`. Split from load_file so tests can validate a
## constructed Dictionary without writing a file.
static func _validate(
	raw: Dictionary,
	file_name: String,
	declared_flags: Dictionary,
	errors: PackedStringArray,
) -> DialogueData:
	var data := DialogueData.new()
	for key: String in raw.keys():
		if not TOP_LEVEL_KEYS.has(key):
			_fail(errors, file_name, "unknown top-level key \"%s\"" % key)
	_validate_id(raw, file_name, errors, data)
	_validate_portrait(raw, file_name, errors, data)
	_validate_entries(raw, file_name, errors, data, declared_flags)
	_validate_gotos(data, file_name, errors)
	return data


## Every choice `goto` must name an entry in the same file. A dangling goto
## would end the conversation mid-tree at runtime; here it is a schema error
## the test suite prints with both names.
static func _validate_gotos(data: DialogueData, file_name: String, errors: PackedStringArray) -> void:
	var ids := data.entry_ids()
	for entry: Entry in data.entries:
		for choice: Variant in entry.choices:
			if not (choice is Dictionary) or not (choice as Dictionary).has("goto"):
				continue
			var target: Variant = (choice as Dictionary)["goto"]
			if target is String and not ids.has(StringName(target as String)):
				_fail(errors, file_name, "%s choice \"goto\" \"%s\" matches no entry (have %s)" % [
					entry.id, target, ", ".join(_id_strings(ids)),
				])


static func _id_strings(ids: Array[StringName]) -> PackedStringArray:
	var strings := PackedStringArray()
	for id: StringName in ids:
		strings.append(String(id))
	return strings


static func _fail(errors: PackedStringArray, file_name: String, message: String) -> void:
	errors.append("%s: %s" % [file_name, message])


static func _validate_id(
	raw: Dictionary,
	file_name: String,
	errors: PackedStringArray,
	data: DialogueData,
) -> void:
	if not raw.has("id"):
		_fail(errors, file_name, "missing \"id\"")
		return
	var value: Variant = raw["id"]
	if not (value is String) or (value as String).is_empty():
		_fail(errors, file_name, "\"id\" must be a non-empty string")
		return
	data.id = StringName(value as String)
	# Content ids are the file name (SPEC-project); the data-driven test
	# enforces the same rule on .tres files.
	var expected := StringName(file_name.trim_suffix(".json"))
	if data.id != expected:
		_fail(errors, file_name, "\"id\" is \"%s\" but the file name says \"%s\"" % [data.id, expected])


static func _validate_portrait(
	raw: Dictionary,
	file_name: String,
	errors: PackedStringArray,
	data: DialogueData,
) -> void:
	if not raw.has("portrait"):
		return
	var value: Variant = raw["portrait"]
	if not (value is String):
		_fail(errors, file_name, "\"portrait\" must be a string path")
		return
	var path := value as String
	if path.is_empty():
		return
	if not path.begins_with("res://"):
		_fail(errors, file_name, "\"portrait\" must be a res:// path, got \"%s\"" % path)
		return
	if not FileAccess.file_exists(path):
		_fail(errors, file_name, "\"portrait\" file does not exist: %s" % path)
		return
	data.portrait = path


static func _validate_entries(
	raw: Dictionary,
	file_name: String,
	errors: PackedStringArray,
	data: DialogueData,
	declared_flags: Dictionary,
) -> void:
	if not raw.has("entries"):
		_fail(errors, file_name, "missing \"entries\"")
		return
	var value: Variant = raw["entries"]
	if not (value is Array):
		_fail(errors, file_name, "\"entries\" must be an array")
		return
	var raw_entries: Array = value
	if raw_entries.is_empty():
		_fail(errors, file_name, "\"entries\" must not be empty")
		return
	if raw_entries.size() > MAX_ENTRIES:
		_fail(errors, file_name, "\"entries\" has %d entries, over the cap of %d" % [
			raw_entries.size(), MAX_ENTRIES,
		])
		return
	var seen: Dictionary[StringName, bool] = {}
	for i: int in raw_entries.size():
		var raw_entry: Variant = raw_entries[i]
		if not (raw_entry is Dictionary):
			_fail(errors, file_name, "entries[%d] must be an object" % i)
			continue
		_validate_entry(raw_entry as Dictionary, i, file_name, errors, data, seen, declared_flags)


static func _validate_entry(
	raw_entry: Dictionary,
	index: int,
	file_name: String,
	errors: PackedStringArray,
	data: DialogueData,
	seen: Dictionary[StringName, bool],
	declared_flags: Dictionary,
) -> void:
	for key: String in raw_entry.keys():
		if not ENTRY_KEYS.has(key):
			_fail(errors, file_name, "entries[%d] has unknown key \"%s\"" % [index, key])
	var entry := Entry.new()
	# Entry id: required, unique within the file, snake_case (it is a goto
	# target, so a space would make authored gotos unreadable).
	if not raw_entry.has("id"):
		_fail(errors, file_name, "entries[%d] missing \"id\"" % index)
	else:
		var value: Variant = raw_entry["id"]
		if not (value is String) or (value as String).is_empty():
			_fail(errors, file_name, "entries[%d] \"id\" must be a non-empty string" % index)
		else:
			entry.id = StringName(value as String)
			if seen.has(entry.id):
				_fail(errors, file_name, "entries[%d] repeats id \"%s\"" % [index, entry.id])
			seen[entry.id] = true
	# Priority: required, integer in bounds. It decides who wins the selection
	# scan, so a missing one is a content mistake, not a default.
	if not raw_entry.has("priority"):
		_fail(errors, file_name, "entries[%d] missing \"priority\"" % index)
	elif not (raw_entry["priority"] is int):
		_fail(errors, file_name, "entries[%d] \"priority\" must be an integer" % index)
	else:
		entry.priority = raw_entry["priority"] as int
		if entry.priority < PRIORITY_MIN or entry.priority > PRIORITY_MAX:
			_fail(errors, file_name, "entries[%d] \"priority\" %d outside %d..%d" % [
				index, entry.priority, PRIORITY_MIN, PRIORITY_MAX,
			])
	# Conditions: optional; an absent or empty object always passes.
	if raw_entry.has("conditions"):
		var conditions: Variant = raw_entry["conditions"]
		if not (conditions is Dictionary):
			_fail(errors, file_name, "entries[%d] \"conditions\" must be an object" % index)
		else:
			entry.conditions = conditions
			_validate_condition(conditions, "entries[%d]" % index, file_name, errors, 0, declared_flags)
	# Lines: required, at least one.
	if not raw_entry.has("lines"):
		_fail(errors, file_name, "entries[%d] missing \"lines\"" % index)
	else:
		var lines: Variant = raw_entry["lines"]
		if not (lines is Array) or (lines as Array).is_empty():
			_fail(errors, file_name, "entries[%d] \"lines\" must be a non-empty array" % index)
		else:
			for j: int in (lines as Array).size():
				_validate_line(lines[j], "entries[%d].lines[%d]" % [index, j], file_name, errors)
				if lines[j] is Dictionary:
					entry.lines.append(lines[j])
	# Choices: optional.
	if raw_entry.has("choices"):
		var choices: Variant = raw_entry["choices"]
		if not (choices is Array):
			_fail(errors, file_name, "entries[%d] \"choices\" must be an array" % index)
		else:
			for j: int in (choices as Array).size():
				_validate_choice(choices[j], "entries[%d].choices[%d]" % [index, j], file_name, errors, declared_flags)
				if choices[j] is Dictionary:
					entry.choices.append(choices[j])
	# on_end: optional.
	if raw_entry.has("on_end"):
		var on_end: Variant = raw_entry["on_end"]
		if not (on_end is Dictionary):
			_fail(errors, file_name, "entries[%d] \"on_end\" must be an object" % index)
		else:
			entry.on_end = on_end
			_validate_on_end(on_end as Dictionary, "entries[%d]" % index, file_name, errors, declared_flags)
	data.entries.append(entry)


static func _validate_line(
	raw_line: Variant,
	where: String,
	file_name: String,
	errors: PackedStringArray,
) -> void:
	if not (raw_line is Dictionary):
		_fail(errors, file_name, "%s must be an object" % where)
		return
	var line := raw_line as Dictionary
	for key: String in line.keys():
		if not LINE_KEYS.has(key):
			_fail(errors, file_name, "%s has unknown key \"%s\"" % [where, key])
	if not line.has("speaker") or not (line["speaker"] is String) \
			or (line["speaker"] as String).is_empty():
		_fail(errors, file_name, "%s missing \"speaker\"" % where)
	if not line.has("text") or not (line["text"] is String) \
			or (line["text"] as String).is_empty():
		_fail(errors, file_name, "%s missing \"text\"" % where)
	elif (line["text"] as String).length() > LINE_TEXT_MAX:
		_fail(errors, file_name, "%s \"text\" over %d characters" % [where, LINE_TEXT_MAX])
	if line.has("character_only") and not (line["character_only"] is String):
		_fail(errors, file_name, "%s \"character_only\" must be a character id" % where)


static func _validate_choice(
	raw_choice: Variant,
	where: String,
	file_name: String,
	errors: PackedStringArray,
	declared_flags: Dictionary,
) -> void:
	if not (raw_choice is Dictionary):
		_fail(errors, file_name, "%s must be an object" % where)
		return
	var choice := raw_choice as Dictionary
	for key: String in choice.keys():
		if not CHOICE_KEYS.has(key):
			_fail(errors, file_name, "%s has unknown key \"%s\"" % [where, key])
	if not choice.has("text") or not (choice["text"] is String) \
			or (choice["text"] as String).is_empty():
		_fail(errors, file_name, "%s missing \"text\"" % where)
	elif (choice["text"] as String).length() > CHOICE_TEXT_MAX:
		_fail(errors, file_name, "%s \"text\" over %d characters" % [where, CHOICE_TEXT_MAX])
	# Exactly one destination: a goto into the same file, or end: true. A
	# choice with neither hangs the conversation; with both it is ambiguous.
	var has_goto: bool = choice.has("goto") and choice["goto"] is String \
			and not (choice["goto"] as String).is_empty()
	var ends: bool = choice.get("end", false) == true
	if has_goto and ends:
		_fail(errors, file_name, "%s has both \"goto\" and \"end\"" % where)
	elif not has_goto and not ends:
		_fail(errors, file_name, "%s needs \"goto\" or \"end\": true" % where)
	if choice.has("set_flags"):
		_validate_flag_set(choice["set_flags"], where, file_name, errors, declared_flags)


static func _validate_on_end(
	on_end: Dictionary,
	where: String,
	file_name: String,
	errors: PackedStringArray,
	declared_flags: Dictionary,
) -> void:
	for key: String in on_end.keys():
		if not ON_END_KEYS.has(key):
			_fail(errors, file_name, "%s has unknown key \"%s\"" % [where, key])
	if on_end.has("set_flags"):
		_validate_flag_set(on_end["set_flags"], where, file_name, errors, declared_flags)
	if on_end.has("give"):
		var give: Variant = on_end["give"]
		if not (give is Dictionary):
			_fail(errors, file_name, "%s \"give\" must be an object" % where)
		else:
			for currency: String in (give as Dictionary).keys():
				if not GIVE_KEYS.has(currency):
					_fail(errors, file_name, "%s \"give\" has unknown currency \"%s\"" % [where, currency])
				elif not ((give as Dictionary)[currency] is int):
					_fail(errors, file_name, "%s \"give.%s\" must be an integer amount" % [where, currency])


## Checks a condition expression's shape and flag names, recursively.
## `depth` guards against runaway nesting: a self-nesting expression would
## otherwise recurse forever, so anything deeper than MAX_CONDITION_DEPTH is
## rejected instead.
##
## `not` holds exactly one sub-expression, `all`/`any` hold any number (zero
## counts: an empty `all` is vacuously true, an empty `any` vacuously false —
## both are well-formed and left to evaluate() to interpret). Every leaf must
## be a known operator; every flag a leaf names must be declared.
static func _validate_condition(
	condition: Variant,
	where: String,
	file_name: String,
	errors: PackedStringArray,
	depth: int,
	declared_flags: Dictionary,
) -> void:
	if not (condition is Dictionary):
		_fail(errors, file_name, "%s condition must be an object" % where)
		return
	if depth > MAX_CONDITION_DEPTH:
		_fail(errors, file_name, "%s condition nests deeper than %d" % [where, MAX_CONDITION_DEPTH])
		return
	var expr := condition as Dictionary
	if expr.is_empty():
		return
	for op: String in expr.keys():
		var value: Variant = expr[op]
		if COMPOSITE_OPS.has(op):
			# `not` accepts either the array form ({"not": [expr]}) or the
			# object form ({"not": expr}) — both appear in the SPEC examples.
			var subs: Array = []
			if op == "not" and not (value is Array):
				subs = [value]
			elif value is Array:
				subs = value
			else:
				_fail(errors, file_name, "%s \"%s\" must be an array of conditions" % [where, op])
				continue
			if op == "not" and subs.size() != 1:
				_fail(errors, file_name, "%s \"not\" holds exactly one condition, got %d" % [
					where, subs.size(),
				])
			for sub: Variant in subs:
				_validate_condition(sub, "%s.%s" % [where, op], file_name, errors, depth + 1, declared_flags)
		elif LEAF_OPS.has(op):
			_validate_leaf(op, value, where, file_name, errors, declared_flags)
		else:
			_fail(errors, file_name, "%s unknown condition operator \"%s\"" % [where, op])


## Leaf operator shapes. Kept structural: the loader checks types and names,
## evaluate() (PLAN G3) checks meaning against live state.
static func _validate_leaf(
	op: String,
	value: Variant,
	where: String,
	file_name: String,
	errors: PackedStringArray,
	declared_flags: Dictionary,
) -> void:
	match op:
		"flag", "flag_not":
			if not (value is String):
				_fail(errors, file_name, "%s \"%s\" must be a flag name" % [where, op])
			elif not _declared(value as String, file_name, errors, where, declared_flags):
				pass
		"character", "class":
			if not (value is String) or (value as String).is_empty():
				_fail(errors, file_name, "%s \"%s\" must be a non-empty id" % [where, op])
		"town_level":
			if not (value is Dictionary):
				_fail(errors, file_name, "%s \"town_level\" must be {building, min}" % where)
			else:
				var spec := value as Dictionary
				if not spec.has("building") or not (spec["building"] is String):
					_fail(errors, file_name, "%s \"town_level\" missing \"building\"" % where)
				if not spec.has("min") or not (spec["min"] is int):
					_fail(errors, file_name, "%s \"town_level\" missing \"min\"" % where)
		"ore_min":
			if not (value is Dictionary):
				_fail(errors, file_name, "%s \"ore_min\" must be {ore, min}" % where)
			else:
				var spec := value as Dictionary
				if not spec.has("ore") or not (spec["ore"] is String):
					_fail(errors, file_name, "%s \"ore_min\" missing \"ore\"" % where)
				if not spec.has("min") or not (spec["min"] is int):
					_fail(errors, file_name, "%s \"ore_min\" missing \"min\"" % where)
		"deepest_floor_min":
			if not (value is int):
				_fail(errors, file_name, "%s \"deepest_floor_min\" must be an integer floor" % where)
			elif (value as int) < RunState.MIN_FLOOR or (value as int) > RunState.MAX_FLOOR:
				_fail(errors, file_name, "%s \"deepest_floor_min\" %d outside %d..%d" % [
					where, value, RunState.MIN_FLOOR, RunState.MAX_FLOOR,
				])
		"rescued":
			if not (value is String):
				_fail(errors, file_name, "%s \"rescued\" must be a miner id" % where)
		"act_min":
			if not (value is int):
				_fail(errors, file_name, "%s \"act_min\" must be an integer" % where)
			elif (value as int) < ACT_MIN or (value as int) > ACT_MAX:
				_fail(errors, file_name, "%s \"act_min\" %d outside %d..%d" % [
					where, value, ACT_MIN, ACT_MAX,
				])
		"random_chance":
			if not (value is float) and not (value is int):
				_fail(errors, file_name, "%s \"random_chance\" must be a number in 0..1" % where)
			elif float(value) < 0.0 or float(value) > 1.0:
				_fail(errors, file_name, "%s \"random_chance\" must be in 0..1" % where)


## True when the flag name is declared; records the schema error when not.
static func _declared(
	flag: String,
	file_name: String,
	errors: PackedStringArray,
	where: String,
	declared_flags: Dictionary,
) -> bool:
	if declared_flags.has(flag):
		return true
	_fail(errors, file_name, "%s names undeclared flag \"%s\"" % [where, flag])
	return false


## Also collects the flags named in `set_flags` (choices and on_end): setting
## an undeclared flag would write a name no condition can ever read. A
## non-array `set_flags` is reported here too, because the caller's own key
## check cannot tell a wrong shape from a right one.
static func _validate_flag_set(
	flag_names: Variant,
	where: String,
	file_name: String,
	errors: PackedStringArray,
	declared_flags: Dictionary,
) -> void:
	if not (flag_names is Array):
		_fail(errors, file_name, "%s \"set_flags\" must be an array of flag names" % where)
		return
	for flag_name: Variant in flag_names:
		if not (flag_name is String):
			_fail(errors, file_name, "%s \"set_flags\" entries must be flag name strings" % where)
		else:
			_declared(flag_name, file_name, errors, where, declared_flags)





