extends GutTest
## Tests for `Effect.spawn()` and `Effect.fire_projectile()` — effect-system,
## W4-B2 (goal G15).
##
## These two helpers are the "my dodge spawns lightning clones that explode"
## half of the effect system: the first asks the world's spawner for an
## FX-with-gameplay root (a clone, a zone, a totem), the second asks it for a
## projectile. Both go through `EffectHost` -> the spawner seam rather than
## reaching for `World/Entities` by path (SPEC-project forbids cross-module
## tree-path reach-through), and both stamp the result with `proc_source_id`
## and `proc_depth` so the VFX library can colour by element and the debug
## overlay can say which relic made what (SPEC-effect-system, "Visual
## language").
##
## Neither the FX spawner nor combat-core's real projectile is in the repo yet
## (Dev A's lane is empty; `scripts/generation/` is empty and `scenes/dungeon/`
## holds nothing but `interactables/`), so the seam is asserted against
## `tests/helpers/effect_spawner_spy.gd` — which runs the real base
## implementation and records what it was asked for — plus a plain container
## and the shipping `PlaceholderProjectile` scene. The seam's absent-spawner
## path is asserted as a *warning*, never an error, so the suite stays
## engine-error free while the real spawners are unlanded.
##
## Proc depth: SPEC-effect-system, "Proc chain limits" — "`deal_damage`,
## `spawn`, and `fire_projectile` from an effect create results with
## `proc_depth = trigger.proc_depth + 1`" — so a spawned node carries *the
## depth the trigger produced*, one link past the event that caused it, exactly
## as `deal_damage` stamps a hit (pinned in `test_effect_helpers.gd`).
##
## Sync: none under test. Both helpers are host-only; the client branch is
## driven through the same `_can_spawn()` seam override the entity-spawner
## tests use, because GUT runs one instance and the offline peer is always the
## server. The real co-op path is the two-instance smoke.

const EFFECT_PATH: String = "res://scripts/effects/effect.gd"
const EFFECT_HOST_PATH: String = "res://scripts/effects/effect_host.gd"
const SPAWNER_PATH: String = "res://scripts/effects/effect_spawner.gd"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const STAT_BLOCK_SCRIPT_PATH: String = "res://scripts/components/stat_block.gd"
const TARGET_SCRIPT_PATH: String = "res://tests/helpers/effect_spawn_target.gd"
const PLACEHOLDER_PROJECTILE: String = "res://scenes/network/placeholder_projectile.tscn"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"

## The two helpers this goal ships, in the spec's own order.
const SPEC_HELPERS: Array[String] = ["spawn", "fire_projectile"]
## The seam `EffectHost` talks to.
const SEAM_METHODS: Array[String] = ["spawn_node", "spawn_projectile"]

const SOURCE_ID: StringName = &"ember_boots"
const TRIGGER_DEPTH: int = 2
const SPAWN_POSITION: Vector2 = Vector2(320.0, 160.0)
const PROJECTILE_FROM: Vector2 = Vector2(64.0, 32.0)
const PROJECTILE_DIR: Vector2 = Vector2(1.0, 0.0)
const SPEC_SPEED: float = 240.0
const SPEC_DAMAGE: float = 18.0
const SPEC_PIERCE: int = 2
const SPEC_BOUNCE: int = 3
const EPSILON: float = 0.0001

var _player: Player
var _host: EffectHost
var _spy: EffectSpawnerSpy
var _container: Node2D
var _source: ContentData
var _setup_probe: SetupProbe


func before_each() -> void:
	NetworkManager.start_solo()
	_container = Node2D.new()
	add_child_autofree(_container)
	_player = _make_player()
	_host = EffectHostPlayer.install(_player)
	_spy = EffectSpawnerSpy.new()
	_spy.container = _container
	add_child_autofree(_spy)
	_host.spawner = _spy
	_source = ContentData.new()
	_source.id = SOURCE_ID
	_source.display_name = "Ember Boots"
	_source.effect_script = load(EFFECT_PATH) as GDScript
	_setup_probe = SetupProbe.new()


func after_each() -> void:
	# Autoload state leaks across test files (LESSONS): the solo session a case
	# may open must not outlive it.
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.disconnect_all()


func _make_player() -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	var component: Node = player.get_node(STAT_BLOCK_NODE)
	component.set_script(load(STAT_BLOCK_SCRIPT_PATH) as Script)
	add_child_autofree(player)
	return player


## The effect under test: attached through the real `EffectHost.add()` path, so
## its host reference is set exactly as it is in the game. Its trigger depth is
## set to `TRIGGER_DEPTH`, standing in for W4-B3's dispatch wrapper having put
## the handled event's depth there.
func _attach(player: Player = null) -> Effect:
	var owner_player: Player = _player if player == null else player
	var host: EffectHost = EffectHostPlayer.install(owner_player)
	host.spawner = _spy
	var effect: Effect = host.add(_source)
	assert_not_null(effect, "the effect attached through the host")
	effect.trigger_depth = TRIGGER_DEPTH
	return effect


## A `.tres`-less scene built in memory, so a case can control exactly which
## properties the spawned root declares.
func _pack(root: Node) -> PackedScene:
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


func _plain_scene() -> PackedScene:
	return _pack(Node2D.new())


func _declaring_scene() -> PackedScene:
	var root := Node2D.new()
	root.set_script(load(TARGET_SCRIPT_PATH) as Script)
	return _pack(root)


func _spec() -> ProjectileSpec:
	return ProjectileSpec.new(
		load(PLACEHOLDER_PROJECTILE) as PackedScene,
		SPEC_SPEED,
		SPEC_DAMAGE,
		HitInfo.Element.FIRE,
		SPEC_PIERCE,
		SPEC_BOUNCE,
	)


func _documented(source: String, method_name: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for i: int in range(1, lines.size()):
		if lines[i].begins_with("func %s(" % method_name):
			return lines[i - 1].strip_edges().begins_with("##")
	return false


# --- declaration ----------------------------------------------------------

func test_the_two_spawn_helpers_are_declared_and_documented() -> void:
	var script: GDScript = load(EFFECT_PATH) as GDScript
	var source: String = FileAccess.get_file_as_string(EFFECT_PATH)
	var names: Array[String] = []
	for method: Dictionary in script.get_script_method_list():
		names.append(String(method["name"]))
	for helper: String in SPEC_HELPERS:
		assert_true(names.has(helper), "Effect declares %s()" % helper)
		assert_true(_documented(source, helper), "%s() carries a doc comment" % helper)


func test_the_seam_declares_the_two_spawn_paths_and_is_documented() -> void:
	var script: GDScript = load(SPAWNER_PATH) as GDScript
	var source: String = FileAccess.get_file_as_string(SPAWNER_PATH)
	var names: Array[String] = []
	for method: Dictionary in script.get_script_method_list():
		names.append(String(method["name"]))
	for path: String in SEAM_METHODS:
		assert_true(names.has(path), "EffectSpawner declares %s()" % path)
		assert_true(_documented(source, path), "%s() carries a doc comment" % path)


func test_the_host_exposes_the_spawner_seam_and_the_client_gate() -> void:
	var host_source: String = FileAccess.get_file_as_string(EFFECT_HOST_PATH)
	assert_true(host_source.contains("var spawner:"), "EffectHost carries the spawner reference")
	assert_true(host_source.contains("func can_spawn("), "EffectHost exposes can_spawn()")
	assert_true(host_source.contains("func _can_spawn("), "and the override seam the client double flips")


# --- spawn ----------------------------------------------------------------

func test_spawn_asks_the_hosts_spawner() -> void:
	var effect: Effect = _attach()
	var node: Node = effect.spawn(_plain_scene(), SPAWN_POSITION)
	assert_eq(_spy.spawns.size(), 1, "the seam was asked exactly once")
	assert_not_null(node, "the seam's node comes back to the effect")
	assert_eq(node.get_parent(), _container, "and it is parented where the spawner puts it")


func test_spawn_stamps_the_source_id_and_places_the_node() -> void:
	var effect: Effect = _attach()
	var node: Node = effect.spawn(_plain_scene(), SPAWN_POSITION)
	assert_eq(_spy.last_source_id(), SOURCE_ID, "the seam is told which content spawned it")
	assert_eq(_spy.last_depth(), TRIGGER_DEPTH + 1, "and the depth the trigger produced")
	assert_eq((node as Node2D).position, SPAWN_POSITION, "the instance lands at the requested position")


## SPEC-effect-system, "Proc chain limits": `spawn` creates a result one link
## past its trigger, exactly as `deal_damage` does. A trigger at depth 0 (a
## weapon hit) therefore spawns at depth 1.
func test_spawn_uses_the_trigger_depth_plus_one_at_the_boundary() -> void:
	var effect: Effect = _attach()
	effect.trigger_depth = 0
	effect.spawn(_plain_scene(), SPAWN_POSITION)
	assert_eq(_spy.last_depth(), 1, "a depth-0 trigger spawns at depth 1")
	effect.trigger_depth = TRIGGER_DEPTH
	effect.spawn(_plain_scene(), SPAWN_POSITION)
	assert_eq(_spy.last_depth(), TRIGGER_DEPTH + 1, "and a depth-%d trigger at %d" % [TRIGGER_DEPTH, TRIGGER_DEPTH + 1])


func test_spawn_stamps_a_scene_that_declares_the_field() -> void:
	var effect: Effect = _attach()
	var node: Node = effect.spawn(_declaring_scene(), SPAWN_POSITION)
	assert_false(node.has_meta(EffectSpawner.PROC_SOURCE_ID), "a declared property is used, not metadata")
	assert_eq(
		EffectSpawner.read_stamp(node, EffectSpawner.PROC_SOURCE_ID), SOURCE_ID,
		"the declared property carries the source id")
	assert_eq(
		int(EffectSpawner.read_stamp(node, EffectSpawner.PROC_DEPTH)), TRIGGER_DEPTH + 1,
		"and the depth")


## The other branch: a root that does not declare the fields still carries them,
## as metadata, so the value is never silently dropped on an art-audio scene.
func test_spawn_stamps_a_scene_that_does_not_declare_the_field() -> void:
	var effect: Effect = _attach()
	var node: Node = effect.spawn(_plain_scene(), SPAWN_POSITION)
	assert_true(node.has_meta(EffectSpawner.PROC_SOURCE_ID), "the plain root takes metadata instead")
	assert_eq(
		EffectSpawner.read_stamp(node, EffectSpawner.PROC_SOURCE_ID), SOURCE_ID,
		"the value arrives as metadata instead")
	assert_eq(
		int(EffectSpawner.read_stamp(node, EffectSpawner.PROC_DEPTH)), TRIGGER_DEPTH + 1,
		"depth too")


func test_spawn_runs_the_setup_callable_before_the_node_enters_the_tree() -> void:
	var effect: Effect = _attach()
	var node: Node = effect.spawn(_plain_scene(), SPAWN_POSITION, Callable(_setup_probe, "run"))
	assert_eq(_setup_probe.calls, 1, "setup ran exactly once")
	assert_eq(_setup_probe.node, node, "on the instance that was returned")
	assert_false(_setup_probe.was_inside_tree, "before it entered the tree")
	assert_null(_setup_probe.parent_at_setup, "and before it was parented")
	assert_true(node.is_inside_tree(), "afterwards it is in the tree")


func test_spawn_with_no_setup_callable_is_fine() -> void:
	var effect: Effect = _attach()
	assert_not_null(effect.spawn(_plain_scene(), SPAWN_POSITION), "the default empty callable is skipped, not called")
	assert_eq(_setup_probe.calls, 0, "and nothing ran")


func test_spawn_refuses_on_a_client_and_never_reaches_the_spawner() -> void:
	var client_host := _make_client_host(_player)
	var effect: Effect = client_host.add(_source)
	assert_not_null(effect, "the client copy still holds the effect")
	assert_null(effect.spawn(_plain_scene(), SPAWN_POSITION), "a client spawn is refused")
	assert_eq(_spy.spawns.size(), 0, "and the spawner was never asked")


func test_spawn_without_a_spawner_is_a_warned_no_op() -> void:
	var effect: Effect = _attach()
	_host.spawner = null
	assert_null(effect.spawn(_plain_scene(), SPAWN_POSITION), "nothing is spawned")
	assert_eq(_spy.spawns.size(), 0, "the absent seam is not reached")


func test_spawn_without_a_host_is_a_warned_no_op() -> void:
	var effect := Effect.new()
	_player.add_child(effect)
	effect.attach(_player, _source, 1)
	assert_null(effect.spawn(_plain_scene(), SPAWN_POSITION), "an effect with no host spawns nothing")
	assert_eq(_spy.spawns.size(), 0, "and never reaches a spawner")
	effect.detach()


func test_spawn_without_a_scene_is_refused() -> void:
	var effect: Effect = _attach()
	assert_null(effect.spawn(null, SPAWN_POSITION), "there is nothing to instantiate")
	assert_eq(_spy.spawns.size(), 0, "the seam is not asked for a null scene")


func test_spawn_returns_null_when_the_seam_has_no_container() -> void:
	var effect: Effect = _attach()
	_spy.container = null
	assert_null(effect.spawn(_plain_scene(), SPAWN_POSITION), "the seam refuses with no world to parent into")
	assert_eq(_spy.spawns.size(), 1, "it was asked, and refused")


# --- fire_projectile ------------------------------------------------------

func test_fire_projectile_asks_the_hosts_spawner_with_the_spec() -> void:
	var effect: Effect = _attach()
	var spec: ProjectileSpec = _spec()
	effect.fire_projectile(spec, PROJECTILE_FROM, PROJECTILE_DIR)
	assert_eq(_spy.projectiles.size(), 1, "the seam was asked exactly once")
	assert_eq(_spy.last_projectile_spec(), spec, "and it is the caller's spec, not a copy")


func test_fire_projectile_forwards_the_specs_numbers() -> void:
	var effect: Effect = _attach()
	effect.fire_projectile(_spec(), PROJECTILE_FROM, PROJECTILE_DIR)
	var spec: ProjectileSpec = _spy.last_projectile_spec()
	assert_almost_eq(spec.speed, SPEC_SPEED, EPSILON, "speed")
	assert_almost_eq(spec.damage, SPEC_DAMAGE, EPSILON, "damage")
	assert_eq(spec.element, HitInfo.Element.FIRE, "element")
	assert_eq(spec.pierce, SPEC_PIERCE, "pierce")
	assert_eq(spec.bounce, SPEC_BOUNCE, "bounce")
	assert_eq(_spy.projectiles[0]["from"], PROJECTILE_FROM, "from")
	assert_eq(_spy.projectiles[0]["direction"], PROJECTILE_DIR, "direction")


func test_fire_projectile_carries_the_source_id_and_the_depth() -> void:
	var effect: Effect = _attach()
	effect.fire_projectile(_spec(), PROJECTILE_FROM, PROJECTILE_DIR)
	assert_eq(_spy.projectiles[0]["proc_source_id"], SOURCE_ID, "the firing content is recorded")
	assert_eq(_spy.projectiles[0]["proc_depth"], TRIGGER_DEPTH + 1, "and the depth the trigger produced")


## The same relationship `deal_damage` has (pinned in `test_effect_helpers.gd`),
## asserted side by side so the two cannot drift.
func test_fire_projectile_increments_the_proc_depth_like_deal_damage() -> void:
	var effect: Effect = _attach()
	effect.trigger_depth = TRIGGER_DEPTH
	var hit := HitInfo.new()
	effect.deal_damage(_player, hit)
	effect.fire_projectile(_spec(), PROJECTILE_FROM, PROJECTILE_DIR)
	assert_eq(hit.proc_depth, TRIGGER_DEPTH + 1, "deal_damage: trigger + 1")
	assert_eq(_spy.projectiles[0]["proc_depth"], hit.proc_depth, "fire_projectile: the same rule")


func test_fire_projectile_through_the_real_projectile_spawner() -> void:
	# The shipping `ProjectileSpawner` plus its placeholder scene: the seam's own
	# production path, exercised for real rather than through the spy's
	# recording alone.
	var holder := Node2D.new()
	add_child_autofree(holder)
	var spawner := ProjectileSpawner.new()
	spawner.spawn_path = ^".."
	holder.add_child(spawner)
	_spy.projectile_spawner = spawner
	var effect: Effect = _attach()
	var node: Node = effect.fire_projectile(_spec(), PROJECTILE_FROM, PROJECTILE_DIR)
	assert_not_null(node, "the projectile spawned")
	assert_eq(node.get_parent(), holder, "under the projectile spawner's spawn path")
	assert_eq((node as Node2D).position, PROJECTILE_FROM, "at the firing position")
	assert_eq(
		EffectSpawner.read_stamp(node, EffectSpawner.PROC_SOURCE_ID), SOURCE_ID,
		"stamped with the firing content")
	assert_eq(
		int(EffectSpawner.read_stamp(node, EffectSpawner.PROC_DEPTH)), TRIGGER_DEPTH + 1,
		"and the depth")
	assert_almost_eq(
		float(EffectSpawner.read_stamp(node, EffectSpawner.SPEC_SPEED)), SPEC_SPEED, EPSILON,
		"the spec's speed reached the projectile")
	assert_almost_eq(
		float(EffectSpawner.read_stamp(node, EffectSpawner.SPEC_DAMAGE)), SPEC_DAMAGE, EPSILON,
		"damage")
	assert_eq(int(EffectSpawner.read_stamp(node, EffectSpawner.SPEC_PIERCE)), SPEC_PIERCE, "pierce")
	assert_eq(int(EffectSpawner.read_stamp(node, EffectSpawner.SPEC_BOUNCE)), SPEC_BOUNCE, "bounce")


func test_fire_projectile_refuses_on_a_client_and_never_reaches_the_spawner() -> void:
	var client_host := _make_client_host(_player)
	var effect: Effect = client_host.add(_source)
	assert_null(effect.fire_projectile(_spec(), PROJECTILE_FROM, PROJECTILE_DIR), "a client shot is refused")
	assert_eq(_spy.projectiles.size(), 0, "and the spawner was never asked")


func test_fire_projectile_without_a_spawner_is_a_warned_no_op() -> void:
	var effect: Effect = _attach()
	_host.spawner = null
	assert_null(effect.fire_projectile(_spec(), PROJECTILE_FROM, PROJECTILE_DIR), "nothing is fired")
	assert_eq(_spy.projectiles.size(), 0, "the absent seam is not reached")


func test_fire_projectile_without_a_host_is_a_warned_no_op() -> void:
	var effect := Effect.new()
	_player.add_child(effect)
	effect.attach(_player, _source, 1)
	assert_null(effect.fire_projectile(_spec(), PROJECTILE_FROM, PROJECTILE_DIR), "an effect with no host fires nothing")
	assert_eq(_spy.projectiles.size(), 0, "and never reaches a spawner")
	effect.detach()


func test_fire_projectile_without_a_spec_is_refused() -> void:
	var effect: Effect = _attach()
	assert_null(effect.fire_projectile(null, PROJECTILE_FROM, PROJECTILE_DIR), "there is nothing to fire")
	assert_eq(_spy.projectiles.size(), 0, "the seam is not asked for a null spec")


func test_fire_projectile_without_a_projectile_spawner_is_a_warned_no_op() -> void:
	var effect: Effect = _attach()
	assert_null(effect.fire_projectile(_spec(), PROJECTILE_FROM, PROJECTILE_DIR), "the seam has no projectile spawner wired")
	assert_eq(_spy.projectiles.size(), 1, "it was asked, and refused")


# --- doubles -------------------------------------------------------------

## Replaces `player`'s host with a client copy: GUT runs one instance per
## process and the offline peer is always the server, so the client branch is
## driven through the `_can_spawn()` seam the production host exposes, exactly
## as `test_entity_spawners.gd` drives `EnemySpawner`'s.
func _make_client_host(player: Player) -> EffectHost:
	var existing: Node = player.get_node_or_null(NodePath(EffectHost.NODE_NAME))
	if existing != null:
		player.remove_child(existing)
		existing.free()
	var host := _FakeClientEffectHost.new()
	host.name = EffectHost.NODE_NAME
	player.add_child(host)
	host.spawner = _spy
	return host


class _FakeClientEffectHost:
	extends EffectHost
	## A client copy of the host: `_can_spawn()` is false there, so every
	## spawn request is refused before the seam is reached.
	func _can_spawn() -> bool:
		return false


class SetupProbe:
	## Records how `Effect.spawn()` ran the caller's `setup` callable: how often,
	## on which node, and whether that node was already in the tree.
	var calls: int = 0
	var node: Node = null
	var was_inside_tree: bool = true
	var parent_at_setup: Node = null

	func run(instance: Node) -> void:
		calls += 1
		node = instance
		was_inside_tree = instance.is_inside_tree()
		parent_at_setup = instance.get_parent()
