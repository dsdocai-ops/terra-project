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

## Node name the host is looked up by under the player (`player.EffectHost`).
const NODE_NAME: StringName = &"EffectHost"

## The player this host belongs to, resolved from the parent on `_ready()`.
## Attaching is refused while it is null, because an effect with no player has
## no target for its modifiers and no owner for its filtered events.
var player: Player = null
## The run generator this host hands every effect on attach, so one seed
## replays one run's procs and every effect on a player draws from the same
## stream. Created on first use, seeded from `GameState.run.seed` (or
## `Effect.DEFAULT_RNG_SEED` when no run is live) — never clock entropy.
var rng: RandomNumberGenerator = null

## {source id: Effect}, in attach order. One effect per id: a duplicate pick
## raises `stacks` on the existing effect, it does not add a second one.
var _effects: Dictionary[StringName, Effect] = {}


func _ready() -> void:
	player = _resolve_player()
	if player == null:
		push_warning("[effect-host] %s is not parented to a Player, effects cannot attach" % name)


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


## The player this host drives: its parent when that is a Player, otherwise
## null. Resolved again lazily by `add()` so a host added to the tree without
## `_ready()` having run yet still attaches correctly once it is parented.
func _resolve_player() -> Player:
	var parent: Node = get_parent()
	if parent is Player:
		return parent as Player
	return null


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
