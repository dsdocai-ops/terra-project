class_name EffectHarness
extends RefCounted
## The trigger-test harness: the one instrument every content module writes its
## effect tests against. Owned by effect-system (W4-B3, goal G19a).
##
## SPEC-effect-system, "Interfaces provided", specifies exactly this shape:
## a harness that "creates a headless player with `EffectHost`, attaches an
## effect, fires any `Events` signal with fake arguments, asserts spawns, stat
## changes, statuses, and damage via a `SpyWorld`". Twenty relics in W4-B6,
## twenty more in week 8, and every mutation, class passive, Ascension and skill
## node after them have a case here rather than a hand-rolled fixture each — so
## "one system, one test harness" is a real claim and not a slogan.
##
## What it builds, all under one autofreed root:
##
## - a **player double** (`make_player()`) — the real `scenes/player/player.tscn`
##   with a `StatBlock` component, a `StatusEffects` double and an `EffectHost`
##   installed, exactly as the game assembles them once Dev A's scene wiring
##   lands. `blocked on Dev A (W2-A1, player.tscn)`: the composition moves into
##   the scene later; this helper swaps in mechanically.
## - a **target double** (`make_target()`) — a node with a `SpyHurtbox` and a
##   `StatusEffects` double, so damage and statuses have somewhere to land.
## - a **`SpyWorld`** (`world`) — the recorder: every spawn, every projectile and
##   every landed hit, attributed to the content id and proc depth that produced
##   it. It is a real `EffectSpawner`, so the production spawn path runs.
##
## The four things a case asserts, and both ways to assert them:
##
## | | pure predicate (returns bool) | GUT-reporting (fails the case) |
## |---|---|---|
## | a spawn | `check_spawned(n)` | `assert_spawned(n)` |
## | a stat change | `check_stat(player, stat, v)` | `assert_stat(...)` |
## | a status | `check_status(target, status, stacks)` | `assert_status(...)` |
## | damage | `check_damage(target, n)` | `assert_damage(target, n)` |
##
## The predicates exist so a case can pin the *negative*: `assert_false(
## check_spawned(1))` is how `test_effect_template.gd` proves the harness's own
## assertion would fail for a broken relic (BRIEF C13 — an assertion whose
## failing path was never observed is an assumption).
##
## COPY-PASTE RECIPE — a new relic case
##
##     extends GutTest
##
##     const RELIC_ID: StringName = &"ember_boots"
##     const SOURCE_PATH: String = "res://data/relics/ember_boots.tres"
##
##     var _harness: EffectHarness
##     var _player: Player
##     var _source: ContentData
##
##     func before_each() -> void:
##         NetworkManager.start_solo()
##         _harness = EffectHarness.new(self)
##         _harness.setup()
##         _player = _harness.make_player()
##         _source = load(SOURCE_PATH) as ContentData
##
##     func after_each() -> void:
##         EffectHarness.reset_globals()
##
##     func test_ember_boots_leaves_a_trail_on_a_dodge() -> void:
##         _harness.attach(_source)
##         assert_true(_harness.fire(Events.player_dodged, [_player, false]))
##         _harness.assert_spawned(1, "the dodge leaves one trail")
##         assert_eq(_harness.spawn_count(RELIC_ID), 1, "attributed to the relic")
##
## A case that needs a target also calls `_harness.make_target()`; one that
## asserts a stat or a status uses `assert_stat` / `assert_status`. For a data
## relic the source is its `.tres`; for a case written before its content file
## exists, `_harness.source(id, name, script, tags)` builds the same
## `ContentData` in memory.
##
## Sync: none — a test helper. The harness is one process; the effects it drives
## are host-only (SPEC-effect-system, "Multiplayer ownership"), and the real
## co-op path is the two-instance smoke.

## The heading a content author looks for in this doc comment. Asserted by
## `test_effect_template.gd`, so the recipe cannot be deleted without a failure.
const RECIPE_HEADING: String = "COPY-PASTE RECIPE"

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const STAT_BLOCK_SCRIPT_PATH: String = "res://scripts/components/stat_block.gd"
const STATUS_STUB_SCRIPT_PATH: String = "res://tests/helpers/status_effects_stub.gd"
const SPY_HURTBOX_SCRIPT_PATH: String = "res://tests/helpers/spy_hurtbox.gd"

## The component node names the effect system looks up. Taken from `Effect`'s own
## constants so the doubles and the lookups cannot drift; `*_NAME` is the bare
## name used when the harness *builds* a target's children.
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
const STATUS_NODE: NodePath = ^"StatusEffects"
const HURTBOX_NODE: NodePath = ^"Hurtbox"
const STAT_BLOCK_NAME: StringName = &"StatBlock"
const STATUS_NAME: StringName = &"StatusEffects"
const HURTBOX_NAME: StringName = &"Hurtbox"

## The stat line every harness player starts from, so a content case can assert
## an absolute value rather than a delta. A relic that *sets* a stat reads badly
## against an arbitrary base, so the numbers are written down here.
const MOVE_SPEED_BASE: float = 100.0
const ATTACK_BASE: float = 100.0
const LUCK_BASE: float = 0.0

## The test this harness reports through, for `assert_*`. Set by `_init()`.
var test: GutTest = null
## The node every player, target and spawn lives under, autofreed by GUT when
## the case ends. One root means one cleanup and no leak between cases.
var root: Node2D = null
## The recorder: spawns, projectiles and landed hits. Also the `spawner` every
## harness player's `EffectHost` is handed.
var world: SpyWorld = null
## The first player `make_player()` built. `attach()` uses it when the caller
## does not name one, so the recipe's `_harness.attach(_source)` line is
## unambiguous.
var primary_player: Player = null

var _players: Array[Player] = []
var _targets: Array[Node2D] = []


func _init(owner_test: GutTest) -> void:
	test = owner_test


## Builds the world: the root the case's nodes live under, and the `SpyWorld`
## recorder with that root as its spawn container. Call once in `before_each()`,
## before `make_player()`.
func setup() -> void:
	if test == null:
		push_warning("[harness] setup() without a test: assertions are unavailable")
		return
	if root != null and is_instance_valid(root):
		return
	root = Node2D.new()
	root.name = &"EffectHarnessRoot"
	test.add_child_autofree(root)
	world = SpyWorld.new()
	world.container = root
	root.add_child(world)


## The real player scene with a `StatBlock`, a `StatusEffects` double, a
## `SpyHurtbox` and an `EffectHost` installed, parented under the harness root.
## The first player made becomes `primary_player`, which `attach()` defaults to.
func make_player() -> Player:
	if root == null:
		push_warning("[harness] make_player() before setup()")
		return null
	var player: Player = EffectHostPlayer.spawn(root)
	player.name = "HarnessPlayer%d" % (_players.size() + 1)
	_install_stat_block(player)
	_install_status_component(player)
	_install_spy_hurtbox(player)
	var host: EffectHost = EffectHostPlayer.install(player)
	host.spawner = world
	_players.append(player)
	if primary_player == null:
		primary_player = player
	return player


## A target for damage and statuses: a node carrying a `SpyHurtbox` (so
## `Effect.deal_damage` has something to deliver to and `SpyWorld` records it)
## and a `StatusEffects` double (so `Effect.apply_status` has something to call).
func make_target(at: Vector2 = Vector2.ZERO) -> Node2D:
	if root == null:
		push_warning("[harness] make_target() before setup()")
		return null
	var target := Node2D.new()
	target.name = "HarnessTarget%d" % (_targets.size() + 1)
	target.position = at
	target.add_child(_make_spy_hurtbox())
	target.add_child(_make_status_component())
	root.add_child(target)
	_targets.append(target)
	return target


## A `ContentData` built in memory, for a case whose content file does not exist
## yet (or that wants to control the tags itself). A data relic's case loads its
## `.tres` instead.
func source(
	id: StringName,
	display_name: String,
	effect_script: GDScript,
	tags: Array[StringName] = [],
) -> ContentData:
	var made := ContentData.new()
	made.id = id
	made.display_name = display_name
	made.effect_script = effect_script
	made.tags = tags
	return made


## A one-node `PackedScene` for a case that needs *something* to spawn, built in
## memory so the harness depends on no art scene (`art-audio`'s relics are
## W4-B12/B13 and not in the week-4 task list).
func marker_scene() -> PackedScene:
	var marker := Node2D.new()
	marker.name = &"HarnessMarker"
	var packed := PackedScene.new()
	packed.pack(marker)
	marker.free()
	return packed


## Instantiates `source.effect_script` on `player` through the real
## `EffectHost.add()`, so the effect that runs is hosted, parented and seeded
## exactly as it is in the game — no second attach path to drift from. Returns
## the live effect, or null (with a warning) when the host refuses it. `player`
## defaults to `primary_player`.
func attach(source: ContentData, stacks: int = 1, player: Player = null) -> Effect:
	if source == null:
		push_warning("[harness] attach() needs a source")
		return null
	var owner_player: Player = _owner_player(player)
	if owner_player == null:
		push_warning("[harness] attach() has no player: call make_player() first")
		return null
	var host: EffectHost = EffectHostPlayer.install(owner_player)
	host.spawner = world
	return host.add(source, stacks)


## Detaches and frees the effect attached for `source`, through the same host
## path `attach()` used. True when there was one. The lifecycle half a content
## case checks: a relic's stat modifier and listeners must go with it.
func detach(source: ContentData, player: Player = null) -> bool:
	if source == null:
		push_warning("[harness] detach() needs a source")
		return false
	var owner_player: Player = _owner_player(player)
	if owner_player == null:
		return false
	var host: EffectHost = _host(owner_player)
	if host == null:
		return false
	return host.remove(source)


## Fires any `Events` signal with `args` as its fake arguments — the harness's
## replacement for a test having to call `Events.foo.emit(...)` five different
## ways. `sig` is the bus's own signal object (`Events.player_dodged`), and its
## name is checked against the bus's script, so a signal that is not on the bus
## or an argument count that does not match is refused with a warning and
## returns false rather than failing at runtime inside a relic: the case's own
## `assert_*` then reports the consequence in its own words.
##
## `args` must match the signal's declared arity; the harness does not invent
## arguments, because the fake ones are the case's choice (a real `Player`, a
## fabricated `HitInfo`, a null enemy).
func fire(sig: Signal, args: Array = []) -> bool:
	var signal_name: StringName = sig.get_name()
	var script: Script = Events.get_script()
	if script == null:
		push_warning("[harness] the Events bus has no script, nothing fired")
		return false
	var declared: Array[Dictionary] = []
	var found: bool = false
	for entry: Dictionary in script.get_script_signal_list():
		if StringName(entry.get("name", &"")) != signal_name:
			continue
		found = true
		var declared_args: Array = entry.get("args", [])
		for argument: Variant in declared_args:
			if argument is Dictionary:
				declared.append(argument)
		break
	if not found:
		push_warning("[harness] Events has no signal %s, nothing fired" % signal_name)
		return false
	if declared.size() != args.size():
		push_warning("[harness] %s takes %d argument(s), %d given, nothing fired" % [
			signal_name, declared.size(), args.size()])
		return false
	var call_args: Array = [signal_name]
	call_args.append_array(args)
	Callable(Events, &"emit_signal").callv(call_args)
	return true


# --- queries --------------------------------------------------------------

## Every player the harness built, in creation order.
func players() -> Array[Player]:
	return _players


## Every target the harness built, in creation order.
func targets() -> Array[Node2D]:
	return _targets


## How many nodes have been spawned, across everything attached — or only those
## attributed to `source_id` when it is given.
func spawn_count(source_id: StringName = &"") -> int:
	if world == null:
		return 0
	return world.spawn_count(source_id)


## The value of `stat` on `player`, read through its `StatBlock`. 0.0 when the
## player carries none (the guarded no-op case).
func stat_of(player: Player, stat: StatBlock.Stat) -> float:
	var block: StatBlock = _stat_block(player)
	if block == null:
		return 0.0
	return block.get_value(stat)


## The stacks of `status` currently on `target`, read through its
## `StatusEffects` double. 0 when none was ever applied.
func status_stacks(target: Node, status: int) -> int:
	var component: StatusEffectsStub = _status_component(target)
	if component == null:
		return 0
	return component.stacks(status)


## How many hits landed on `target`.
func damage_count(target: Node) -> int:
	if world == null:
		return 0
	return world.damage_count(target)


## The summed `base_damage` of the hits that landed on `target` — the damage the
## effect asked for, before any hurtbox computation.
func damage_total(target: Node) -> float:
	if world == null:
		return 0.0
	return world.damage_total(target)


## The id of the single effect attached to `player`, or an empty name when none
## is. Convenience for the common one-relic case.
func attached_id(player: Player = null) -> StringName:
	var owner_player: Player = _owner_player(player)
	if owner_player == null:
		return &""
	var host: EffectHost = _host(owner_player)
	if host == null:
		return &""
	var attached: Array[Effect] = host.effects()
	if attached.is_empty():
		return &""
	return attached[0].source_id()


# --- pure predicates ------------------------------------------------------

## True when `id` is attached to `player` (default `primary_player`).
func check_attached(id: StringName, player: Player = null) -> bool:
	var owner_player: Player = _owner_player(player)
	if owner_player == null:
		return false
	var host: EffectHost = _host(owner_player)
	return host != null and host.has_effect(id)


## True when exactly `expected` node(s) were spawned, all of them when
## `source_id` is empty or only that content's when it is given.
func check_spawned(expected: int, source_id: StringName = &"") -> bool:
	return spawn_count(source_id) == expected


## True when nothing was spawned.
func check_no_spawns() -> bool:
	return spawn_count() == 0


## True when `stat` on `player` equals `expected` to within `EPSILON`.
func check_stat(player: Player, stat: StatBlock.Stat, expected: float) -> bool:
	return is_equal_approx(stat_of(player, stat), expected)


## True when `target` carries exactly `expected` stacks of `status`.
func check_status(target: Node, status: int, expected: int) -> bool:
	return status_stacks(target, status) == expected


## True when exactly `expected` hit(s) landed on `target`.
func check_damage(target: Node, expected: int) -> bool:
	return damage_count(target) == expected


# --- GUT-reporting assertions ---------------------------------------------

## Fails the case unless exactly `expected` node(s) were spawned. `text` is the
## case's own words; a default is written when it gives none.
func assert_spawned(expected: int, text: String = "", source_id: StringName = &"") -> void:
	_report(check_spawned(expected, source_id), text, "expected %d spawned node(s)" % expected)


## Fails the case unless nothing was spawned.
func assert_no_spawns(text: String = "") -> void:
	_report(check_no_spawns(), text, "expected no spawned nodes")


## Fails the case unless `stat` on `player` reads `expected`.
func assert_stat(player: Player, stat: StatBlock.Stat, expected: float, text: String = "") -> void:
	_report(check_stat(player, stat, expected), text, "expected stat %d to read %s" % [int(stat), expected])


## Fails the case unless `target` carries `expected` stacks of `status`.
func assert_status(target: Node, status: int, expected: int, text: String = "") -> void:
	_report(check_status(target, status, expected), text, "expected %d stack(s) of status %d" % [expected, status])


## Fails the case unless exactly `expected` hit(s) landed on `target`.
func assert_damage(target: Node, expected: int, text: String = "") -> void:
	_report(check_damage(target, expected), text, "expected %d landed hit(s)" % expected)


## Fails the case unless `id` is attached to `player`.
func assert_attached(id: StringName, text: String = "", player: Player = null) -> void:
	_report(check_attached(id, player), text, "expected %s to be attached" % id)


# --- cleanup --------------------------------------------------------------

## The copy-paste `after_each()` line: the autoload state every effect test must
## not leak into the next file (LESSONS: GUT global state bleeds across files).
## A harness player registers in `TimeManager`'s PLAYER group when an effect
## opens an `every_seconds()` loop, and a case may open a solo session; both are
## put back here.
static func reset_globals() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.disconnect_all()


# --- internals ------------------------------------------------------------

## The player an operation applies to: the one named, else `primary_player`.
func _owner_player(player: Player) -> Player:
	if player != null:
		return player
	return primary_player


## The `EffectHost` under `player`, or null when it carries none.
func _host(player: Player) -> EffectHost:
	if player == null:
		return null
	var node: Node = player.get_node_or_null(NodePath(EffectHost.NODE_NAME))
	if node is EffectHost:
		return node as EffectHost
	return null


## The `StatBlock` on `player`, or null.
func _stat_block(player: Player) -> StatBlock:
	if player == null:
		return null
	var node: Node = player.get_node_or_null(STAT_BLOCK_NODE)
	if node is StatBlock:
		return node as StatBlock
	return null


## The `StatusEffects` double on `target`, or null.
func _status_component(target: Node) -> StatusEffectsStub:
	if target == null:
		return null
	var node: Node = target.get_node_or_null(STATUS_NODE)
	if node is StatusEffectsStub:
		return node as StatusEffectsStub
	return null


## Puts the real `StatBlock` component and its starting stats on the player
## scene's bare node — the shape `test_effect_helpers.gd` already uses.
func _install_stat_block(player: Player) -> void:
	var node: Node = player.get_node_or_null(STAT_BLOCK_NODE)
	if node == null:
		return
	node.set_script(load(STAT_BLOCK_SCRIPT_PATH) as Script)
	var block: StatBlock = node as StatBlock
	block.base = {
		StatBlock.Stat.MOVE_SPEED: MOVE_SPEED_BASE,
		StatBlock.Stat.ATTACK: ATTACK_BASE,
		StatBlock.Stat.LUCK: LUCK_BASE,
	}


## Hangs a `StatusEffects` double on `player`'s component node, so
## `apply_status` on the player is recorded rather than warned away.
func _install_status_component(player: Player) -> void:
	var node: Node = player.get_node_or_null(STATUS_NODE)
	if node == null:
		return
	node.set_script(load(STATUS_STUB_SCRIPT_PATH) as Script)


## Replaces `player`'s hurtbox with the recording one, wired to this harness's
## `SpyWorld`, so a relic that damages a player is recorded like any target.
func _install_spy_hurtbox(player: Player) -> void:
	var node: Node = player.get_node_or_null(HURTBOX_NODE)
	if node == null:
		return
	node.set_script(load(SPY_HURTBOX_SCRIPT_PATH) as Script)
	var spy: SpyHurtbox = node as SpyHurtbox
	spy.world = world


## A new recording hurtbox wired to this harness's `SpyWorld`.
func _make_spy_hurtbox() -> SpyHurtbox:
	var hurtbox := SpyHurtbox.new()
	hurtbox.name = HURTBOX_NAME
	hurtbox.world = world
	return hurtbox


## A new `StatusEffects` double.
func _make_status_component() -> StatusEffectsStub:
	var status := StatusEffectsStub.new()
	status.name = STATUS_NAME
	return status


## Reports one predicate through GUT, using `text` when the case gave one and
## `fallback` otherwise.
func _report(result: bool, text: String, fallback: String) -> void:
	if test == null:
		push_warning("[harness] no test to report through: %s" % fallback)
		return
	test.assert_true(result, text if text != "" else fallback)
