extends GutTest
## `Events` bus conformance test — effect-system, W4-B1.
##
## `Events` is the one interface every Week 4 module writes against, so this
## test reads the signal table straight out of `specs/SPEC-effect-system.md` at
## run time and asserts the autoload matches it exactly: the same signal names
## with no extras and none missing, the same parameter names in the same order
## and count, and for every parameter a declared type that is either the real
## class or the documented placeholder. A signal that drifts therefore fails
## here rather than at runtime inside a relic.
##
## It also pins the placeholders. Every parameter still carrying a placeholder
## type must have a matching `## TODO(<module>): <SpecType> <- <Placeholder>
## (blocked on Dev X, <task-id>)` line in `scripts/autoload/events.gd`, so
## "we retype this when the owner lands" is a checked claim and not a hope: the
## test fails if a placeholder loses its line, if a line loses its owner, or if
## a line appears for a type that is no longer a placeholder.
##
## Sync: read-only inspection of a host-emitted bus. Owned by effect-system.

const SPEC_PATH: String = "res://specs/SPEC-effect-system.md"
const EVENTS_SCRIPT_PATH: String = "res://scripts/autoload/events.gd"
const SPEC_HEADING: String = "### Events bus"

## Parameter type as written in `SPEC-effect-system.md` -> the type the bus is
## expected to declare today. Built-in value types are compared against
## `type_string()`; every other entry is compared against the argument's
## `class_name`. A spec type absent from this map fails the test, so a new spec
## type cannot slip in without this mapping being updated deliberately.
const TYPE_MAP: Dictionary[String, String] = {
	# real classes that already exist in this repo
	"Player": "Player",
	"RunResult": "RunResult",
	# the week-2 mirror of combat-core's `HitInfo`: field names match, so the
	# swap-in is mechanical when W2-A1 lands
	"HitInfo": "HitData",
	# placeholders until their owner lands (see the TODO lines in events.gd)
	"Projectile": "Node",
	"Enemy": "Node",
	"Room": "Node",
	"Pickup": "Node",
	"RelicData": "Resource",
	"SynergyData": "Resource",
	"WeaponData": "Resource",
	"MutationData": "Resource",
	"AbilityData": "Resource",
	"AscensionData": "Resource",
	# `StatusEffects.Status` is still a placeholder: the enum exists (G20) but the
	# bus carries it as an `int` until a goal retypes the signal, and the TODO
	# line in events.gd pins that. `Combo` is no longer one: G24 (2026-10-20)
	# declared the real `Combo` class and `combo_triggered` carries it.
	"StatusEffects.Status": "int",
	"Combo": "Combo",
	# object base types the spec itself writes without naming a class
	"Node": "Node",
	"Resource": "Resource",
	# built-in value types, declared exactly
	"int": "int",
	"float": "float",
	"bool": "bool",
	"StringName": "StringName",
	"Dictionary": "Dictionary",
}

## Built-in names, compared through `type_string()` rather than `class_name`.
const BUILT_IN_TYPES: Array[String] = ["int", "float", "bool", "StringName", "Dictionary"]

## The five signals the spec says are re-emitted on clients from replicated
## state (effect-system "Events bus", last paragraph). Parsed from the spec by
## `_spec_client_signals()`, so the list cannot drift away from the document.
const CLIENT_SIGNAL_COUNT: int = 5

var _todo_re := RegEx.new()


func before_all() -> void:
	_todo_re.compile("^## TODO\\(([^)]+)\\): (\\S+) <- (\\S+) \\(blocked on Dev ([AB]), (W\\d+-[AB]\\d+)\\)$")


func _events() -> Node:
	return get_tree().root.get_node_or_null("Events")


func _read_lines(path: String) -> PackedStringArray:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "could not open %s" % path)
	if file == null:
		return PackedStringArray()
	var text := file.get_as_text()
	file.close()
	return text.split("\n")


# --- spec parsing ---------------------------------------------------------

## The `signal ...` lines of the spec's "### Events bus" fenced block, in file
## order.
func _spec_signal_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	var in_block: bool = false
	for raw: String in _read_lines(SPEC_PATH):
		var line: String = raw.strip_edges()
		if line.begins_with("### "):
			in_block = line == SPEC_HEADING
			continue
		if in_block and line.begins_with("signal "):
			out.append(line)
	return out


func _parse_signal_line(line: String) -> Dictionary:
	var body: String = line.split("#")[0].strip_edges()
	var re := RegEx.new()
	re.compile("^signal\\s+(\\w+)\\(([^)]*)\\)$")
	var m: RegExMatch = re.search(body)
	if m == null:
		return {}
	var params: Array[Dictionary] = []
	var inner: String = m.get_string(2).strip_edges()
	if inner != "":
		for part: String in inner.split(","):
			var bits: PackedStringArray = part.split(":")
			params.append({"name": bits[0].strip_edges(), "type": bits[1].strip_edges()})
	return {"name": m.get_string(1), "params": params}


## The spec's signal table, parsed. `[{name, params: [{name, type}]}]`.
func _spec_signals() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: String in _spec_signal_lines():
		var parsed: Dictionary = _parse_signal_line(line)
		assert_false(parsed.is_empty(), "spec line did not parse: %s" % line)
		if not parsed.is_empty():
			out.append(parsed)
	return out


## The five signals the spec names as also emitted on clients.
func _spec_client_signals() -> Array[String]:
	var re := RegEx.new()
	re.compile("replicated state \\(([^)]+)\\)")
	for raw: String in _read_lines(SPEC_PATH):
		var m: RegExMatch = re.search(raw)
		if m == null:
			continue
		var out: Array[String] = []
		for part: String in m.get_string(1).split(","):
			out.append(part.strip_edges().replace("`", ""))
		return out
	return [] as Array[String]


# --- runtime parsing ------------------------------------------------------

## `Events`' script-declared signals keyed by name. Deliberately
## `get_script_signal_list()` and not `get_signal_list()`, because the latter
## also returns Node's inherited signals (`ready`, `renamed`, ...).
func _runtime_signals() -> Dictionary:
	var out: Dictionary = {}
	var events: Node = _events()
	assert_not_null(events, "the Events autoload is registered")
	if events == null:
		return out
	for entry: Dictionary in events.get_script().get_script_signal_list():
		var args: Array[Dictionary] = []
		for arg: Dictionary in entry["args"]:
			args.append({"name": String(arg["name"]), "type_name": _declared_type(arg)})
		out[String(entry["name"])] = args
	return out


func _declared_type(arg: Dictionary) -> String:
	var cls: String = String(arg["class_name"])
	if cls != "":
		return cls
	return type_string(int(arg["type"]))


# --- comparison helpers (pure, so the negative control can drive them) -----

func _expected_type(spec_type: String) -> String:
	return String(TYPE_MAP.get(spec_type, ""))


func _spec_has(spec: Array, name: String) -> bool:
	for sig: Dictionary in spec:
		if String(sig["name"]) == name:
			return true
	return false


func _name_mismatches(spec: Array, runtime: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for sig: Dictionary in spec:
		var name: String = String(sig["name"])
		if not runtime.has(name):
			problems.append("missing from Events: %s" % name)
	for name: String in runtime:
		if not _spec_has(spec, name):
			problems.append("on Events but not in the spec: %s" % name)
	return problems


func _param_mismatches(spec: Array, runtime: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for sig: Dictionary in spec:
		var name: String = String(sig["name"])
		if not runtime.has(name):
			continue
		var want: Array = sig["params"]
		var have: Array = runtime[name]
		if want.size() != have.size():
			problems.append("%s: the spec declares %d parameters, Events declares %d" % [name, want.size(), have.size()])
			continue
		for i: int in want.size():
			var want_param: Dictionary = want[i]
			var have_param: Dictionary = have[i]
			if String(want_param["name"]) != String(have_param["name"]):
				problems.append("%s: parameter %d is `%s` in the spec, `%s` on Events" % [name, i, want_param["name"], have_param["name"]])
			var spec_type: String = String(want_param["type"])
			var expected: String = _expected_type(spec_type)
			var declared: String = String(have_param["type_name"])
			if expected == "":
				problems.append("%s: spec type `%s` has no entry in TYPE_MAP" % [name, spec_type])
			elif expected != declared:
				problems.append("%s.%s: spec type `%s` should be declared as `%s`, Events declares `%s`" % [name, want_param["name"], spec_type, expected, declared])
	return problems


## Spec parameter types that are still waiting on a real class: a non-built-in
## whose expected declaration is not exactly the spec's own type name.
func _placeholder_types(spec: Array) -> Array[String]:
	var out: Array[String] = []
	for sig: Dictionary in spec:
		for param: Dictionary in sig["params"]:
			var spec_type: String = String(param["type"])
			if BUILT_IN_TYPES.has(spec_type):
				continue
			if _expected_type(spec_type) == spec_type:
				continue
			if not out.has(spec_type):
				out.append(spec_type)
	return out


# --- the conformance tests ------------------------------------------------

func test_the_spec_table_parses_and_names_every_signal_it_documents() -> void:
	var spec: Array[Dictionary] = _spec_signals()
	assert_eq(spec.size(), 37, "the spec's Events bus declares 37 signals")
	var names: Array[String] = []
	for sig: Dictionary in spec:
		names.append(String(sig["name"]))
	assert_eq(names.size(), 37)
	assert_true(names.has("hit_landed"))
	assert_true(names.has("miner_rescued"), "the last signal in the spec block parses too")
	assert_false(_spec_client_signals().is_empty(), "the client-emitted list parses out of the spec")


func test_signal_names_match_the_spec_exactly_with_no_extras_and_none_missing() -> void:
	var problems: Array[String] = _name_mismatches(_spec_signals(), _runtime_signals())
	assert_eq(problems, [] as Array[String], "Events signal names match SPEC-effect-system.md")


func test_every_signal_has_the_spec_parameter_names_count_and_type() -> void:
	var problems: Array[String] = _param_mismatches(_spec_signals(), _runtime_signals())
	assert_eq(problems, [] as Array[String], "Events parameter names, order, count and types match the spec")


func test_real_classes_are_declared_not_their_placeholders() -> void:
	var runtime: Dictionary = _runtime_signals()
	# `RunResult` and `HitData` both exist in this repo, so their signals must
	# name them rather than the `RefCounted` / `Node` base.
	for sig_name: String in ["run_ended"]:
		assert_true(runtime.has(sig_name), sig_name)
		var args: Array = runtime[sig_name]
		assert_eq(String(args[0]["type_name"]), "RunResult", "run_ended takes the real RunResult")
	for sig_name: String in ["hit_landed", "crit_landed", "player_damaged", "enemy_killed", "elite_killed"]:
		assert_true(runtime.has(sig_name), sig_name)
		var args: Array = runtime[sig_name]
		var hit_index: int = 0 if sig_name in ["hit_landed", "crit_landed"] else 1
		assert_eq(String(args[hit_index]["type_name"]), "HitData", "%s carries the hit payload class" % sig_name)


func test_the_specs_client_emitted_signals_are_all_present() -> void:
	var client_signals: Array[String] = _spec_client_signals()
	assert_eq(client_signals.size(), CLIENT_SIGNAL_COUNT, "the spec names five client-emitted signals: %s" % str(client_signals))
	assert_eq(client_signals, ["hit_landed", "enemy_killed", "relic_picked", "room_cleared", "currency_gained"] as Array[String])
	var runtime: Dictionary = _runtime_signals()
	for name: String in client_signals:
		assert_true(runtime.has(name), "%s is on the bus so clients can re-emit it" % name)


func test_events_exposes_signals_only_and_no_public_methods_or_state() -> void:
	var events: Node = _events()
	assert_not_null(events)
	if events == null:
		return
	for method: Dictionary in events.get_script().get_script_method_list():
		assert_true(String(method["name"]).begins_with("_"), "Events declares no public method, found `%s`" % method["name"])
	for prop: Dictionary in events.get_script().get_script_property_list():
		assert_eq(int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE, 0, "Events declares no `var`, found `%s`" % prop["name"])


func test_the_node_signal_list_agrees_with_the_script_declaration() -> void:
	var events: Node = _events()
	assert_not_null(events)
	if events == null:
		return
	var declared: Dictionary = _runtime_signals()
	var on_node: Dictionary = {}
	for entry: Dictionary in events.get_signal_list():
		on_node[String(entry["name"])] = true
	# `get_signal_list()` is the wider view: it carries Node's own signals too.
	# Every declared bus signal must be in it, and nothing beyond the bus may
	# appear that a bare Node does not already have.
	assert_true(declared.size() < on_node.size(), "get_signal_list() also reports Node's own signals")
	for name: String in declared:
		assert_true(on_node.has(name), "%s is queryable through Events.get_signal_list()" % name)
	var plain: Node = Node.new()
	var node_own: Dictionary = {}
	for entry: Dictionary in plain.get_signal_list():
		node_own[String(entry["name"])] = true
	plain.free()
	var problems: Array[String] = []
	for name: String in on_node:
		if not declared.has(name) and not node_own.has(name):
			problems.append(name)
	assert_eq(problems, [] as Array[String], "the node exposes no signal the script does not declare")
	for name: String in node_own:
		assert_true(on_node.has(name), "Node's own signal `%s` survives on the autoload" % name)


func test_every_placeholder_type_is_pinned_to_a_todo_with_its_owner() -> void:
	var placeholders: Array[String] = _placeholder_types(_spec_signals())
	assert_true(placeholders.size() > 0, "the bus still carries placeholders for Dev A's classes")
	var todos: Array[String] = []
	for raw: String in _read_lines(EVENTS_SCRIPT_PATH):
		var line: String = raw.strip_edges()
		if line.begins_with("## TODO("):
			todos.append(line)
	assert_eq(todos.size(), placeholders.size(), "one TODO line per placeholder type: %s" % str(todos))
	var pinned: Array[String] = []
	for line: String in todos:
		var m: RegExMatch = _todo_re.search(line)
		assert_not_null(m, "TODO line is not in the pinned format: %s" % line)
		if m == null:
			continue
		assert_false(String(m.get_string(1)).is_empty(), "the TODO names its owning module")
		pinned.append(String(m.get_string(2)))
	for spec_type: String in placeholders:
		assert_true(pinned.has(spec_type), "placeholder `%s` has a TODO naming the class that replaces it" % spec_type)


func test_the_placeholder_pins_are_specific_about_who_unblocks_them() -> void:
	var expected_owners: Dictionary[String, String] = {
		"HitInfo": "combat-core",
		"Projectile": "combat-core",
		"Enemy": "enemies-ai",
		"Room": "floor-generation",
		"Pickup": "run-economy",
		"RelicData": "relics",
		"SynergyData": "relics",
		"WeaponData": "weapons",
		"MutationData": "weapons",
		"AbilityData": "abilities",
		"AscensionData": "classes-characters",
		"StatusEffects.Status": "stats-status",
	}
	var owners: Dictionary[String, String] = {}
	for raw: String in _read_lines(EVENTS_SCRIPT_PATH):
		var line: String = raw.strip_edges()
		var m: RegExMatch = _todo_re.search(line)
		if m == null:
			continue
		owners[String(m.get_string(2))] = String(m.get_string(1))
	assert_eq(owners, expected_owners, "every placeholder names the module that owns the real class")


func test_the_conformance_helpers_catch_a_dropped_signal_a_renamed_parameter_and_a_wrong_type() -> void:
	var spec: Array = _spec_signals()
	var runtime: Dictionary = _runtime_signals()
	assert_eq(_name_mismatches(spec, runtime), [] as Array[String], "positive control: the real bus conforms")
	assert_eq(_param_mismatches(spec, runtime), [] as Array[String], "positive control: the real parameters conform")

	var dropped: Dictionary = runtime.duplicate(true)
	dropped.erase("hit_landed")
	assert_true(_name_mismatches(spec, dropped).size() > 0, "a missing signal is reported")

	var extra: Dictionary = runtime.duplicate(true)
	extra["made_up_signal"] = [] as Array[Dictionary]
	assert_true(_name_mismatches(spec, extra).size() > 0, "an undeclared signal is reported")

	var renamed: Dictionary = runtime.duplicate(true)
	(renamed["run_started"] as Array)[0]["name"] = "not_the_spec_name"
	assert_true(_param_mismatches(spec, renamed).size() > 0, "a renamed parameter is reported")

	var retyped: Dictionary = runtime.duplicate(true)
	(retyped["hit_landed"] as Array)[0]["type_name"] = "RefCounted"
	assert_true(_param_mismatches(spec, retyped).size() > 0, "a placeholder type left in place is reported")

	var invented: Dictionary = runtime.duplicate(true)
	(invented["enemy_spawned"] as Array)[0]["type_name"] = "RefCounted"
	assert_true(_param_mismatches(spec, invented).size() > 0, "an invented type is reported")
