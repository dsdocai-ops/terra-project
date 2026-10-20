extends GutTest
## Tests for the proc-chain depth limit — effect-system, W4-B3 (goal G16).
##
## SPEC-effect-system, "Proc chain limits", rule 1: "A proc at depth 3 does not
## trigger further effects (its hits still damage, but `hit_landed` from it is
## emitted with `hit.proc_depth = 3` and `Effect.listen` wrappers skip events
## with `proc_depth >= 3`)." That sentence has four parts and this file pins
## each one separately: the depth travels on `HitData`, the wrapper skips an
## event whose depth has reached the limit, the skipped event's hit is still
## announced and still dealt, and the chain therefore stops instead of
## recursing.
##
## The chain is built from `ProcChainProbe`, a test double that listens to every
## hit-carrying signal through the real `Effect.listen()` path and produces one
## more result per reaction. Two shapes are covered, because a chain that stops
## can stop for the wrong reason:
##
## - one self-triggering effect with five links available (it reacts to its own
##   hits), which must use three;
## - a chain of five *different* effects, each handing the next a differently
##   tagged hit, which must stop at the fifth link's predecessor — so the stop is
##   attributed to a named effect rather than to a total.
##
## The probe's own link budget is deliberately longer than the spec's limit, so
## a chain that stops has stopped because of the gate and not because it ran out
## of links. The depth gate's negative control is in
## `test_the_gate_reads_the_event_and_not_the_effects_own_state`.
##
## `Events.hit_landed` is announced by the *hurtbox* (SPEC-combat-core: "...
## emit `Events.hit_landed`"), not by `Effect.deal_damage`, so the target
## carries `ProcHurtboxStub` — a double of Dev A's `Hurtbox` (combat-core,
## W2-A2) that records and then announces, which is what makes a chain advance
## through the real path. `blocked on Dev A (W2-A2)`.
##
## Sync: none under test. The depth rules are host-only logic (an effect never
## runs on a client), so there is no client half to drive in one process.

const EFFECT_PATH: String = "res://scripts/effects/effect.gd"
const SPEC_PATH: String = "res://specs/SPEC-effect-system.md"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const STAT_BLOCK_SCRIPT_PATH: String = "res://scripts/components/stat_block.gd"
const PROC_HURTBOX_SCRIPT_PATH: String = "res://tests/helpers/proc_hurtbox_stub.gd"
const PROC_CHAIN_PROBE_SCRIPT_PATH: String = "res://tests/helpers/proc_chain_probe.gd"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
## The name `Effect.deal_damage` looks the damage sink up by, and the node the
## dummy carries it under.
const HURTBOX_NAME: StringName = &"Hurtbox"

## The limit, read from the class under test rather than written here twice.
const MAX_DEPTH: int = 3
## How many links each chain shape offers before it runs out: five, the length
## of the chain the spec's rule is meant to stop.
const CHAIN_LINKS: int = 5
## A depth past the limit, so "no handler above the limit" is asserted on both
## the boundary and the far side of it.
const OVER_LIMIT_DEPTH: int = MAX_DEPTH + 1
const BASE_DAMAGE: float = 12.0
const SPAWN_POSITION: Vector2 = Vector2(96.0, 48.0)
const EPSILON: float = 0.0001

var _player: Player
var _host: EffectHost
var _dummy: Node2D
var _hurtbox: ProcHurtboxStub
var _log: ProcChainLog
var _container: Node2D
var _spy: EffectSpawnerSpy
## Every `Events.hit_landed` the bus announced, by the hit's own depth. Recorded
## by a plain listener rather than by an effect, so "the depth-3 hit is still
## emitted" is asserted on the emission itself.
var _announced: Array[int] = []
var _sources: Array[ContentData] = []


func before_each() -> void:
	# An offline peer reports `is_server() == true`, which is the state the
	# spawn case needs; it must not outlive the file (LESSONS).
	NetworkManager.start_solo()
	_log = ProcChainLog.new()
	_announced.clear()
	_player = _make_player()
	_host = EffectHostPlayer.install(_player)
	_container = Node2D.new()
	add_child_autofree(_container)
	_spy = EffectSpawnerSpy.new()
	_spy.container = _container
	add_child_autofree(_spy)
	_host.spawner = _spy
	_dummy = _make_dummy()
	Events.hit_landed.connect(_on_hit_landed)


func after_each() -> void:
	Events.hit_landed.disconnect(_on_hit_landed)
	for effect: Effect in _host.effects():
		if effect.source != null:
			_host.remove(effect.source)
	_sources.clear()
	# Autoload state leaks across test files (LESSONS).
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.disconnect_all()


## The real player scene with the `StatBlock` component hung on its bare node,
## the shape the other effect tests use.
func _make_player() -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	var component: Node = player.get_node(STAT_BLOCK_NODE)
	component.set_script(load(STAT_BLOCK_SCRIPT_PATH) as Script)
	add_child_autofree(player)
	return player


## The hit target: a plain node named like an enemy, carrying the recording,
## announcing hurtbox double the chain advances through.
func _make_dummy() -> Node2D:
	var dummy := Node2D.new()
	dummy.name = "TrainingDummy"
	add_child_autofree(dummy)
	var area := Area2D.new()
	area.name = HURTBOX_NAME
	area.set_script(load(PROC_HURTBOX_SCRIPT_PATH) as Script)
	dummy.add_child(area)
	_hurtbox = area as ProcHurtboxStub
	return dummy


## A content source carrying the probe script, the way a relic carries its
## effect script.
func _source(id: StringName) -> ContentData:
	var content := ContentData.new()
	content.id = id
	content.display_name = String(id)
	content.effect_script = load(PROC_CHAIN_PROBE_SCRIPT_PATH) as GDScript
	_sources.append(content)
	return content


## A probe attached through the real `EffectHost.add()` path, observing into
## this case's log and producing against the dummy. `link_limit` is left at the
## probe's default (0 — observe only); a chaining case sets it.
func _probe(id: StringName = &"chain_relic") -> ProcChainProbe:
	var effect: ProcChainProbe = _host.add(_source(id)) as ProcChainProbe
	assert_not_null(effect, "the probe attached")
	if effect == null:
		return null
	effect.log = _log
	effect.target = _dummy
	return effect


## A hit at `depth`, optionally tagged.
func _hit(depth: int, tags: Array[StringName] = []) -> HitData:
	var hit := HitData.new()
	hit.base_damage = BASE_DAMAGE
	hit.proc_depth = depth
	hit.tags = tags.duplicate()
	return hit


## Delivers `hit` the way a weapon does: to the target's hurtbox, which records
## it and announces it on `Events.hit_landed`. Nothing here stamps the depth, so
## the depth that reaches the handlers is the depth the hit was built with.
func _deliver(hit: HitData) -> void:
	_hurtbox.receive(hit)


## Emits one of the bus's hit-carrying signals with `hit` at its own depth.
func _emit_hit_signal(signal_name: StringName, enemy: Node, hit: HitData) -> void:
	match signal_name:
		&"hit_landed":
			Events.hit_landed.emit(hit)
		&"crit_landed":
			Events.crit_landed.emit(hit)
		&"player_damaged":
			Events.player_damaged.emit(_player, hit)
		&"enemy_killed":
			Events.enemy_killed.emit(enemy, hit)
		&"elite_killed":
			Events.elite_killed.emit(enemy, hit)
		_:
			assert_true(false, "%s is not a hit-carrying signal" % signal_name)


## The depths of the hits the hurtbox was asked to receive, in order — the
## "its hits still damage" half of the rule.
func _dealt_depths() -> Array[int]:
	var depths: Array[int] = []
	for hit: HitData in _hurtbox.received:
		depths.append(hit.proc_depth)
	return depths


## The bus listener: a plain named method, never an effect, so it observes the
## emission whether or not any effect may react to it.
func _on_hit_landed(hit: HitData) -> void:
	_announced.append(hit.proc_depth)


## The line declaring `const <name>` in `source`, and whether the line above it
## is a doc comment.
func _const_documented(source: String, const_name: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for i: int in range(1, lines.size()):
		if lines[i].begins_with("const %s" % const_name):
			return lines[i - 1].strip_edges().begins_with("##")
	return false


# --- the depth travels on the payload --------------------------------------

func test_a_fresh_hit_is_depth_zero() -> void:
	var hit := HitData.new()
	assert_eq(hit.proc_depth, 0, "proc_depth defaults to 0: a weapon hit is the chain's root")


func test_the_limit_is_the_specs_three_and_is_documented() -> void:
	var source: String = FileAccess.get_file_as_string(EFFECT_PATH)
	assert_true(source.contains("MAX_PROC_DEPTH"), "Effect declares the limit")
	assert_true(_const_documented(source, "MAX_PROC_DEPTH"), "the limit carries a doc comment")
	assert_eq(Effect.MAX_PROC_DEPTH, MAX_DEPTH, "the limit is the spec's 3")
	var spec: String = FileAccess.get_file_as_string(SPEC_PATH)
	assert_true(
		spec.contains("Effect.listen` wrappers skip events with `proc_depth >= 3`"),
		"the spec states the rule the constant implements"
	)


func test_deal_damage_spawn_and_fire_projectile_stamp_trigger_depth_plus_one() -> void:
	var probe: ProcChainProbe = _probe()
	probe.link_limit = 1
	var scene: PackedScene = _plain_scene()
	probe.spawn_scene = scene
	probe.spawn_at = SPAWN_POSITION
	_deliver(_hit(2))
	assert_eq(_dealt_depths(), [2] as Array[int], "only the trigger hit was dealt; this probe spawns instead")
	assert_eq(_spy.spawns.size(), 1, "the spawn went through the host to the seam")
	assert_eq(_spy.last_depth(), MAX_DEPTH, "proc_depth = trigger.proc_depth + 1, so depth 2 spawns at 3")
	assert_eq(_spy.last_source_id(), probe.source_id(), "and the spawn names the effect that made it")
	assert_eq(probe.trigger_depth, 0, "the trigger depth is cleared once the handler returns")


# --- the chain stops -------------------------------------------------------

func test_a_five_link_self_triggering_chain_stops_at_depth_three() -> void:
	var probe: ProcChainProbe = _probe()
	probe.link_limit = CHAIN_LINKS
	_deliver(_hit(0))
	assert_eq(
		_log.depths_for(&"hit_landed"),
		[0, 1, 2] as Array[int],
		"an effect reacts at depths 0, 1 and 2 and never at 3"
	)
	assert_eq(probe.links, MAX_DEPTH, "three of the five links were used, so the gate stopped it rather than the budget")
	assert_eq(_dealt_depths(), [0, 1, 2, 3] as Array[int], "the hits themselves still damage, the depth-3 hit included")
	assert_eq(_announced, [0, 1, 2, 3] as Array[int], "the depth-3 hit is still emitted on Events.hit_landed")
	assert_eq(_hurtbox.received[3].proc_depth, MAX_DEPTH, "and it carries hit.proc_depth == 3")
	assert_eq(probe.trigger_depth, 0, "the chain leaves no trigger depth behind")


func test_a_chain_of_five_effects_stops_at_the_depth_three_link() -> void:
	var probes: Array[ProcChainProbe] = []
	for i: int in CHAIN_LINKS:
		var link: ProcChainProbe = _probe(StringName("link_%d" % i))
		link.react_tag = StringName("link_%d" % i)
		link.emit_tag = StringName("link_%d" % (i + 1))
		link.link_limit = 1
		probes.append(link)
	_deliver(_hit(0, [&"link_0"] as Array[StringName]))
	assert_eq(
		_log.sources_for(&"hit_landed"),
		[&"link_0", &"link_1", &"link_2"] as Array[StringName],
		"each link hands the next a tagged hit until the depth limit is reached"
	)
	assert_eq(_log.depths_for(&"hit_landed"), [0, 1, 2] as Array[int], "at depths 0, 1 and 2")
	assert_false(_log.reacted(&"link_3"), "the fourth link would have run at depth 3 and never does")
	assert_false(_log.reacted(&"link_4"), "nor the fifth")
	assert_eq(probes[3].links, 0, "the fourth link produced nothing")
	assert_eq(_dealt_depths(), [0, 1, 2, 3] as Array[int], "the depth-3 hit is dealt even though nothing reacts to it")


func test_a_depth_three_hit_is_announced_and_dealt_but_triggers_nothing() -> void:
	var probe: ProcChainProbe = _probe()
	_deliver(_hit(MAX_DEPTH))
	assert_eq(_announced, [MAX_DEPTH] as Array[int], "the hit is emitted on Events.hit_landed with its own depth")
	assert_eq(_hurtbox.received.size(), 1, "and still reaches the damage sink")
	assert_eq(_log.count(), 0, "no effect reacts to it")
	assert_eq(probe.links, 0)


func test_each_depth_boundary_is_asserted_separately() -> void:
	var probe: ProcChainProbe = _probe()
	for depth: int in [0, 1, 2]:
		_log.clear()
		_deliver(_hit(depth))
		assert_eq(
			_log.depths_for(&"hit_landed"),
			[depth] as Array[int],
			"a depth-%d hit reaches a handler" % depth
		)
	for depth: int in [MAX_DEPTH, OVER_LIMIT_DEPTH]:
		_log.clear()
		_deliver(_hit(depth))
		assert_eq(
			_log.depths_for(&"hit_landed"),
			[] as Array[int],
			"a depth-%d hit reaches no handler" % depth
		)
	assert_eq(probe.links, 0, "the observe-only probe produced nothing")


## Every signal that carries a `HitData` is gated the same way, so the rule
## cannot hold for `hit_landed` alone while a relic that listens to
## `player_damaged` or `enemy_killed` chains forever.
func test_the_gate_holds_on_every_hit_carrying_signal() -> void:
	var probe: ProcChainProbe = _probe()
	var enemy := EnemyBaseStub.new()
	add_child_autofree(enemy)
	for signal_name: StringName in ProcChainProbe.HIT_SIGNAL_NAMES:
		var under: int = MAX_DEPTH - 1
		_log.clear()
		_emit_hit_signal(signal_name, enemy, _hit(under))
		assert_eq(
			_log.depths_for(signal_name),
			[under] as Array[int],
			"%s at depth %d reaches a handler" % [signal_name, under]
		)
		_log.clear()
		_emit_hit_signal(signal_name, enemy, _hit(MAX_DEPTH))
		assert_eq(
			_log.depths_for(signal_name),
			[] as Array[int],
			"%s at depth %d reaches no handler" % [signal_name, MAX_DEPTH]
		)


func test_the_gate_reads_the_event_and_not_the_effects_own_state() -> void:
	var probe: ProcChainProbe = _probe()
	probe.trigger_depth = MAX_DEPTH
	_deliver(_hit(0))
	assert_eq(
		_log.depths_for(&"hit_landed"),
		[0] as Array[int],
		"a depth-0 event is not gated by a stale depth on the effect"
	)
	assert_eq(
		probe.trigger_depth,
		MAX_DEPTH,
		"the wrapper puts the event's depth in place for the handler and restores what it found"
	)


## The handler sees the event's depth while it runs: that is what makes the
## `+ 1` on everything it produces a step in a chain rather than a constant.
func test_the_handler_runs_with_the_events_depth_as_its_trigger_depth() -> void:
	var probe: ProcChainProbe = _probe()
	_deliver(_hit(1))
	assert_eq(_log.depths_for(&"hit_landed"), [1] as Array[int], "the handler read the event's own depth")
	assert_eq(probe.trigger_depth, 0, "and the depth is cleared once the handler returns")
	assert_almost_eq(_hurtbox.received[0].base_damage, BASE_DAMAGE, EPSILON, "the delivered hit is the one that was sent")


## A scene built in memory, so the spawn case is independent of any `.tscn`.
func _plain_scene() -> PackedScene:
	var root := Node2D.new()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed
