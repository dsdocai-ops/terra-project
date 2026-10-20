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

## `StatBlock` modifier handles to remove on detach.
var _handles: Array[int] = []
## Timers parented to this effect, freed on detach.
var _timers: Array[Timer] = []
## {signal: Signal, callable: Callable} pairs, disconnected on detach. Kept as
## an explicit list because a connection cannot be found again by name alone
## once a wrapper is involved, and a lambda can never be disconnected.
var _connections: Array[Dictionary] = []
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
	_disconnect_all()
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
func listen(sig: Signal, callable: Callable) -> void:
	if not callable.is_valid():
		push_warning("[effect] %s: listen() needs a callable" % source_id())
		return
	if sig.is_connected(callable):
		return
	sig.connect(callable)
	_connections.append({"signal": sig, "callable": callable})


## Adds a stat modifier carrying this effect's id as its source, and records
## the returned handle so `detach()` removes exactly this effect's change.
## Never writes a base stat.
func modify(stat: StatBlock.Stat, flat: float = 0.0, percent: float = 0.0) -> void:
	if stat_block == null:
		push_warning("[effect] %s: no StatBlock on the player, modifier dropped" % source_id())
		return
	_handles.append(stat_block.add_modifier(stat, flat, percent, source_id()))


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
