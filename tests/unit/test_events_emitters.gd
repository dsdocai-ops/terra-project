extends GutTest
## `Events` emitter coverage — effect-system, W4-B1 (the emitter half).
##
## `tests/unit/test_events_bus.gd` pins the bus's *shape*. This file pins its
## *use*: every signal in `SPEC-effect-system.md` "Events bus" is reachable
## through exactly one named method on `tests/helpers/event_emitter.gd`, each
## of those calls carries arguments of the declared arity and reaches a
## listener, and the emitters Dev B already owns fire from their real owner
## (`GameState` for `run_started`/`run_ended`/`room_cleared`,
## `NetworkManager` for `player_downed`/`player_revived`).
##
## Dev A's production emitters are combat-core's W4-A4. The nine signals that
## task names are recorded as `blocked on Dev A (W4-A4)` in the helper's doc
## comment and in `tasks/todo.md`; the helper still emits them, so an effect
## that listens to a hit can be tested before Dev A's lane lands.
##
## The spec's signal table is parsed from the document at run time, so the
## coverage check cannot drift away from it. Listeners are connected as named
## method callbacks, never lambdas (LESSONS: `.connect(lambda)` never fires
## under GUT).
##
## Sync: read-only inspection plus host-side emitter calls. Owned by
## effect-system.

const SPEC_PATH: String = "res://specs/SPEC-effect-system.md"
const HELPER_PATH: String = "res://tests/helpers/event_emitter.gd"
const TODO_PATH: String = "res://tasks/todo.md"
const SPEC_HEADING: String = "### Events bus"

## The nine signals W4-A4 names as combat-core's to emit, in that task's own
## order. Hard-coded here as well as in the helper so the two cannot drift.
const DEV_A_OWNED: Array[StringName] = [
	&"hit_landed",
	&"crit_landed",
	&"player_damaged",
	&"heavy_attack_released",
	&"weapon_swapped",
	&"projectile_fired",
	&"enemy_killed",
	&"enemy_spawned",
	&"player_dodged",
]

const BLOCKED_LINE: String = "blocked on Dev A (W4-A4)"

var _emitter: EventEmitterHelper = null
## Player and node doubles this file created; never added to the tree.
var _doubles: Array[Node] = []
var _started_seeds: Array[int] = []
var _ended_results: Array[RunResult] = []
var _downed: Array[Player] = []
var _revived: Array[Player] = []
var _revived_by: Array[Player] = []


## A named-method listener. GUT never fires a connected lambda, so every
## signal below is connected through `Callable(recorder, "on_<arity>")`; the
## method name is chosen from the signal's declared parameter count because a
## handler that does not match the signal's arity is an engine error.
class Recorder extends RefCounted:
	var calls: int = 0
	var arg_count: int = -1
	var first_arg: Variant = null

	func on_0() -> void:
		calls += 1
		arg_count = 0

	func on_1(a: Variant) -> void:
		calls += 1
		arg_count = 1
		first_arg = a

	func on_2(a: Variant, _b: Variant) -> void:
		calls += 1
		arg_count = 2
		first_arg = a

	func on_3(a: Variant, _b: Variant, _c: Variant) -> void:
		calls += 1
		arg_count = 3
		first_arg = a

	func on_4(a: Variant, _b: Variant, _c: Variant, _d: Variant) -> void:
		calls += 1
		arg_count = 4
		first_arg = a


func before_each() -> void:
	_emitter = EventEmitterHelper.new()
	# A solo session is a host with one peer — the same code path co-op uses,
	# which is what `GameState.start_run` and the room counter require
	# (the pattern test_game_state_run.gd established).
	NetworkManager.start_solo()
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_run_summary = ""
	_started_seeds.clear()
	_ended_results.clear()
	_downed.clear()
	_revived.clear()
	_revived_by.clear()
	Events.run_started.connect(_on_run_started)
	Events.run_ended.connect(_on_run_ended)
	Events.player_downed.connect(_on_player_downed)
	Events.player_revived.connect(_on_player_revived)


func after_each() -> void:
	if Events.run_started.is_connected(_on_run_started):
		Events.run_started.disconnect(_on_run_started)
	if Events.run_ended.is_connected(_on_run_ended):
		Events.run_ended.disconnect(_on_run_ended)
	if Events.player_downed.is_connected(_on_player_downed):
		Events.player_downed.disconnect(_on_player_downed)
	if Events.player_revived.is_connected(_on_player_revived):
		Events.player_revived.disconnect(_on_player_revived)
	# A live run holds GameState's own Events subscriptions open; ending it is
	# the public path a real quit takes, and it is what leaves the bus clean
	# for the next test file (LESSONS: autoload state bleeds across files).
	if GameState.run != null and NetworkManager.is_host:
		GameState.end_run(RunEndReason.Reason.ABORT)
	_emitter.cleanup()
	_emitter = null
	for double: Node in _doubles:
		double.free()
	_doubles.clear()
	NetworkManager.players.clear()
	NetworkManager.disconnect_all()
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_run_summary = ""


# --- spec parsing (same source of truth as test_events_bus.gd) --------------

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "could not open %s" % path)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _spec_signal_names() -> Array[StringName]:
	var out: Array[StringName] = []
	var in_block: bool = false
	for raw: String in _read_text(SPEC_PATH).split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("### "):
			in_block = line == SPEC_HEADING
			continue
		if not in_block or not line.begins_with("signal "):
			continue
		var body: String = line.split("#")[0].strip_edges()
		var re := RegEx.new()
		re.compile("^signal\\s+(\\w+)\\(")
		var m: RegExMatch = re.search(body)
		assert_not_null(m, "spec line did not parse: %s" % line)
		if m != null:
			out.append(StringName(m.get_string(1)))
	return out


func _signal_arities() -> Dictionary:
	var out: Dictionary = {}
	var events: Node = _events()
	assert_not_null(events, "the Events autoload is registered")
	if events == null:
		return out
	for entry: Dictionary in events.get_script().get_script_signal_list():
		var args: Array = entry["args"] as Array
		out[StringName(entry["name"])] = args.size()
	return out


func _events() -> Node:
	return get_tree().root.get_node_or_null("Events")


# --- pure comparison helper (so the negative control can drive it) ----------

## Everything wrong with an emitter table: a spec signal with no method, a
## method with no spec signal, or a signal with more than one method.
func _coverage_problems(spec_names: Array[StringName], methods: Array[String]) -> Array[String]:
	var problems: Array[String] = []
	for name: StringName in spec_names:
		var wanted: String = "emit_%s" % name
		var hits: int = 0
		for method: String in methods:
			if method == wanted:
				hits += 1
		if hits == 0:
			problems.append("no emitter method for %s" % name)
		elif hits > 1:
			problems.append("%d emitter methods for %s" % [hits, name])
	for method: String in methods:
		if not spec_names.has(StringName(method.trim_prefix("emit_"))):
			problems.append("emitter method with no spec signal: %s" % method)
	return problems


## The `emit_`-prefixed methods the helper's own script declares. Deliberately
## `get_script_method_list()` and not `get_method_list()`, because the latter
## also returns the inherited `Object.emit_signal()` — which would read as an
## extra emitter method and fail the coverage check for the wrong reason.
func _emitter_methods() -> Array[String]:
	var out: Array[String] = []
	if _emitter == null:
		return out
	for entry: Dictionary in _emitter.get_script().get_script_method_list():
		var name: String = String(entry["name"])
		if name.begins_with("emit_"):
			out.append(name)
	return out


# --- coverage ---------------------------------------------------------------

func test_every_spec_signal_has_exactly_one_emitter_method() -> void:
	var spec_names: Array[StringName] = _spec_signal_names()
	assert_gt(spec_names.size(), 0, "the spec's Events bus table parsed")
	var methods: Array[String] = _emitter_methods()
	var problems: Array[String] = _coverage_problems(spec_names, methods)
	assert_eq(problems, [] as Array[String], "emitter coverage matches the spec")
	assert_eq(
		EventEmitterHelper.all_signal_names().size(),
		spec_names.size(),
		"the helper's declared signal list is the spec's list"
	)
	for name: StringName in spec_names:
		assert_true(
			EventEmitterHelper.all_signal_names().has(name),
			"the helper knows %s" % name
		)
		assert_true(
			_emitter.has_method(EventEmitterHelper.emitter_method_name(name)),
			"emit_%s() exists" % name
		)


func test_every_emitter_method_takes_no_arguments() -> void:
	var spec_names: Array[StringName] = _spec_signal_names()
	for entry: Dictionary in _emitter.get_script().get_script_method_list():
		var method: String = String(entry["name"])
		if not method.begins_with("emit_"):
			continue
		var args: Array = entry["args"] as Array
		assert_eq(args.size(), 0, "%s() builds its own fake arguments" % method)
	assert_eq(_emitter_methods().size(), spec_names.size(), "no extra emit_ methods")


func test_coverage_helper_reports_a_dropped_or_invented_signal() -> void:
	# Negative control (BRIEF C13): the coverage check above must be able to
	# fail. A dropped method and an invented one are both reported.
	var dropped: Array[String] = _coverage_problems(
		[&"hit_landed", &"crit_landed"] as Array[StringName],
		["emit_hit_landed"] as Array[String]
	)
	assert_eq(dropped.size(), 1, "a spec signal with no method is reported")
	var invented: Array[String] = _coverage_problems(
		[&"hit_landed"] as Array[StringName],
		["emit_hit_landed", "emit_not_a_signal"] as Array[String]
	)
	assert_eq(invented.size(), 1, "a method with no spec signal is reported")


func test_dev_a_owned_emitters_are_recorded_as_blocked() -> void:
	assert_eq(DEV_A_OWNED.size(), 9, "W4-A4 names nine signals")
	assert_eq(
		EventEmitterHelper.dev_a_owned_signals(),
		DEV_A_OWNED,
		"the helper's blocked list is W4-A4's list"
	)
	var helper_lines: PackedStringArray = _read_text(HELPER_PATH).split("\n")
	var re := RegEx.new()
	for name: StringName in DEV_A_OWNED:
		# The parentheses in the literal are escaped by hand: GDScript has no
		# `RegEx.escape`, and an unescaped pair would be read as a capture group.
		# Each line is searched on its own — `^` anchors to the string, not to a
		# line, so the pattern must be applied per line.
		re.compile("^##.*\\b%s\\b.*blocked on Dev A \\(W4-A4\\)" % String(name))
		var found: bool = false
		for line: String in helper_lines:
			if re.search(line) != null:
				found = true
				break
		assert_true(
			found,
			"%s carries a '%s' doc line in event_emitter.gd" % [name, BLOCKED_LINE]
		)
	assert_true(
		_read_text(TODO_PATH).contains(BLOCKED_LINE),
		"tasks/todo.md records '%s'" % BLOCKED_LINE
	)


# --- every emitter reaches a listener ---------------------------------------

func test_each_emitter_call_reaches_a_listener() -> void:
	var arities: Dictionary = _signal_arities()
	var spec_names: Array[StringName] = _spec_signal_names()
	for name: StringName in spec_names:
		var recorder := Recorder.new()
		var arity: int = int(arities.get(name, -1))
		assert_true(arity >= 0, "%s has a declared arity" % name)
		if arity < 0:
			continue
		var callback: Callable = Callable(recorder, "on_%d" % arity)
		Events.connect(name, callback)
		var emit_callable: Callable = _emitter.callable_for(name)
		assert_true(emit_callable.is_valid(), "callable_for(%s) is valid" % name)
		emit_callable.call()
		assert_eq(recorder.calls, 1, "%s reached its listener" % name)
		assert_eq(recorder.arg_count, arity, "%s carried %d arguments" % [name, arity])
		Events.disconnect(name, callback)


func test_callable_for_refuses_a_name_that_is_not_a_signal() -> void:
	assert_false(_emitter.callable_for(&"not_a_signal").is_valid())
	assert_true(_emitter.callable_for(&"hit_landed").is_valid())


func test_emitter_arguments_have_the_declared_types() -> void:
	# The player-first signals carry a real Player and the hit signals carry a
	# real HitData, so an effect listening to them can read the fields the
	# spec names.
	var recorder := Recorder.new()
	# `player_dodged(player, perfect)` takes two arguments, so the handler must
	# too: a handler that does not match the signal's arity is an engine error
	# (LESSONS: match an Events signal's exact arity).
	var cb: Callable = Callable(recorder, "on_2")
	Events.player_dodged.connect(cb)
	_emitter.emit_player_dodged()
	Events.player_dodged.disconnect(cb)
	assert_eq(recorder.calls, 1, "player_dodged fired")
	assert_true(recorder.first_arg is Player, "player_dodged's first argument is a Player")

	var hit_recorder := Recorder.new()
	var hit_cb: Callable = Callable(hit_recorder, "on_1")
	Events.hit_landed.connect(hit_cb)
	_emitter.emit_hit_landed()
	Events.hit_landed.disconnect(hit_cb)
	assert_eq(hit_recorder.calls, 1, "hit_landed fired")
	assert_true(hit_recorder.first_arg is HitData, "hit_landed's argument is a HitData")


# --- the emitters Dev B owns, firing from their real owners ------------------

func test_game_state_emits_run_started_and_run_ended() -> void:
	GameState.start_run(4242, 1, [_spawn_info(1)] as Array)
	assert_eq(_started_seeds, [4242] as Array[int], "GameState emitted run_started")
	assert_not_null(GameState.run, "a run is live")
	GameState.end_run(RunEndReason.Reason.ABORT)
	assert_eq(_ended_results.size(), 1, "GameState emitted run_ended once")
	assert_eq(_ended_results[0].seed, 4242, "the result carries the run's seed")


func test_the_host_counts_room_cleared_from_the_bus() -> void:
	GameState.start_run(4242, 1, [_spawn_info(1)] as Array)
	assert_eq(GameState.run.rooms_cleared, 0, "no rooms cleared yet")
	var room := _room_double()
	Events.room_cleared.emit(room)
	Events.room_cleared.emit(room)
	assert_eq(GameState.run.rooms_cleared, 2, "the host counted both room_cleared events")


func test_network_manager_emits_player_downed_and_revived() -> void:
	var one: Player = _player_double(1)
	var two: Player = _player_double(2)
	NetworkManager.players[1] = one
	NetworkManager.players[2] = two
	assert_eq(NetworkManager.apply_player_downed(1), true, "the down applied")
	assert_eq(_downed.size(), 1, "NetworkManager emitted player_downed")
	assert_eq(_downed[0], one, "the event names the peer that went down")
	assert_eq(NetworkManager.apply_player_revived(1, 2), true, "the revive applied")
	assert_eq(_revived.size(), 1, "NetworkManager emitted player_revived")
	assert_eq(_revived[0], one, "the event names the revived player")
	assert_eq(_revived_by[0], two, "the event names the reviver")


# --- doubles -----------------------------------------------------------------

func _spawn_info(peer_id: int) -> PlayerSpawnInfo:
	return PlayerSpawnInfo.new(peer_id)


## A bare `Player.new()` that is never added to the tree, so Dev A's `_ready`
## never runs (the pattern test_run_end_defeat.gd established).
func _player_double(peer_id: int) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	_doubles.append(player)
	return player


func _room_double() -> Node:
	var room := EventEmitterNodeStub.new()
	room.stub_kind = &"room"
	_doubles.append(room)
	return room


# --- named listeners ---------------------------------------------------------

func _on_run_started(seed: int) -> void:
	_started_seeds.append(seed)


func _on_run_ended(result: RunResult) -> void:
	_ended_results.append(result)


func _on_player_downed(player: Player) -> void:
	_downed.append(player)


func _on_player_revived(player: Player, by: Player) -> void:
	_revived.append(player)
	_revived_by.append(by)
