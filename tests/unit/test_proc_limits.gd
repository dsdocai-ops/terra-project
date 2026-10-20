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
const EFFECT_HOST_PATH: String = "res://scripts/effects/effect_host.gd"
const SPEC_PATH: String = "res://specs/SPEC-effect-system.md"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const PLACEHOLDER_PROJECTILE: String = "res://scenes/network/placeholder_projectile.tscn"
const STAT_BLOCK_SCRIPT_PATH: String = "res://scripts/components/stat_block.gd"
const PROC_HURTBOX_SCRIPT_PATH: String = "res://tests/helpers/proc_hurtbox_stub.gd"
const PROC_CHAIN_PROBE_SCRIPT_PATH: String = "res://tests/helpers/proc_chain_probe.gd"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
## The name `Effect.deal_damage` looks the damage sink up by, and the node the
## dummy carries it under.
const HURTBOX_NAME: StringName = &"Hurtbox"

## The limit, read from the class under test rather than written here twice.
const MAX_DEPTH: int = 3
## How many reactions each chain offers before it runs out: five, the length of
## the chain the spec's rule is meant to stop.
const CHAIN_LINKS: int = 5
## A link budget no chain in this file can use up, for the cases where the
## assertion is about the rules and not about a probe's own budget — a chain
## that stops then stopped because of the rules and not because it ran dry.
const LONG_LINK_BUDGET: int = 20
## A depth past the limit, so "no handler above the limit" is asserted on both
## the boundary and the far side of it.
const OVER_LIMIT_DEPTH: int = MAX_DEPTH + 1
const BASE_DAMAGE: float = 12.0
const SPAWN_POSITION: Vector2 = Vector2(96.0, 48.0)
const EPSILON: float = 0.0001

## The two content ids the no-self-retrigger cases use (rule 2, goal G17). A
## relic's effect id is its content id — `ember_boots`, `storm_sandals` — and
## rule 2 keys on exactly that and not on the effect's class name, so two
## effects built from one script are suppressed independently.
const SELF_ID: StringName = &"ember_boots"
const OTHER_ID: StringName = &"storm_sandals"
## A display name deliberately different from `SELF_ID`, for the case that pins
## which of the two the rule reads.
const SELF_DISPLAY_NAME: String = "Ember Boots"
## How many reactions the mutually-referencing pair produces with the self-tag
## rule in force: each effect reacts once per depth 0, 1 and 2 and never to the
## hit the other tagged with its id. Derived in the case's doc comment.
const MUTUAL_REACTIONS: int = 6
## The same pair with nothing tagged: every hit is seen by both effects at every
## depth below the limit, so 2 + 4 + 8 = 14 reactions. The delta is what makes
## the self-tag rule the cause of the bounded number above.
const UNTAGGED_MUTUAL_REACTIONS: int = 14

## The per-frame spawn cap, read from the class under test rather than written
## here twice. SPEC-effect-system, "Proc chain limits", rule 3: "Per-frame cap:
## at most 64 effect-spawned nodes per player per frame; the rest are dropped and
## counted in a debug stat."
const SPAWN_CAP: int = 64
## How many spawns the cap case asks one player for in a single frame: more than
## three times the cap, so a cap that is missing, late or off by any margin a
## test could hide behind cannot pass this case by luck.
const OVER_CAP_SPAWNS: int = 200
## What those 200 requests leave behind and what they drop.
const OVER_CAP_DROPPED: int = OVER_CAP_SPAWNS - SPAWN_CAP
## The projectile fired by the shared-budget case. Its numbers do not matter —
## only that it is a real `ProjectileSpec` the host can forward.
const PROJECTILE_SPEED: float = 240.0
const PROJECTILE_DAMAGE: float = 18.0

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
## The second player and its own host/seam/container, built only by the case
## that needs two independent spawn budgets to compare.
var _other_host: EffectHost = null
var _other_spy: EffectSpawnerSpy = null
var _other_container: Node2D = null


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
## effect script. `display_name` defaults to the id, and is set to something
## else only by the case that pins which of the two the self-tag rule reads.
func _source(id: StringName, display_name: String = "") -> ContentData:
	var content := ContentData.new()
	content.id = id
	content.display_name = display_name if display_name != "" else String(id)
	content.effect_script = load(PROC_CHAIN_PROBE_SCRIPT_PATH) as GDScript
	_sources.append(content)
	return content


## A probe attached through the real `EffectHost.add()` path, observing into
## this case's log and producing against the dummy. `link_limit` is left at the
## probe's default (0 — observe only); a chaining case sets it.
func _probe(id: StringName = &"chain_relic", display_name: String = "") -> ProcChainProbe:
	var effect: ProcChainProbe = _host.add(_source(id, display_name)) as ProcChainProbe
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


## Forgets everything the case has recorded so far — the reaction log, the
## announced depths and the hits the hurtbox was asked to receive — so a case
## can drive the same chain twice and compare the two runs.
func _forget() -> void:
	_log.clear()
	_announced.clear()
	_hurtbox.received.clear()


## Asks `host` for `count` spawns in the current frame, the way an effect's
## `spawn()` does — through the host's own public spawn path, so the cap is
## exercised where a relic would meet it. Returns how many requests came back
## with a node.
func _spawn_n(host: EffectHost, count: int) -> int:
	var scene: PackedScene = _plain_scene()
	var made: int = 0
	for i: int in count:
		if host.spawn_proc(scene, SPAWN_POSITION, Callable(), SELF_ID, 1) != null:
			made += 1
	return made


## A second player with its own `EffectHost`, its own seam and its own container,
## so "each player has their own 64 budget" is asserted against two real hosts
## rather than against one host read twice.
func _install_second_player() -> EffectHost:
	_other_container = Node2D.new()
	add_child_autofree(_other_container)
	var player: Player = _make_player()
	_other_host = EffectHostPlayer.install(player)
	_other_spy = EffectSpawnerSpy.new()
	_other_spy.container = _other_container
	add_child_autofree(_other_spy)
	_other_host.spawner = _other_spy
	return _other_host


## A real `ProjectileSpec`, so the shared-budget case fires the same kind of
## request a projectile relic would. The seam under it has no projectile spawner
## wired (combat-core's is Dev A's W4-A4), so what the case asserts is whether
## the *host* let the request through to the seam — which is what the cap
## governs — and not what the seam did with it.
func _projectile_spec() -> ProjectileSpec:
	return ProjectileSpec.new(
		load(PLACEHOLDER_PROJECTILE) as PackedScene,
		PROJECTILE_SPEED,
		PROJECTILE_DAMAGE,
		HitData.Element.FIRE,
		1,
		0,
	)


## Fires one proc projectile through the real host path.
func _fire(host: EffectHost) -> Node:
	return host.fire_proc_projectile(_projectile_spec(), Vector2.ZERO, Vector2.RIGHT, SELF_ID, 1)


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


## Five *different* effects, each handing the next a tagged hit until the depth
## limit is reached. The stop is attributed to a named effect (`link_3`) rather
## than to a total, which is what a chain that stops for the wrong reason cannot
## fake.
##
## The tag that routes the chain is deliberately **not** any effect's own id —
## `hop_0`…`hop_4` against ids `link_0`…`link_4` — because rule 2 (G17) drops an
## event whose hit carries the reacting effect's own id. Routing by id would
## make this chain impossible by construction and the two rules would be
## conflated; the id-tagged case has its own case below.
func test_a_chain_of_five_effects_stops_at_the_depth_three_link() -> void:
	var probes: Array[ProcChainProbe] = []
	for i: int in CHAIN_LINKS:
		var link: ProcChainProbe = _probe(StringName("link_%d" % i))
		link.react_tag = StringName("hop_%d" % i)
		link.emit_tag = StringName("hop_%d" % (i + 1))
		link.link_limit = 1
		probes.append(link)
	_deliver(_hit(0, [&"hop_0"] as Array[StringName]))
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


# --- no self-retrigger (rule 2) --------------------------------------------

## The rule itself, read off the class under test and the spec, so the sentence
## cannot drift away from the code that implements it.
func test_the_self_retrigger_rule_is_the_specs_and_is_documented() -> void:
	var spec: String = FileAccess.get_file_as_string(SPEC_PATH)
	assert_true(
		spec.contains("An effect never reacts to a hit whose `tags` already contain its own id"),
		"the spec states rule 2"
	)
	var source: String = FileAccess.get_file_as_string(EFFECT_PATH)
	assert_true(
		source.contains("_is_own_hit"),
		"Effect carries the check in the dispatch wrapper"
	)
	assert_true(
		source.contains("An effect never reacts to a hit whose `tags` already contain its own id"),
		"and the check quotes the rule it implements"
	)


## rule 2: "An effect never reacts to a hit whose `tags` already contain its own
## id (no self-retrigger)." A hit so tagged must not reach the handler at all —
## `handler_calls` is counted before the probe's own filters, so this cannot be
## the probe's `react_tag` doing the work — while the hit itself is delivered
## and announced exactly as before: the rule suppresses reactions, not damage.
func test_an_effect_never_reacts_to_a_hit_tagged_with_its_own_id() -> void:
	var probe: ProcChainProbe = _probe(SELF_ID)
	_deliver(_hit(0, [SELF_ID] as Array[StringName]))
	assert_eq(probe.handler_calls, 0, "a hit tagged with the effect's own id never reaches a handler")
	assert_eq(_log.count(), 0, "and nothing is recorded")
	assert_eq(_dealt_depths(), [0] as Array[int], "the hit still damages")
	assert_eq(_announced, [0] as Array[int], "and is still emitted on Events.hit_landed")
	assert_eq(
		_hurtbox.received[0].tags,
		[SELF_ID] as Array[StringName],
		"the gate reads the tags and leaves them alone"
	)


## The negative control: the same probe, the same hit, no self-tag — it fires.
## Without this case a gate that was accidentally always-on would pass the rule
## case above.
func test_the_same_hit_without_the_self_tag_still_reaches_the_handler() -> void:
	var probe: ProcChainProbe = _probe(SELF_ID)
	_deliver(_hit(0))
	assert_eq(probe.handler_calls, 1, "an untagged hit reaches the handler")
	assert_eq(_log.sources_for(&"hit_landed"), [SELF_ID] as Array[StringName], "and is recorded")
	_log.clear()
	_deliver(_hit(0, [OTHER_ID] as Array[StringName]))
	assert_eq(
		_log.sources_for(&"hit_landed"),
		[SELF_ID] as Array[StringName],
		"another content's id on the hit is not this effect's own id"
	)


## The rule is per-id, not a blanket suppression: two effects on one player,
## one hit tagged with one of their ids, and the other effect still reacts.
## Both probes are the same class, so the discriminator can only be the source
## id. The third block is the other half of the same property — a hit with no
## id on it reaches **both** effects, so nothing about two effects on one host
## makes either of them inert.
func test_two_effects_with_different_ids_are_filtered_independently() -> void:
	var self_probe: ProcChainProbe = _probe(SELF_ID)
	var other_probe: ProcChainProbe = _probe(OTHER_ID)
	_deliver(_hit(0, [SELF_ID] as Array[StringName]))
	assert_eq(
		_log.sources_for(&"hit_landed"),
		[OTHER_ID] as Array[StringName],
		"only the effect whose own id is not on the hit reacts"
	)
	assert_eq(self_probe.handler_calls, 0, "the tagged effect's handler did not run")
	assert_eq(other_probe.handler_calls, 1, "the untagged one's did")
	_log.clear()
	_deliver(_hit(0, [OTHER_ID] as Array[StringName]))
	assert_eq(
		_log.sources_for(&"hit_landed"),
		[SELF_ID] as Array[StringName],
		"and the suppression follows the id, not the attachment order"
	)
	_log.clear()
	_deliver(_hit(0))
	assert_eq(_log.sources_for(&"hit_landed").size(), 2, "a hit carrying no id reaches both effects")
	assert_true(_log.reacted(SELF_ID), "the first reacted")
	assert_true(_log.reacted(OTHER_ID), "and so did the second: the rule suppresses by id, not wholesale")


## The rule keys on the content id, never on the class name (both probes are
## `ProcChainProbe`) and never on the display name (which is not a tag any code
## puts on a hit).
func test_the_rule_keys_on_the_source_id_and_not_the_display_name() -> void:
	var probe: ProcChainProbe = _probe(SELF_ID, SELF_DISPLAY_NAME)
	_deliver(_hit(0, [StringName(SELF_DISPLAY_NAME)] as Array[StringName]))
	assert_eq(
		probe.handler_calls,
		1,
		"a hit tagged with the display name is not a hit tagged with the effect's id"
	)
	_log.clear()
	_deliver(_hit(0, [SELF_ID] as Array[StringName]))
	assert_eq(probe.handler_calls, 1, "only the id itself suppresses")


## A hit the rule suppresses is still gated by depth, and the rule holds on
## every hit-carrying signal rather than on `hit_landed` alone — a relic that
## listens to `enemy_killed` must not re-trigger on its own kill either.
func test_the_self_tag_is_honoured_on_every_hit_carrying_signal() -> void:
	var probe: ProcChainProbe = _probe(SELF_ID)
	var enemy := EnemyBaseStub.new()
	add_child_autofree(enemy)
	for signal_name: StringName in ProcChainProbe.HIT_SIGNAL_NAMES:
		probe.handler_calls = 0
		_emit_hit_signal(signal_name, enemy, _hit(0, [SELF_ID] as Array[StringName]))
		assert_eq(probe.handler_calls, 0, "%s does not reach an effect that tagged the hit with its own id" % signal_name)
		probe.handler_calls = 0
		_emit_hit_signal(signal_name, enemy, _hit(0))
		assert_eq(probe.handler_calls, 1, "%s still reaches it when the tag is absent" % signal_name)


## The mutual-reference chain the rule is really for: A tags its hits with B's
## id and B tags its hits with A's id, so neither can re-trigger the other, and
## the chain has to terminate. Both react at depth 0 (the initial hit is
## untagged), and then:
##
## - A's hit (tagged `link_b`) is dropped for B and reaches A at depths 1 and 2,
##   where the depth limit stops it — three reactions, depths 0, 1 and 2;
## - B's hit is symmetric — three reactions, depths 0, 1 and 2.
##
## Six reactions, and nothing is left to run: the count is a consequence of the
## two rules together, so it is asserted against a derivation rather than
## observed and copied.
func test_a_pair_that_tags_its_hits_with_the_others_id_terminates() -> void:
	var first: ProcChainProbe = _probe(&"link_a")
	first.emit_tag = &"link_b"
	first.link_limit = LONG_LINK_BUDGET
	var second: ProcChainProbe = _probe(&"link_b")
	second.emit_tag = &"link_a"
	second.link_limit = LONG_LINK_BUDGET
	_deliver(_hit(0))
	assert_eq(_log.count(), MUTUAL_REACTIONS, "the chain terminates, bounded by the two rules")
	assert_eq(
		_log.depths_for_source(&"link_a", &"hit_landed"),
		[0, 1, 2] as Array[int],
		"A reacts to the untagged hit and to the one tagged with B's id, and stops at the depth limit"
	)
	assert_eq(
		_log.depths_for_source(&"link_b", &"hit_landed"),
		[0, 1, 2] as Array[int],
		"and B does the same, neither ever reacting to the hit tagged with its own id"
	)
	assert_eq(
		_dealt_depths().size(),
		MUTUAL_REACTIONS + 1,
		"every produced hit lands, the two depth-3 ones included"
	)
	assert_eq(_dealt_depths().count(MAX_DEPTH), 2, "one from each effect, past the gate that stops reactions")
	_forget()
	_deliver(_hit(0))
	assert_eq(_log.count(), MUTUAL_REACTIONS, "driving it again gives the same count, not merely a finite one")
	assert_eq(_log.depths_for_source(&"link_a", &"hit_landed"), [0, 1, 2] as Array[int], "with A's links unchanged")
	assert_eq(_log.depths_for_source(&"link_b", &"hit_landed"), [0, 1, 2] as Array[int], "and B's too")


## The control for the case above: the same two effects with nothing tagged feed
## each other freely, so every hit below the depth limit is seen by both and the
## chain is bounded by the depth rule alone. 2 + 4 + 8 = 14 reactions — the
## self-tag rule is what took that number to six.
func test_the_same_pair_tags_freely_when_nothing_carries_an_id() -> void:
	var first: ProcChainProbe = _probe(&"link_a")
	first.link_limit = LONG_LINK_BUDGET
	var second: ProcChainProbe = _probe(&"link_b")
	second.link_limit = LONG_LINK_BUDGET
	_deliver(_hit(0))
	assert_eq(
		_log.count(),
		UNTAGGED_MUTUAL_REACTIONS,
		"without a self-tag both effects react to every hit at depths 0, 1 and 2"
	)
	assert_eq(_log.depths_for_source(&"link_a", &"hit_landed").size(), 7, "A sees 1 + 2 + 4 hits")
	assert_eq(_log.depths_for_source(&"link_b", &"hit_landed").size(), 7, "and so does B")
	assert_eq(_dealt_depths().size(), 15, "and every hit at depths 0, 1, 2 and 3 is dealt")


# --- the per-frame spawn cap (rule 3) ---------------------------------------

## The rule itself, read off the class under test and the spec, so the number
## cannot drift away from the sentence that mandates it.
func test_the_per_frame_cap_is_the_specs_and_is_documented() -> void:
	var source: String = FileAccess.get_file_as_string(EFFECT_HOST_PATH)
	assert_true(source.contains("MAX_SPAWNS_PER_FRAME"), "EffectHost declares the cap")
	assert_true(_const_documented(source, "MAX_SPAWNS_PER_FRAME"), "the cap carries a doc comment")
	assert_eq(EffectHost.MAX_SPAWNS_PER_FRAME, SPAWN_CAP, "the cap is the spec's 64")
	var spec: String = FileAccess.get_file_as_string(SPEC_PATH)
	assert_true(
		spec.contains("at most 64 effect-spawned nodes per player per frame"),
		"the spec states the rule the constant implements"
	)


## The headline case: 200 requests in one frame, 64 nodes, 136 counted drops.
func test_two_hundred_spawns_in_one_frame_leave_sixty_four_nodes() -> void:
	var made: int = _spawn_n(_host, OVER_CAP_SPAWNS)
	assert_eq(made, SPAWN_CAP, "exactly the cap's 64 requests were allowed")
	assert_eq(_container.get_child_count(), SPAWN_CAP, "and exactly 64 exist as children")
	assert_eq(_spy.spawns.size(), SPAWN_CAP, "the seam was asked exactly 64 times")
	assert_eq(_host.spawns_this_frame, SPAWN_CAP, "the readable counter reads 64 allowed")
	assert_eq(_host.spawns_dropped, OVER_CAP_DROPPED, "and 136 counted as dropped")


## The boundary: the 64th request passes and the 65th is the first drop, so the
## cap is neither off by one nor "at most 63".
func test_the_boundary_passes_sixty_four_and_drops_the_sixty_fifth() -> void:
	_spawn_n(_host, SPAWN_CAP)
	assert_eq(_host.spawns_this_frame, SPAWN_CAP, "sixty-four requests are all allowed")
	assert_eq(_host.spawns_dropped, 0, "and nothing is dropped")
	assert_eq(_container.get_child_count(), SPAWN_CAP, "so sixty-four nodes exist")
	var extra: Node = _host.spawn_proc(_plain_scene(), SPAWN_POSITION, Callable(), SELF_ID, 1)
	assert_null(extra, "the sixty-fifth request is refused")
	assert_eq(_host.spawns_this_frame, SPAWN_CAP, "the allowed count does not move")
	assert_eq(_host.spawns_dropped, 1, "and exactly one is counted as dropped")
	assert_eq(_container.get_child_count(), SPAWN_CAP, "no sixty-fifth child appears")
	assert_eq(_spy.spawns.size(), SPAWN_CAP, "the seam was never asked for the dropped request")


## The counters are per frame, not per lifetime: the next physics frame starts
## with an empty budget and an empty count, so a build that caps out one frame is
## not silently disabled for the rest of the run.
func test_the_counter_resets_on_the_next_physics_frame() -> void:
	_spawn_n(_host, OVER_CAP_SPAWNS)
	assert_eq(_host.spawns_dropped, OVER_CAP_DROPPED, "this frame's excess is counted")
	await wait_physics_frames(1)
	assert_eq(_host.spawns_this_frame, 0, "the allowed count resets with the frame")
	assert_eq(_host.spawns_dropped, 0, "and so does the dropped count")
	assert_eq(_host.drop_reports, 0, "and the announcement flag with them")
	assert_eq(_spawn_n(_host, 5), 5, "the next frame has its own budget")
	assert_eq(_host.spawns_this_frame, 5, "five of it spent")
	assert_eq(_host.spawns_dropped, 0, "and nothing dropped")


## The budget is per player: one player capping out must not silence a
## teammate's relics.
func test_a_second_player_has_its_own_budget() -> void:
	_spawn_n(_host, OVER_CAP_SPAWNS)
	var other: EffectHost = _install_second_player()
	assert_eq(_spawn_n(other, OVER_CAP_SPAWNS), SPAWN_CAP, "the second player's own 64 budget is intact")
	assert_eq(_other_container.get_child_count(), SPAWN_CAP, "with its own 64 nodes")
	assert_eq(other.spawns_dropped, OVER_CAP_DROPPED, "and its own 136 counted drops")
	assert_eq(other.spawns_this_frame, SPAWN_CAP, "its own allowed count")
	assert_eq(_host.spawns_dropped, OVER_CAP_DROPPED, "while the first player's count is unchanged")
	assert_eq(_container.get_child_count(), SPAWN_CAP, "and the first player's nodes are untouched")
	assert_eq(_other_spy.spawns.size(), SPAWN_CAP, "each seam saw only its own player's spawns")


## 136 drops produce one line, not 136: the excess is counted in a stat, and the
## log stays readable. The announcement is per frame, so a build that caps out
## every frame still says so every frame.
func test_the_drop_is_announced_once_per_frame() -> void:
	_spawn_n(_host, OVER_CAP_SPAWNS)
	assert_eq(_host.spawns_dropped, OVER_CAP_DROPPED, "136 spawns were dropped in this frame")
	assert_eq(_host.drop_reports, 1, "and announced once, not 136 times")
	await wait_physics_frames(1)
	_spawn_n(_host, OVER_CAP_SPAWNS)
	assert_eq(_host.spawns_dropped, OVER_CAP_DROPPED, "the next frame drops the same excess")
	assert_eq(_host.drop_reports, 1, "and announces it once again, rather than not at all")


## Rule 3 caps "effect-spawned nodes", not "spawns of one kind": a relic that
## fires projectiles spends the same per-player budget a relic that spawns
## clones does. Without this, half the cap would be bypassable by choosing the
## other helper.
func test_projectiles_spend_the_same_budget_as_spawns() -> void:
	_spawn_n(_host, SPAWN_CAP - 4)
	assert_eq(_host.spawns_this_frame, SPAWN_CAP - 4, "sixty spawns spent")
	for i: int in 4:
		_fire(_host)
	assert_eq(_host.spawns_this_frame, SPAWN_CAP, "four projectiles spend the rest of the budget")
	assert_eq(_spy.projectiles.size(), 4, "and all four reached the seam")
	assert_null(_fire(_host), "the next request — of either kind — is refused")
	assert_eq(_spy.projectiles.size(), 4, "and never reaches the seam")
	assert_eq(_host.spawns_dropped, 1, "the refused request is counted as dropped")
	assert_eq(_container.get_child_count(), SPAWN_CAP - 4, "and no node appeared for it")


## No effect script can bypass the cap: `Effect.spawn()` reaches the world
## through the host, so a relic that spawns in a loop is capped exactly like a
## direct caller is. This is the property rule 3's "enforced in the helpers, not
## in each effect" clause is written for.
func test_an_effect_cannot_bypass_the_cap() -> void:
	var probe: ProcChainProbe = _probe(SELF_ID)
	var scene: PackedScene = _plain_scene()
	var made: int = 0
	for i: int in OVER_CAP_SPAWNS:
		if probe.spawn(scene, SPAWN_POSITION) != null:
			made += 1
	assert_eq(made, SPAWN_CAP, "an effect's own spawn() is capped at 64")
	assert_eq(_container.get_child_count(), SPAWN_CAP, "with 64 nodes to show for it")
	assert_eq(_host.spawns_dropped, OVER_CAP_DROPPED, "and the excess counted")
	assert_eq(probe.source_id(), SELF_ID, "the spawns name the effect that made them")


## A scene built in memory, so the spawn case is independent of any `.tscn`.
func _plain_scene() -> PackedScene:
	var root := Node2D.new()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed
