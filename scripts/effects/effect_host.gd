class_name EffectHost
extends Node
## The `EffectHost` node every player carries: holds that player's attached
## effects keyed by source id, and is the single attach/remove/lookup path for
## relics, mutations, synergies, class passives, Ascensions and skill nodes
## (SPEC-effect-system, "Effect base class"; one system, one harness).
## Owned by effect-system.
##
## Sync: host only. The host exists on the host for every player, including
## remote ones, because gameplay runs there; clients hold no `Effect` instances
## and see the results through the spawners and the replicated `RunPlayerState`.
## Nothing here reads input, writes a replicated field or branches on
## `multiplayer`.
##
## Events reach effects through `Effect.listen()` — each effect subscribes to
## the `Events` bus itself, filtered to its own player — so this node is the
## single place their lifetime and (from W4-B3) the proc rules are enforced,
## not a second bus. A removed effect is detached before it is freed, which is
## what stops its listeners and `StatBlock` modifiers while the node is still
## alive to do it.
##
## It is also the one boundary an effect reaches to spawn: `spawn_proc()` and
## `fire_proc_projectile()` forward to the `spawner` seam after checking
## `can_spawn()` and the per-frame spawn cap, so no effect instantiates a node
## itself, no effect names a node path (SPEC-project forbids cross-module
## tree-path reach-through), and there is exactly one place a client's spawn
## request is refused and one place a runaway build's is capped.

## Node name the host is looked up by under the player (`player.EffectHost`).
const NODE_NAME: StringName = &"EffectHost"

## The per-frame spawn cap, from SPEC-effect-system, "Proc chain limits", rule 3:
## "Per-frame cap: at most 64 effect-spawned nodes per player per frame; the rest
## are dropped and counted in a debug stat."
##
## The budget is per *host* (one player) and per *physics frame*, and it is one
## shared budget for both kinds of effect-spawned result: `spawn_proc()` and
## `fire_proc_projectile()` each spend it, so a relic cannot buy a second 64 by
## firing projectiles instead of spawning clones. The spec's "effect-spawned
## nodes" is the unit, not "spawns of one helper".
##
## It is enforced here, on the one boundary every effect reaches, and never in an
## effect script — which is what makes it unbypassable. It is the reason the
## Week 4 checkpoint's pathological proc build allocates a bounded number of
## nodes per frame (SPEC-effect-system, "Testing": "a deliberately pathological
## build ... cannot drop the host below 60 FPS or allocate unbounded nodes").
const MAX_SPAWNS_PER_FRAME: int = 64

## The player this host belongs to, resolved from the parent on `_ready()`.
## Attaching is refused while it is null, because an effect with no player has
## no target for its modifiers and no owner for its filtered events.
var player: Player = null
## The run generator this host hands every effect on attach, so one seed
## replays one run's procs and every effect on a player draws from the same
## stream. Created on first use, seeded from `GameState.run.seed` (or
## `Effect.DEFAULT_RNG_SEED` when no run is live) — never clock entropy.
var rng: RandomNumberGenerator = null
## The seam every effect on this player spawns through. Assigned by whoever
## builds the player (the world, or a test double); left null, effects still
## attach and run, and only their spawns are dropped — which is the state of
## the game while Dev A's FX spawner (W4-A4) is unlanded. Never reached by
## path: SPEC-project forbids cross-module tree-path reach-through, so the
## reference is handed over, not looked up.
var spawner: EffectSpawner = null
## Where to find the seam when nobody assigned `spawner`: resolved once on
## `_ready()`. The world sets either this or `spawner`.
@export var spawner_path: NodePath = ^""

## {source id: Effect}, in attach order. One effect per id: a duplicate pick
## raises `stacks` on the existing effect, it does not add a second one.
var _effects: Dictionary[StringName, Effect] = {}

## How many effect-spawned nodes this player's effects have been allowed in the
## current physics frame — a public counter, the "debug stat" rule 3 says the
## drops are counted in, and what the debug overlay (W4-B11) reads. Computed from
## `_stats_frame` rather than reset in a process callback, so it reads 0 on the
## first read of a new frame whether or not this node has been processed yet: the
## frame the counter belongs to is `Engine.get_physics_frames()`, and nothing can
## observe a stale value from the frame before.
var spawns_this_frame: int:
	get:
		return _spawns_this_frame if _stats_frame == Engine.get_physics_frames() else 0

## How many effect-spawned nodes were refused by the cap in the current physics
## frame. The counterpart of `spawns_this_frame`, with the same frame-keyed
## reset, and the number rule 3 requires to be counted rather than discarded
## silently.
var spawns_dropped: int:
	get:
		return _spawns_dropped if _stats_frame == Engine.get_physics_frames() else 0

## How many *lines* have been written about those drops this frame: at most one,
## because the first drop of a frame announces the cap and the rest only add to
## `spawns_dropped`. Rule 3's "the rest are dropped and counted" is what keeps a
## 1 000-spawn frame from writing 936 warnings.
var drop_reports: int:
	get:
		return _drop_reports if _stats_frame == Engine.get_physics_frames() else 0

## The physics frame `_spawns_this_frame`, `_spawns_dropped` and `_drop_reports`
## belong to. Anything else means they are last frame's and read as 0.
var _stats_frame: int = -1
var _spawns_this_frame: int = 0
var _spawns_dropped: int = 0
var _drop_reports: int = 0


func _ready() -> void:
	player = _resolve_player()
	if player == null:
		push_warning("[effect-host] %s is not parented to a Player, effects cannot attach" % name)
	_resolve_spawner()


## Instantiates `source.effect_script` under this host and attaches it to the
## host's player at `stacks`. Returns the live effect, or null when the request
## is refused with a warning: no source, no id, no `effect_script`, a script
## that is not an `Effect`, the same id already attached, or no player.
##
## The effect is parented before `attach()`, so a subclass may call `add_child`,
## start timers or spawn from `_on_attach()` — and `Effect.detach()` can free
## everything it opened. The host's generator is injected first, so every draw
## an effect makes comes from the host's one stream.
func add(source: ContentData, stacks: int = 1) -> Effect:
	if source == null:
		push_warning("[effect-host] add() needs a source")
		return null
	if source.id == &"":
		push_warning("[effect-host] source %s has no id, effect refused" % source.resource_name)
		return null
	if _effects.has(source.id):
		push_warning("[effect-host] %s is already attached" % source.id)
		return null
	if source.effect_script == null:
		push_warning("[effect-host] %s has no effect_script, effect refused" % source.id)
		return null
	if player == null:
		player = _resolve_player()
	if player == null:
		push_warning("[effect-host] %s has no player, effect refused" % source.id)
		return null
	var made: Variant = source.effect_script.new()
	if not (made is Effect):
		push_warning("[effect-host] %s's effect_script does not extend Effect, refused" % source.id)
		if made is Node and is_instance_valid(made as Node):
			(made as Node).free()
		return null
	var effect: Effect = made as Effect
	effect.name = source.id
	add_child(effect)
	effect.host = self
	effect.rng = _resolve_rng()
	effect.attach(player, source, stacks)
	_effects[source.id] = effect
	return effect


## Detaches the effect for `source` and frees it, returning true when there was
## one to remove. Detach runs first, while the node is alive, so its modifiers,
## timers and bus connections are released; `queue_free()` then takes the node
## out of the tree at the end of the frame (safe from inside a signal handler).
## An unknown source is a warned no-op.
func remove(source: ContentData) -> bool:
	if source == null:
		push_warning("[effect-host] remove() needs a source")
		return false
	var id: StringName = source.id
	var effect: Effect = _effects.get(id) as Effect
	if effect == null:
		push_warning("[effect-host] %s is not attached" % id)
		return false
	_effects.erase(id)
	effect.detach()
	effect.queue_free()
	return true


## The live effect attached for `id`, or null when nothing is attached with
## that id.
func get_effect(id: StringName) -> Effect:
	return _effects.get(id) as Effect


## True while an effect is attached for `id`.
func has_effect(id: StringName) -> bool:
	return _effects.has(id)


## How many effects are attached.
func effect_count() -> int:
	return _effects.size()


## Every attached effect, in attach order. The debug overlay (W4-B11) lists
## this, and W4-B3's proc gate iterates the same set.
func effects() -> Array[Effect]:
	var listed: Array[Effect] = []
	for effect: Effect in _effects.values():
		listed.append(effect)
	return listed


## Tag counts across every attached effect, each weighted by that effect's
## `stacks` — the shape `SynergyTracker` evaluates `SynergyData.required_count`
## against on every pick and removal. An empty Dictionary when nothing is
## attached; a tag no effect carries is absent rather than zero.
func list_tags() -> Dictionary:
	var counts: Dictionary = {}
	for effect: Effect in _effects.values():
		if effect.source == null:
			continue
		for tag: StringName in effect.source.tags:
			counts[tag] = int(counts.get(tag, 0)) + effect.stacks
	return counts


## True while this peer may spawn an effect's result. The client gate lives
## here, on the one boundary an effect reaches, rather than on `EffectSpawner`
## as well: one gate, one place to test, and no way for a second check to hide
## a spawner that was reached around the host.
func can_spawn() -> bool:
	return _can_spawn()


## The host-only seam `can_spawn()` reports through. Split out so a client
## copy can flip it in one process — the same shape `EnemySpawner._can_spawn()`
## and `ProjectileSpawner._can_spawn()` use, and the reason the client half of
## "clients hold no `Effect` instances" is testable without a second instance.
func _can_spawn() -> bool:
	return multiplayer.is_server()


## Spawns one FX-with-gameplay root for `source_id` at `depth` through the
## spawner seam. Returns the node, or null with a warning when this peer may
## not spawn (SPEC-effect-system: "Sync: host only"), no seam is wired — never
## an error, because the FX spawner is Dev A's W4-A4 — or this frame's
## `MAX_SPAWNS_PER_FRAME` budget is already spent.
func spawn_proc(
	scene: PackedScene,
	pos: Vector2,
	setup: Callable,
	source_id: StringName,
	depth: int,
) -> Node:
	if not can_spawn():
		push_warning("[effect-host] %s's spawn refused: only the host spawns effect results" % source_id)
		return null
	if spawner == null or not is_instance_valid(spawner):
		push_warning("[effect-host] no spawner wired, %s's spawn dropped (blocked on Dev A W4-A4)" % source_id)
		return null
	if not _spend_spawn_budget(source_id):
		return null
	return spawner.spawn_node(scene, pos, setup, source_id, depth)


## Fires one projectile for `source_id` at `depth` through the spawner seam.
## Same refusals as `spawn_proc()`, with the projectile spawner named in the
## warning instead — and the same per-frame budget, which both helpers spend.
func fire_proc_projectile(
	spec: ProjectileSpec,
	from: Vector2,
	dir: Vector2,
	source_id: StringName,
	depth: int,
) -> Node:
	if not can_spawn():
		push_warning("[effect-host] %s's shot refused: only the host spawns effect results" % source_id)
		return null
	if spawner == null or not is_instance_valid(spawner):
		push_warning("[effect-host] no spawner wired, %s's shot dropped (blocked on Dev A W4-A4)" % source_id)
		return null
	if not _spend_spawn_budget(source_id):
		return null
	return spawner.spawn_projectile(spec, from, dir, source_id, depth)


## Spends one unit of this host's per-frame budget, and answers whether the
## request may proceed. Called by both spawn paths and by nothing else, so the
## cap cannot be spent twice for one result or forgotten on a new path.
##
## The frame is `Engine.get_physics_frames()`: the counters belong to that frame
## and a call in any other frame starts the budget and the counts fresh. Resetting
## lazily here rather than in `_physics_process()` means a host that is not being
## processed (paused, outside the tree for a tick) still cannot read or spend
## last frame's budget.
##
## The first drop of a frame writes one warning naming the cap; the rest are
## counted in `spawns_dropped` only. The refusal is a warning and not an error:
## capping is a designed outcome (a pathological proc build is expected to reach
## it), not a fault.
func _spend_spawn_budget(source_id: StringName) -> bool:
	var frame: int = Engine.get_physics_frames()
	if frame != _stats_frame:
		_stats_frame = frame
		_spawns_this_frame = 0
		_spawns_dropped = 0
		_drop_reports = 0
	if _spawns_this_frame >= MAX_SPAWNS_PER_FRAME:
		_spawns_dropped += 1
		if _drop_reports == 0:
			_drop_reports = 1
			push_warning(
				"[effect-host] %s: per-frame spawn cap of %d reached, further effect spawns this frame are dropped (SPEC-effect-system, \"Proc chain limits\", rule 3)" % [source_id, MAX_SPAWNS_PER_FRAME]
			)
		return false
	_spawns_this_frame += 1
	return true


## The player this host drives: its parent when that is a Player, otherwise
## null. Resolved again lazily by `add()` so a host added to the tree without
## `_ready()` having run yet still attaches correctly once it is parented.
func _resolve_player() -> Player:
	var parent: Node = get_parent()
	if parent is Player:
		return parent as Player
	return null


## Resolves `spawner_path` into `spawner` once, on `_ready()`. An explicitly
## assigned seam wins, so a test (or a later world) can hand one over without
## the path being set; a path that names something other than an
## `EffectSpawner` is reported and left unset rather than used.
func _resolve_spawner() -> void:
	if spawner != null or spawner_path.is_empty():
		return
	var node: Node = get_node_or_null(spawner_path)
	if node is EffectSpawner:
		spawner = node as EffectSpawner
	elif node != null:
		push_warning("[effect-host] %s is not an EffectSpawner, spawns stay dropped" % node.name)


## The generator handed to effects: this host's own, created and seeded on
## first use. Seeded from the live run so a replay of one seed replays the same
## procs, otherwise from the fixed fallback — never the clock.
func _resolve_rng() -> RandomNumberGenerator:
	if rng != null:
		return rng
	rng = RandomNumberGenerator.new()
	rng.seed = _host_seed()
	return rng


## The seed for this host's generator: the live run's, or `Effect`'s fixed
## fallback when no run is live.
func _host_seed() -> int:
	if GameState.run != null:
		return GameState.run.seed
	return Effect.DEFAULT_RNG_SEED
