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
## How deep a proc chain may go, from SPEC-effect-system, "Proc chain limits",
## rule 1: "A proc at depth 3 does not trigger further effects (its hits still
## damage, but `hit_landed` from it is emitted with `hit.proc_depth = 3` and
## `Effect.listen` wrappers skip events with `proc_depth >= 3`)." An event whose
## hit carries this depth or more never reaches a handler; the hit itself has
## already been dealt by whoever emitted it, so damage still lands.
const MAX_PROC_DEPTH: int = 3
## The class an event's argument must be to count as "the hit this event is
## about". `HitData` is this repo's payload (stats-status); `HitInfo` is the
## combat-core name SPEC-effect-system's table uses, accepted here already so
## the swap-in is a type rename and not a second list to keep in step.
const HIT_CLASSES: Array[String] = ["HitData", "HitInfo"]

## The player this effect belongs to. Set by `attach()`.
var player: Player = null
## The content this effect came from (`RelicData`, `MutationData`, ...). Its
## `id` is the effect's id: the `StatBlock` modifier source, and the tag that
## stops this effect reacting to its own hits (SPEC-effect-system, "Proc chain
## limits", rule 2).
var source: ContentData = null
## The id suffix this effect was attached under, empty for every effect that is
## not a duplicate. SPEC-effect-system, "Proc chain limits", rule 4: "Mimic
## Crown copies the last picked relic's effect; the copy is a second `Effect`
## instance with its own id suffix so rule 2 still applies." The suffix is what
## makes the copy a *different* effect to rule 2 — without it the copy and its
## original would each suppress the other's hits (they share the content id) —
## and what keeps the two apart as `StatBlock` modifier sources, spawn
## attributions and `EffectHost` keys. Set by `EffectHost.add()`; an effect
## attached by hand has none and behaves exactly as before rule 4 existed.
##
## The copy holds the *same* `ContentData` as its original — it is a copy of the
## effect, not a second relic — so this is the only thing that distinguishes the
## two, and `source_id()` is where it is applied.
var id_suffix: StringName = &""
## The `EffectHost` this effect was attached through, set by `EffectHost.add()`.
## It is how `spawn()` and `fire_projectile()` reach the world's spawner without
## an effect ever naming a node path (SPEC-project forbids cross-module
## tree-path reach-through). Null for an effect attached by hand, which then
## spawns nothing.
var host: EffectHost = null
## Duplicates (a relic picked twice), rank (skill node) or upgrade rank
## (ability). Every helper that scales reads this.
var stacks: int = 1
## The `StatBlock` every stat helper writes through, resolved from `player` on
## attach. A double or a test may set it before attach. Null means the player
## carries no `StatBlock` component (the player scene's component nodes are
## bare until their owning module lands), and each stat helper then warns and
## does nothing rather than failing silently.
var stat_block: StatBlock = null
## The generator `chance()` draws from. The host owns it: `EffectHost`
## (effect-system, goal G14) hands every effect its player's generator on
## attach so one seed replays a whole run's procs. An effect with no host makes
## its own, seeded from the run seed, so the draw is never a global roll function
## and is
## still reproducible. A caller may replace it (the tests seed it directly).
var rng: RandomNumberGenerator = null
## The proc depth of the event this effect is currently handling, so
## `deal_damage`, `spawn` and `fire_projectile` each produce a result one link
## deeper than their trigger (`proc_depth = trigger.proc_depth + 1`,
## SPEC-effect-system "Proc chain limits"). `_forward()` sets it on the way into
## a handler and restores the previous value on the way out, so a nested proc
## sees its own event's depth and leaks nothing back out. An effect that is not
## handling an event reads 0 — the depth of a hit a weapon landed — which is the
## chain's root. An event whose hit already carries `MAX_PROC_DEPTH` never
## reaches a handler at all: that is where a chain stops. The self-retrigger
## check (rule 2) runs in the same wrapper, just before this one, and drops an
## event whose hit carries this effect's own id.
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


## The effect's id: `source.id` plus `id_suffix`, which is `source.id` itself
## for every effect that is not a duplicate. Used as the `StatBlock` modifier
## source and as the id the no-self-retrigger check matches (rule 2: an effect
## never reacts to a hit tagged with its own id). Empty when the effect was
## attached with no source, in which case there is no id to match and nothing is
## suppressed.
##
## A Mimic Crown copy reports the **suffixed** id here, which is what rule 4's
## "so rule 2 still applies" means: the copy and its original hold the same
## `ContentData`, so without the suffix a hit tagged with the relic's id would
## suppress both of them. `EffectHost.suffixed_id()` is the one place the form
## is built, so the copy is keyed, named, attributed and self-tag-checked with
## the same string.
func source_id() -> StringName:
	if source == null:
		return &""
	return EffectHost.suffixed_id(source.id, id_suffix)


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
## A listener goes through `_forward()` when there is something there to do:
##
## - where the signal declares a `Player` argument, to filter the event to this
##   effect's own player — an effect on player 1 never reacts to player 2's
##   dodge, hit, pickup or room entry;
## - where the signal carries a hit payload, to apply the proc chain rules — an
##   event whose hit carries this effect's own id (rule 2, no self-retrigger) or
##   has reached `MAX_PROC_DEPTH` (rule 1) is dropped before the handler runs,
##   whatever player it belongs to (`hit_landed` has no `Player` argument at all
##   and is nonetheless wrapped, for exactly this reason).
##
## A signal with neither is connected untouched, so the handler is the named
## method itself: nothing is wrapped that has nothing to look at.
##
## Tagging a hit with this effect's own id is the *producer's* job, not this
## class's: `deal_damage()` stamps `proc` and increments the depth, while the
## tag list is the caller's to build, because a hit is also a weapon's, a
## status's and a hazard's. An effect that wants rule 2 to protect it appends
## `source_id()` to the `tags` of every hit it deals.
func listen(sig: Signal, callable: Callable) -> void:
	if not callable.is_valid():
		push_warning("[effect] %s: listen() needs a callable" % source_id())
		return
	var args: Array[Dictionary] = _signal_arguments(sig)
	var index: int = _player_argument_index(args)
	if index == NO_PLAYER_ARGUMENT and not _carries_a_hit(args):
		_connect_tracked(sig, callable)
		return
	if args.size() >= DISPATCH_METHODS.size():
		push_warning("[effect] %s: %s carries more arguments than the wrapper forwards, connected unfiltered" % [source_id(), sig.get_name()])
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
##
## The hit's `tags` are the caller's: this helper adds `proc` and nothing else.
## An effect that would otherwise re-trigger on its own damage appends
## `source_id()` there as well, which is what the wrapper's rule-2 check
## (`_is_own_hit()`) matches on.
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


## Spawns `scene` at `pos` through the world's spawner seam, one link deeper
## than the event this effect is handling (`proc_depth = trigger.proc_depth + 1`,
## SPEC-effect-system "Proc chain limits", the same rule `deal_damage` applies
## to a hit). The instance is stamped with this effect's source id and that
## depth, `setup` — optional — runs on it before it enters the tree, and it is
## parented where the spawner puts it.
##
## This is the "my dodge spawns lightning clones" half of the effect system: an
## effect never instantiates a node itself, and never reaches for
## `World/Entities` by path. The request goes through the effect's `EffectHost`,
## which is the one boundary that knows whether this peer may spawn at all, and
## on to `EffectSpawner`. Refused with a warning — never an error — when there
## is no scene, no host, or no spawner wired (the FX spawner is Dev A's W4-A4).
func spawn(scene: PackedScene, pos: Vector2, setup: Callable = Callable()) -> Node:
	if scene == null:
		push_warning("[effect] %s: spawn() needs a scene" % source_id())
		return null
	var owner_host: EffectHost = _resolve_host()
	if owner_host == null:
		push_warning("[effect] %s: no EffectHost to spawn through, spawn dropped" % source_id())
		return null
	return owner_host.spawn_proc(scene, pos, setup, source_id(), trigger_depth + 1)


## Fires `data` from `from` along `dir` through the world's spawner seam,
## incrementing proc depth exactly as `deal_damage` does: the projectile is a
## result of this trigger, so it carries `trigger_depth + 1` and the effect's
## source id, and whatever hit it lands goes one link deeper again.
##
## The spec travels whole, so the speed, damage, element, pierce and bounce it
## describes reach the projectile spawner unchanged. Refused with a warning —
## never an error — when there is no spec, no host, or no projectile spawner
## wired (combat-core's Projectile is Dev A's W4-A4).
func fire_projectile(data: ProjectileSpec, from: Vector2, dir: Vector2) -> Node:
	if data == null:
		push_warning("[effect] %s: fire_projectile() needs a spec" % source_id())
		return null
	var owner_host: EffectHost = _resolve_host()
	if owner_host == null:
		push_warning("[effect] %s: no EffectHost to fire through, shot dropped" % source_id())
		return null
	return owner_host.fire_proc_projectile(data, from, dir, source_id(), trigger_depth + 1)


## The `EffectHost` this effect spawns through: the one it was attached through,
## or — for an effect parented under a host by hand — its parent. Null when
## neither, which every spawning helper treats as a warned no-op.
func _resolve_host() -> EffectHost:
	if host != null and is_instance_valid(host):
		return host
	var parent: Node = get_parent()
	if parent is EffectHost:
		return parent as EffectHost
	return null


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


## Calls `callable` with the event's own `values`, unless the event belongs to
## another player, carries a hit this effect tagged itself, or has reached the
## proc depth limit.
##
## Four things happen here and this is the only place any of them happens, so
## no effect script re-implements them:
##
## 1. the player filter: an event naming a `Player` other than this effect's own
##    returns without calling anything at all (the negative control is a
##    `player_dodged` for a teammate in `test_effect_base.gd`);
## 2. the self-retrigger check: an event whose hit already carries this effect's
##    own id is dropped here, so a relic whose own damage comes back to it —
##    Ember Boots' trail burning the enemy that was just hit, Volatile Core's
##    death explosion killing another enemy — does not re-trigger itself
##    (SPEC-effect-system, "Proc chain limits", rule 2 — asserted in
##    `test_proc_limits.gd`);
## 3. the proc gate: an event whose hit carries `MAX_PROC_DEPTH` or more is
##    dropped here, so a chain of effects that trigger one another stops at the
##    third link while the hits themselves keep damaging (rule 1 — asserted in
##    `test_proc_limits.gd`);
## 4. `trigger_depth` is set to the event's depth for the duration of the
##    handler, so everything the handler produces is one link deeper, and the
##    previous value is restored on the way out, so a nested proc cannot leak
##    its depth back into the event that caused it.
func _forward(values: Array, argument_index: int, callable: Callable) -> void:
	if argument_index >= 0 and argument_index < values.size():
		if values[argument_index] != player:
			return
	if _is_own_hit(values):
		return
	var depth: int = _event_proc_depth(values)
	if depth >= MAX_PROC_DEPTH:
		return
	var previous: int = trigger_depth
	trigger_depth = depth
	callable.callv(values)
	trigger_depth = previous


## True when a hit the event carries is tagged with this effect's own id — the
## no-self-retrigger rule, quoted from SPEC-effect-system, "Proc chain limits",
## rule 2: "An effect never reacts to a hit whose `tags` already contain its own id
## (no self-retrigger)."
##
## The comparison is against `source_id()` — the content id the effect was
## attached with, never its class name — so two effects built from one script
## (a Mimic Crown copy, two relics sharing an effect script) are suppressed
## independently, each by its own id only. An effect attached with no source has
## no id and therefore nothing to suppress, so the check passes everything
## through rather than matching an empty tag.
##
## Only the *reaction* is suppressed: the hit was already delivered and
## announced by whoever produced it, so it still damages (the same clause rule 1
## is written around).
func _is_own_hit(values: Array) -> bool:
	var id: StringName = source_id()
	if id == &"":
		return false
	for hit: HitData in _event_hits(values):
		if hit.tags.has(id):
			return true
	return false


## The proc depth the event in `values` carries: the greatest `proc_depth` among
## the arguments that are a hit payload, or 0 when none of them is. An event
## with no hit argument is not a link in a chain and is therefore never gated,
## which is what keeps a dodge or a room entry out of the depth rules.
func _event_proc_depth(values: Array) -> int:
	var depth: int = 0
	for hit: HitData in _event_hits(values):
		depth = maxi(depth, hit.proc_depth)
	return depth


## Every hit payload among `values`, in argument order. Both rules that read an
## event's hit — the self-retrigger check and the depth gate — go through here,
## so "what counts as a hit" is one decision rather than two that can drift.
func _event_hits(values: Array) -> Array[HitData]:
	var hits: Array[HitData] = []
	for value: Variant in values:
		if value is HitData:
			hits.append(value as HitData)
	return hits


## True when a signal declared with `args` (as `_signal_arguments()` reads them)
## carries a hit payload, so events on it must go through `_forward()` for the
## proc gate even when there is no `Player` argument to filter on. `hit_landed`
## is exactly that signal: unfiltered by player, gated by depth.
func _carries_a_hit(args: Array[Dictionary]) -> bool:
	for argument: Dictionary in args:
		if int(argument.get("type", TYPE_NIL)) != TYPE_OBJECT:
			continue
		if HIT_CLASSES.has(String(argument.get("class_name", ""))):
			return true
	return false


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
