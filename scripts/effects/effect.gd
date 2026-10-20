class_name Effect
extends Node
## Base for relic, mutation, synergy, class passive, Ascension and skill node
## effects (SPEC-effect-system). Owned by effect-system.
##
## Sync: host only. Effects attach and run on the host for every player,
## including remote ones; clients hold no `Effect` instances and see spawned
## results through the spawners plus HUD state from the replicated
## `RunPlayerState`. Nothing here reads input, writes a replicated field, or
## branches on `multiplayer`.
##
## An `Effect` is the only place a content item changes the game: it listens to
## the `Events` bus, adds `StatBlock` modifiers through handles, opens timers
## and spawns things. `detach()` is therefore the point of the class — it must
## leave no modifier, no timer and no connection behind, because a relic
## dropped at a Shrine or an effect torn down on room exit otherwise keeps
## changing the game after it is gone. Every stat change goes through
## `modify()`; no base stat is ever written here.

## Child node the `StatBlock` component lives on (the player scene's layout).
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
## Child node the `StatusEffects` component lives on (stats-status, W4-B4).
const STATUS_NODE: NodePath = ^"StatusEffects"
## Child node an entity's `Hurtbox` lives on (combat-core, W2-A2).
const HURTBOX_NODE: NodePath = ^"Hurtbox"
## The method `deal_damage` delivers a hit to, and the one `apply_status`
## applies through. Called dynamically (never as a typed call) because both
## components are owned by other modules and their classes do not exist yet:
## `StatusEffects` is W4-B4's and `Hurtbox` is Dev A's.
const DAMAGE_SINK_METHOD: StringName = &"receive"
const STATUS_METHOD: StringName = &"apply_status"
## The tag `deal_damage` stamps on a hit it produced, so a later listener can
## tell an effect's damage from a weapon's (SPEC-effect-system, "Effect base
## class": "increments proc depth, tags proc").
const PROC_TAG: StringName = &"proc"
## Seed for an effect's own generator when no run is live to take one from.
## Fixed rather than clock-derived so the same inputs replay the same draws,
## which is what makes `chance()` testable without a live run.
const DEFAULT_RNG_SEED: int = 1

## The class name a signal's argument must carry to be the event's player
## (SPEC-effect-system, "Events bus").
const PLAYER_CLASS: String = "Player"
## Returned by `_player_argument_index()` for a signal with no `Player`
## argument: nothing to filter on.
const NO_PLAYER_ARGUMENT: int = -1
## One forwarder per signal arity, indexed by it. `Callable.bind()` appends its
## arguments *after* the signal's own, so a single method cannot receive a
## variable number of event arguments ahead of the bound pair; one method per
## arity receives them positionally instead. Five covers every signal on the
## bus (the widest, `status_applied`, carries four).
const DISPATCH_METHODS: Array[StringName] = [
	&"_dispatch0", &"_dispatch1", &"_dispatch2", &"_dispatch3", &"_dispatch4",
]

## The player this effect belongs to. Set by `attach()`.
var player: Player = null
## The content this effect came from (`RelicData`, `MutationData`, ...). Its
## `id` is the effect's id: the `StatBlock` modifier source, and (from W4-B3)
## the tag that stops the effect reacting to its own hits.
var source: ContentData = null
## Duplicates (a relic picked twice), rank (skill node) or upgrade rank
## (ability). Every helper that scales reads this.
var stacks: int = 1
## The `StatBlock` every stat helper writes through, resolved from `player` on
## attach. A double or a test may set it before attach. Null means the player
## carries no `StatBlock` component (the player scene's component nodes are
## bare until their owning module lands), and each stat helper then warns and
## does nothing rather than failing silently.
var stat_block: StatBlock = null
## The generator `chance()` draws from. The host owns it: `EffectHost` (W4-B4,
## goal G14) hands every effect the run's generator on attach so one seed
## replays a whole run's procs. An effect with no host of its own makes one,
## seeded from the run seed, so the draw is never a global roll function and is
## still reproducible. A caller may replace it (the tests seed it directly).
var rng: RandomNumberGenerator = null
## The proc depth of the event this effect is currently handling, so
## `deal_damage` produces a result one link deeper than its trigger
## (`proc_depth = trigger.proc_depth + 1`, SPEC-effect-system "Proc chain
## limits"). The dispatch wrapper sets it while a handler runs — that wrapper,
## the depth-3 gate and the self-retrigger check are W4-B3 (goal G16); until
## then it stays 0, the depth of a hit a weapon landed.
var trigger_depth: int = 0

## `StatBlock` modifier handles to remove on detach.
var _handles: Array[int] = []
## Timers parented to this effect, freed on detach.
var _timers: Array[Timer] = []
## Loops opened by `every_seconds()`, keyed by a per-effect id so a handler can
## be identified after the fact: `{interval, callable, signal, connection}`. The
## signal and the connection are what `detach()` disarms; the id is how a
## timeout finds the loop it belongs to.
var _periodic: Dictionary[int, Dictionary] = {}
## Id handed to the next `every_seconds()` loop. Never reused, so a timeout that
## arrives after its loop was stopped cannot be mistaken for a live one.
var _next_periodic_id: int = 0
## {signal: Signal, callable: Callable} pairs, disconnected on detach. Kept as
## an explicit list because a connection cannot be found again by name alone
## once a wrapper is involved, and a lambda can never be disconnected.
var _connections: Array[Dictionary] = []
## Keys `once_per_room()` has already granted this room. Cleared on every
## `room_entered`, and by `attach()`/`detach()` so a cycle never inherits the
## previous one's budget.
var _room_keys: Dictionary[StringName, bool] = {}
var _attached: bool = false


## Attaches this effect to `player` for `source` at `stacks`. Resolves the
## stat block, then calls `_on_attach()` once. A second attach without an
## intervening detach is refused with a warning: an effect belongs to exactly
## one player at a time, and a second `_on_attach()` would double its
## modifiers.
func attach(player: Player, source: ContentData, stacks: int = 1) -> void:
	if _attached:
		push_warning("[effect] %s is already attached; detach() it first" % source_id())
		return
	self.player = player
	self.source = source
	self.stacks = maxi(stacks, 1)
	stat_block = _resolve_stat_block()
	_attached = true
	_room_keys.clear()
	_connect_tracked(Events.room_entered, _on_room_entered)
	_on_attach()


## Tears the effect down completely: every modifier handle it added, every
## timer it parented and every connection it made. Safe on an unattached
## effect (a no-op). `_on_detach()` runs last, so a subclass tears down against
## a state that already holds no handles, timers or connections — anything a
## subclass registers in `_on_detach()` itself would leak.
func detach() -> void:
	if not _attached:
		return
	_release_handles()
	_free_timers()
	_stop_periodic()
	_disconnect_all()
	_room_keys.clear()
	_attached = false
	_on_detach()


## True while the effect is attached. `EffectHost` reads it before re-adding a
## source and the debug overlay reads it to list live effects.
func is_attached() -> bool:
	return _attached


## The effect's id: `source.id`. Used as the `StatBlock` modifier source and,
## from W4-B3, as the tag that blocks self-retriggering. Empty when the effect
## was attached with no source.
func source_id() -> StringName:
	if source == null:
		return &""
	return source.id


## Called at the end of `attach()`, once per attach/detach cycle. Subclasses
## add their modifiers, timers and listeners here.
func _on_attach() -> void:
	pass


## Called at the end of `detach()`, once per attach/detach cycle, after the
## base cleanup. Subclasses release only their own extra state here.
func _on_detach() -> void:
	pass


## Connects `callable` to `sig` and records the connection, so `detach()`
## disconnects it. `callable` must be a named method on this effect: a lambda
## cannot be disconnected and never fires under the test harness.
##
## Where the signal declares a `Player` argument, the connection is filtered
## through `_forward()` and the handler runs only for events belonging to this
## effect's own player — an effect on player 1 never reacts to player 2's dodge,
## hit, pickup or room entry. A signal with no `Player` argument is connected
## untouched, so the handler is the named method itself (`hit_landed` carries
## the attacker inside `HitData` and is deliberately unfiltered).
func listen(sig: Signal, callable: Callable) -> void:
	if not callable.is_valid():
		push_warning("[effect] %s: listen() needs a callable" % source_id())
		return
	var args: Array[Dictionary] = _signal_arguments(sig)
	var index: int = _player_argument_index(args)
	if index == NO_PLAYER_ARGUMENT:
		_connect_tracked(sig, callable)
		return
	if args.size() >= DISPATCH_METHODS.size():
		push_warning("[effect] %s: %s carries more arguments than the filter forwards, connected unfiltered" % [source_id(), sig.get_name()])
		_connect_tracked(sig, callable)
		return
	_connect_tracked(sig, Callable(self, DISPATCH_METHODS[args.size()]).bind(index, callable))


## True the first time `key` is asked for in this room and false on every later
## ask; every key is granted again when `room_entered` fires. The base of every
## "once per room" relic (Second Wind, Cracked Shell, Panic Button): `key` is
## the caller's own name for the thing it is spending, so two effects — and two
## abilities on one effect — never share a budget by accident.
func once_per_room(key: StringName) -> bool:
	if _room_keys.has(key):
		return false
	_room_keys[key] = true
	return true


## Runs `callable` every `interval` seconds of *this effect's own player's*
## scaled time — the spec's pinned clock for a periodic relic (Clockwork Heart's
## "every 10 s"), and the reason `every_seconds` exists at all rather than a
## plain engine `Timer`.
##
## The loop is armed with `TimeManager.timer()` on the effect's player, so:
##
## - a time stop or slow aimed at the enemies never pauses it — a relic's own
##   clock keeps counting while the dungeon is frozen, which is what makes
##   Clockwork Heart a relic rather than a casualty of someone else's ult;
## - a pause aimed at this player's own node (hit-stop) does pause it, because
##   the player's scaled time is the clock's rate;
## - and it is scaled rather than engine time, so nothing here ever reaches for
##   the engine's global time scale (which would freeze every peer).
##
## The player is put in `TimeManager`'s PLAYER group here. Registration is
## idempotent, and doing it at the point of use keeps the loop correct for any
## player whose own registration has not run: an unregistered node silently
## reads the default scale, which would make the exemption above accidental
## rather than declared.
##
## The loop is tracked for `detach()`: the tick is disconnected from the armed
## timer and the loop forgotten, so a relic dropped at a Shrine stops ticking
## immediately and stops holding its effect alive through the timer. Nothing
## else cancels the armed tick — it is `TimeManager`'s own one-shot and expires
## silently, with no listener and no reference to this effect.
func every_seconds(interval: float, callable: Callable) -> void:
	if interval <= 0.0:
		push_warning("[effect] %s: every_seconds() needs a positive interval" % source_id())
		return
	if not callable.is_valid():
		push_warning("[effect] %s: every_seconds() needs a callable" % source_id())
		return
	if player == null:
		push_warning("[effect] %s: every_seconds() needs an attached player" % source_id())
		return
	TimeManager.set_group(player, TimeManager.Group.PLAYER)
	var id: int = _next_periodic_id
	_next_periodic_id += 1
	_periodic[id] = {
		"interval": interval,
		"callable": callable,
		"signal": Signal(),
		"connection": Callable(),
	}
	_arm_periodic(id)


## Adds a stat modifier carrying this effect's id as its source, and records
## the returned handle so `detach()` removes exactly this effect's change.
## Never writes a base stat.
func modify(stat: StatBlock.Stat, flat: float = 0.0, percent: float = 0.0) -> void:
	if stat_block == null:
		push_warning("[effect] %s: no StatBlock on the player, modifier dropped" % source_id())
		return
	_handles.append(stat_block.add_modifier(stat, flat, percent, source_id()))


## Rolls a host-side probability. The two extremes short-circuit without
## drawing, so a guaranteed or impossible proc never advances the run's
## generator stream and one effect's certainty cannot desynchronise another's
## rolls. Everything between them draws from `rng` (the host's run generator,
## created on first use when nothing supplied one) — never a global roll
## function, so a seed replays the sequence. Loot-type procs that scale with
## Luck go through `chance_lucky()` (W4-B8, run-economy) instead.
func chance(p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return _resolve_rng().randf() < p


## Applies a status to `target` through its `StatusEffects` component
## (stats-status). The source argument the component records is this effect, so
## `Events.status_applied(target, status, stacks, source)` names the relic that
## applied it. `status` is `StatusEffects.Status` — an int until W4-B4's
## component lands, at which point this parameter is retyped to the enum. A
## target with no component (an enemy that is not yet wired, a double) is a
## warned no-op rather than a crash.
func apply_status(target: Node, status: int, stacks: int = 1) -> void:
	if target == null:
		push_warning("[effect] %s: apply_status() needs a target" % source_id())
		return
	var component: Node = _status_component(target)
	if component == null:
		push_warning("[effect] %s: %s carries no StatusEffects component, status %d dropped" % [
			source_id(), target.name, status])
		return
	component.call(STATUS_METHOD, status, stacks, self)


## Deals a hit to `target`: stamps its proc depth one link past the trigger,
## tags it `proc`, then hands it to the target's `Hurtbox` (combat-core), which
## computes the damage, applies it to `Health` and announces it on
## `Events.hit_landed`. This helper deliberately does not emit a combat event
## itself — the emitters are the owning modules (SPEC-effect-system, "Events
## bus") — so a chain continues through the hurtbox, and the hit is stamped
## before it gets there. A target with no hurtbox is a warned no-op.
func deal_damage(target: Node, hit: HitData) -> void:
	if target == null or hit == null:
		push_warning("[effect] %s: deal_damage() needs a target and a hit" % source_id())
		return
	hit.proc_depth = trigger_depth + 1
	if not hit.tags.has(PROC_TAG):
		hit.tags.append(PROC_TAG)
	var sink: Node = target.get_node_or_null(HURTBOX_NODE)
	if sink == null or not sink.has_method(DAMAGE_SINK_METHOD):
		push_warning("[effect] %s: %s has no Hurtbox to receive the hit, damage not applied" % [
			source_id(), target.name])
		return
	sink.call(DAMAGE_SINK_METHOD, hit)


## The `StatusEffects` component on `target`, or null when it carries none. A
## `has_method` check rather than a typed cast because the component's class is
## W4-B4's and does not exist yet; when it lands this becomes an `is
## StatusEffects` check with no call-site change.
func _status_component(target: Node) -> Node:
	var component: Node = target.get_node_or_null(STATUS_NODE)
	if component == null or not component.has_method(STATUS_METHOD):
		return null
	return component


## The generator to draw from: the effect's own when one is set (a host's
## injection or a test's seed), otherwise one created here and seeded from the
## live run. Created once and kept, so the stream is continuous.
func _resolve_rng() -> RandomNumberGenerator:
	if rng != null:
		return rng
	rng = RandomNumberGenerator.new()
	rng.seed = _host_seed()
	return rng


## The seed an effect's own generator starts from: the live run's, so a replay
## of one seed replays the same procs, otherwise the fixed fallback. Read from
## `GameState` rather than rolled, because a clock-derived seed would make every
## draw in a test un-reproducible.
func _host_seed() -> int:
	if GameState.run != null:
		return GameState.run.seed
	return DEFAULT_RNG_SEED


## Opens a one-shot `Timer` parented to this effect, tracked in `_timers` so
## `detach()` frees it, and connects `callable` (a named method) to its
## `timeout`. Plain engine time: anything gameplay-relevant that must obey a
## time stop goes through `every_seconds()` (TimeManager-scaled) instead, and
## a subclass must never parent a gameplay timer any other way, or `detach()`
## cannot free it.
func _start_timer(seconds: float, callable: Callable = Callable()) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(seconds, 0.0)
	add_child(timer)
	if callable.is_valid():
		timer.timeout.connect(callable)
	_timers.append(timer)
	timer.start()
	return timer


## Arms the next tick of loop `id` on `TimeManager`'s scaled timer for this
## effect's player, recording the signal and the connection so `detach()` can
## disarm it. One armed tick per loop rather than a chain: each tick re-arms
## itself from `_on_periodic_timeout`, so a stopped loop leaves nothing behind
## but the single tick already in flight.
func _arm_periodic(id: int) -> void:
	var entry: Dictionary = _periodic.get(id, {}) as Dictionary
	if entry.is_empty():
		return
	var sig: Signal = TimeManager.timer(player, float(entry["interval"]))
	var connection: Callable = _on_periodic_timeout.bind(id)
	sig.connect(connection)
	entry["signal"] = sig
	entry["connection"] = connection


## One tick of an `every_seconds()` loop: runs the loop's callable, then arms the
## next tick unless the callable detached the effect. The re-arm is skipped
## rather than refused, because a relic that spends its last tick tearing itself
## down (Second Wind, Panic Button) must not resurrect its own loop.
func _on_periodic_timeout(id: int) -> void:
	var entry: Dictionary = _periodic.get(id, {}) as Dictionary
	if entry.is_empty():
		return
	var callable: Callable = entry["callable"]
	callable.call()
	if _periodic.has(id):
		_arm_periodic(id)


## Disarms and forgets every `every_seconds()` loop: each tick is disconnected
## from its armed timer, so the pending one fires into nothing and holds no
## reference to this effect. The timer itself is `TimeManager`'s object and
## expires on its own; nothing here reaches into the manager's list.
func _stop_periodic() -> void:
	for id: int in _periodic.keys():
		var entry: Dictionary = _periodic[id]
		var sig: Signal = entry["signal"]
		var connection: Callable = entry["connection"]
		if connection.is_valid() and sig.is_connected(connection):
			sig.disconnect(connection)
	_periodic.clear()


## The stat block to write through: an explicitly set one wins, otherwise the
## player's `StatBlock` child when that node carries the component. Null (with
## a warning) when it does not, so an effect on a component-less double is
## inert rather than crashing.
func _resolve_stat_block() -> StatBlock:
	if stat_block != null:
		return stat_block
	if player == null:
		return null
	var node: Node = player.get_node_or_null(STAT_BLOCK_NODE)
	if node is StatBlock:
		return node as StatBlock
	push_warning("[effect] %s: the player has no StatBlock component" % source_id())
	return null


## Removes every modifier this effect added, by handle, and forgets the
## handles. Handles rather than `remove_source()`: two effects on one player
## must never be able to take each other's modifiers down, even if they were
## built from the same content id.
func _release_handles() -> void:
	if stat_block != null:
		for handle: int in _handles:
			stat_block.remove_modifier(handle)
	_handles.clear()


## Frees every timer this effect opened and forgets them. `queue_free()` so a
## detach from inside a signal handler is safe; the nodes leave the tree at
## the end of the frame.
func _free_timers() -> void:
	for timer: Timer in _timers:
		if is_instance_valid(timer):
			timer.queue_free()
	_timers.clear()


## Disconnects every connection this effect made and forgets the pairs.
func _disconnect_all() -> void:
	for entry: Dictionary in _connections:
		var sig: Signal = entry["signal"]
		var callable: Callable = entry["callable"]
		if sig.is_connected(callable):
			sig.disconnect(callable)
	_connections.clear()


## Connects `callable` and records the pair for `detach()`. The only place this
## class connects anything, so no subscription can escape the teardown.
func _connect_tracked(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		return
	sig.connect(callable)
	_connections.append({"signal": sig, "callable": callable})


## Clears every `once_per_room()` key. Subscribed directly, never through
## `listen()`: the reset is the room's, not the entering player's, and a
## teammate walking in must not leave this effect's relic spent from the room
## before (SPEC-effect-system, "returns true the first time per room").
func _on_room_entered(_room: Node, _player: Player) -> void:
	_room_keys.clear()


## The arguments `sig` is declared with on the `Events` bus, or an empty array
## when it is not one of the bus's signals. Read from the autoload's own script
## (the `test_events_bus.gd` precedent) so a new or retyped signal is filtered
## without a second list here to keep in step.
func _signal_arguments(sig: Signal) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var script: Script = Events.get_script()
	if script == null:
		return found
	for entry: Dictionary in script.get_script_signal_list():
		if StringName(entry.get("name", &"")) != sig.get_name():
			continue
		var declared: Array = entry.get("args", [])
		for argument: Variant in declared:
			if argument is Dictionary:
				found.append(argument)
		return found
	return found


## The position of `sig`'s `Player` argument, or `NO_PLAYER_ARGUMENT` when it
## has none. Taken from the declaration rather than sniffed off a call, so the
## same signal is filtered the same way for every emit.
func _player_argument_index(args: Array[Dictionary]) -> int:
	for i: int in args.size():
		var argument: Dictionary = args[i]
		if int(argument.get("type", TYPE_NIL)) != TYPE_OBJECT:
			continue
		if String(argument.get("class_name", "")) == PLAYER_CLASS:
			return i
	return NO_PLAYER_ARGUMENT


## Calls `callable` with the event's own `values`, unless the event's `Player`
## argument says the event belongs to someone else. The negative control for
## the filter: a foreign event returns without calling anything at all.
func _forward(values: Array, argument_index: int, callable: Callable) -> void:
	if argument_index >= 0 and argument_index < values.size():
		if values[argument_index] != player:
			return
	callable.callv(values)


## One forwarder per signal arity: the event's arguments arrive first and the
## bound `(argument_index, callable)` pair last. See `DISPATCH_METHODS`.
func _dispatch0(argument_index: int, callable: Callable) -> void:
	_forward([], argument_index, callable)


func _dispatch1(a: Variant, argument_index: int, callable: Callable) -> void:
	_forward([a], argument_index, callable)


func _dispatch2(a: Variant, b: Variant, argument_index: int, callable: Callable) -> void:
	_forward([a, b], argument_index, callable)


func _dispatch3(a: Variant, b: Variant, c: Variant, argument_index: int, callable: Callable) -> void:
	_forward([a, b, c], argument_index, callable)


func _dispatch4(a: Variant, b: Variant, c: Variant, d: Variant, argument_index: int, callable: Callable) -> void:
	_forward([a, b, c, d], argument_index, callable)
