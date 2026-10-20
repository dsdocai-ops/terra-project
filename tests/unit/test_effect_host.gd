extends GutTest
## Tests for `EffectHost` — effect-system, W4-B2 (goal G14).
##
## `EffectHost` is the node every player carries and the one place effects are
## attached: it keys them by source id, hands each one the host's own generator
## and its player, exposes the tag counts synergies are evaluated against
## (`SynergyTracker` recomputes from `list_tags()` on every pick and removal),
## and is the single lookup path `RelicRoller` and the HUD use. The cases below
## assert the lifecycle one claim at a time: instantiate-and-attach, the three
## refusals (no `effect_script`, a non-`Effect` script, an id already attached),
## detach-and-free, lookup, and tag counting weighted by stacks.
##
## The dispatch case goes through the real path an effect uses: two hosts on two
## players, each carrying a `EffectHostProbe` whose listener was registered by
## `Effect.listen()`. Emitting `player_dodged` for one player must reach only
## that player's effect, and a removed effect must stop receiving events — the
## host's half of "the single dispatch point".
##
## The player double is the real player scene plus an `EffectHost` installed by
## `tests/helpers/effect_host_player.gd`, because `player.tscn` is Dev A's and
## this lane does not edit it (the `fake_health.gd` pattern).
##
## Sync: none under test. `EffectHost` is host-only (SPEC-effect-system:
## "clients hold no `Effect` instances"); nothing here is replicated, so there
## is no client half to assert in one process.

const EFFECT_HOST_PATH: String = "res://scripts/effects/effect_host.gd"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const STAT_BLOCK_SCRIPT_PATH: String = "res://scripts/components/stat_block.gd"
const NON_EFFECT_SCRIPT_PATH: String = "res://scripts/effects/tags.gd"
const PROBE_SCRIPT_PATH: String = "res://tests/helpers/effect_host_probe.gd"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"

## The spec's surface for the host (SPEC-effect-system, "Effect base class").
const SPEC_METHODS: Array[String] = ["add", "remove", "get_effect", "list_tags"]

var _player: Player
var _host: EffectHost
var _other_player: Player
var _other_host: EffectHost


func before_each() -> void:
	_player = _make_player()
	_host = EffectHostPlayer.install(_player)
	_other_player = _make_player()
	_other_host = EffectHostPlayer.install(_other_player)


func after_each() -> void:
	for host: EffectHost in [_host, _other_host]:
		for effect: Effect in host.effects():
			if effect.source != null:
				host.remove(effect.source)


## The real player scene with the `StatBlock` component installed on its bare
## node, so attaching an effect does not warn about a missing component.
func _make_player() -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	var component: Node = player.get_node(STAT_BLOCK_NODE)
	component.set_script(load(STAT_BLOCK_SCRIPT_PATH) as Script)
	add_child_autofree(player)
	return player


## A content source carrying the probe script, an id and tags.
func _source(id: StringName, tags: Array[StringName] = [], script_path: String = PROBE_SCRIPT_PATH) -> ContentData:
	var content := ContentData.new()
	content.id = id
	content.display_name = String(id)
	content.tags = tags
	content.effect_script = load(script_path) as GDScript
	return content


func _script_property_names(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for property: Dictionary in script.get_script_property_list():
		names.append(String(property["name"]))
	return names


func _script_method_names(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for method: Dictionary in script.get_script_method_list():
		names.append(String(method["name"]))
	return names


## True when the line declaring `func <name>(` is preceded by a `##` doc line.
func _documented(source: String, method_name: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for i: int in range(1, lines.size()):
		if lines[i].begins_with("func %s(" % method_name):
			return lines[i - 1].strip_edges().begins_with("##")
	return false


func test_the_script_declares_the_spec_surface_documented_and_host_owned() -> void:
	var script: GDScript = load(EFFECT_HOST_PATH) as GDScript
	assert_not_null(script, "scripts/effects/effect_host.gd must exist")
	if script == null:
		return
	var source: String = FileAccess.get_file_as_string(EFFECT_HOST_PATH)
	assert_true(source.contains("class_name EffectHost"), "class_name EffectHost")
	assert_eq(script.get_instance_base_type(), "Node", "extends Node")
	assert_true(source.contains("## Sync: host only"), "the ownership line")
	for method_name: String in SPEC_METHODS:
		assert_true(_script_method_names(script).has(method_name), "declares method %s" % method_name)
		assert_true(_documented(source, method_name), "%s carries a doc comment" % method_name)
	assert_true(_script_property_names(script).has("player"), "exposes the player it drives")
	assert_true(_script_property_names(script).has("rng"), "owns the generator it hands out")


func test_add_instantiates_the_source_effect_script_under_the_host() -> void:
	var source: ContentData = _source(&"test_relic")
	var effect: Effect = _host.add(source)
	assert_not_null(effect, "add returns the new effect")
	if effect == null:
		return
	assert_eq(effect.get_parent(), _host, "the effect is parented to the host")
	assert_eq(_host.get_child_count(), 1, "exactly one child was added")
	assert_eq(effect.get_script(), source.effect_script, "the source's own script")
	assert_true(_host.effects().has(effect), "the host lists it")


func test_add_attaches_with_the_hosts_player_source_and_stacks() -> void:
	var source: ContentData = _source(&"test_relic")
	var effect: Effect = _host.add(source, 3)
	assert_not_null(effect)
	if effect == null:
		return
	assert_eq(effect.player, _player, "the host's player")
	assert_eq(effect.source, source, "the source it was added for")
	assert_eq(effect.stacks, 3, "the requested stacks")
	assert_true(effect.is_attached(), "attach ran")
	assert_eq((effect as EffectHostProbe).attach_calls, 1, "_on_attach ran exactly once")


func test_stacks_default_to_one() -> void:
	var effect: Effect = _host.add(_source(&"test_relic"))
	assert_not_null(effect)
	if effect != null:
		assert_eq(effect.stacks, 1)


func test_add_is_refused_when_the_source_has_no_effect_script() -> void:
	var source: ContentData = _source(&"scriptless")
	source.effect_script = null
	assert_null(_host.add(source), "a source with no effect_script is refused")
	assert_eq(_host.get_child_count(), 0, "nothing was instanced")
	assert_eq(_host.effect_count(), 0, "nothing was recorded")


func test_add_is_refused_when_the_script_does_not_extend_effect() -> void:
	var source: ContentData = _source(&"not_an_effect", [], NON_EFFECT_SCRIPT_PATH)
	assert_null(_host.add(source), "a script that is not an Effect is refused")
	assert_eq(_host.get_child_count(), 0, "nothing was parented")
	assert_eq(_host.effect_count(), 0, "nothing was recorded")


func test_add_is_refused_for_the_same_id_twice() -> void:
	var source: ContentData = _source(&"test_relic")
	var first: Effect = _host.add(source, 1)
	assert_not_null(first)
	if first == null:
		return
	var second: ContentData = _source(&"test_relic")
	assert_null(_host.add(second, 2), "a second source with the same id is refused")
	assert_eq(_host.effect_count(), 1, "still one effect")
	assert_eq(_host.get_child_count(), 1, "no second node")
	assert_same(_host.get_effect(&"test_relic"), first, "the original stays attached")
	assert_eq(first.stacks, 1, "the refused add did not change its stacks")


func test_add_refuses_a_null_source_and_an_empty_id() -> void:
	assert_null(_host.add(null), "a null source is refused")
	var nameless: ContentData = _source(&"")
	assert_null(_host.add(nameless), "a source with no id is refused")
	assert_eq(_host.effect_count(), 0)


func test_remove_detaches_and_frees_the_effect() -> void:
	var source: ContentData = _source(&"test_relic")
	var effect: Effect = _host.add(source)
	assert_not_null(effect)
	if effect == null:
		return
	var probe: EffectHostProbe = effect as EffectHostProbe
	assert_true(_host.remove(source), "remove reports it removed something")
	assert_false(effect.is_attached(), "detach ran")
	assert_eq(probe.detach_calls, 1, "_on_detach ran exactly once")
	assert_eq(probe.dodge_calls, 0)
	assert_null(_host.get_effect(&"test_relic"), "the lookup no longer finds it")
	assert_eq(_host.effect_count(), 0, "the key was erased")
	await wait_process_frames(1)
	assert_false(is_instance_valid(effect), "the node was freed")


func test_remove_of_an_unknown_source_is_a_warned_no_op() -> void:
	assert_false(_host.remove(null), "a null source removes nothing")
	assert_false(_host.remove(_source(&"never_added")), "an unattached source removes nothing")
	assert_eq(_host.effect_count(), 0)


func test_get_effect_returns_the_live_effect_or_null() -> void:
	assert_null(_host.get_effect(&"absent"), "nothing attached gives null")
	var source: ContentData = _source(&"test_relic")
	var effect: Effect = _host.add(source)
	assert_not_null(effect)
	assert_same(_host.get_effect(&"test_relic"), effect, "the live effect is returned")
	assert_true(_host.has_effect(&"test_relic"))
	assert_false(_host.has_effect(&"absent"))


func test_list_tags_is_empty_when_nothing_is_attached() -> void:
	var tags: Dictionary = _host.list_tags()
	assert_true(tags.is_empty(), "an empty host has no tags")
	assert_eq(_host.effect_count(), 0)


func test_list_tags_counts_every_tag_weighted_by_stacks() -> void:
	var first: ContentData = _source(&"relic_a", [&"fire", &"dodge"] as Array[StringName])
	var second: ContentData = _source(&"relic_b", [&"fire", &"storm"] as Array[StringName])
	_host.add(first, 1)
	_host.add(second, 3)
	var tags: Dictionary = _host.list_tags()
	assert_eq(int(tags.get(&"fire", 0)), 4, "fire: 1 + 3 stacks")
	assert_eq(int(tags.get(&"dodge", 0)), 1, "dodge from the single-stack relic")
	assert_eq(int(tags.get(&"storm", 0)), 3, "storm: 3 stacks")
	assert_eq(tags.size(), 3, "no tag is counted twice")


func test_list_tags_drops_a_removed_effects_tags() -> void:
	var source: ContentData = _source(&"relic_a", [&"fire"] as Array[StringName])
	_host.add(source, 2)
	assert_eq(int(_host.list_tags().get(&"fire", 0)), 2)
	assert_true(_host.remove(source))
	assert_true(_host.list_tags().is_empty(), "removal drops the contribution")


func test_the_helper_installs_the_host_as_a_child_named_effect_host() -> void:
	var resolved: Node = _player.get_node_or_null(NodePath(EffectHostPlayer.HOST_NAME))
	assert_not_null(resolved, "player.EffectHost resolves by name")
	assert_true(resolved is EffectHost, "and it is an EffectHost")
	assert_same(resolved, _host, "the helper returned the installed host")
	assert_eq(_host.player, _player, "the host resolved its player from the tree")
	assert_same(EffectHostPlayer.install(_player), _host, "install is idempotent")


func test_events_reach_only_the_effects_on_the_owning_host() -> void:
	var source: ContentData = _source(&"test_relic")
	var mine: EffectHostProbe = _host.add(source) as EffectHostProbe
	var theirs: EffectHostProbe = _other_host.add(_source(&"other_relic")) as EffectHostProbe
	assert_not_null(mine)
	assert_not_null(theirs)
	if mine == null or theirs == null:
		return
	Events.player_dodged.emit(_player, true)
	assert_eq(mine.dodge_calls, 1, "the owner's effect reacts")
	assert_eq(theirs.dodge_calls, 0, "the other player's effect does not")
	assert_eq(mine.last_dodge_player, _player)
	Events.player_dodged.emit(_other_player, false)
	assert_eq(mine.dodge_calls, 1, "the other player's dodge does not reach this host")
	assert_eq(theirs.dodge_calls, 1)
	_host.remove(source)
	Events.player_dodged.emit(_player, true)
	assert_eq(mine.dodge_calls, 1, "a removed effect stops receiving events")


func test_effects_share_the_hosts_generator() -> void:
	var first: Effect = _host.add(_source(&"relic_a"))
	var second: Effect = _host.add(_source(&"relic_b"))
	assert_not_null(_host.rng, "the host owns a generator")
	assert_not_null(first)
	assert_not_null(second)
	if first == null or second == null:
		return
	assert_same(first.rng, _host.rng, "the host's generator is handed to the effect")
	assert_same(second.rng, first.rng, "and the same one to the next effect")
