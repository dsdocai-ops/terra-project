extends GutTest
## Tests for `Effect` — effect-system, W4-B2 (goal G10).
##
## `Effect` is the base every relic, mutation, synergy, class passive,
## Ascension and skill node is written as, and `detach()` is the whole point of
## the class: a relic dropped at a Shrine, or an effect torn down on room exit,
## must leave no `StatBlock` modifier, no timer and no connection behind, or it
## keeps changing the game after it is gone. This file therefore attaches an
## effect that does all three and asserts the total cleanup.
##
## The player double is the real player scene with the `StatBlock` component
## hung on its `StatBlock` node — the same shape `test_hud_model.gd` uses for
## Dev A's missing `Health`. The player scene's component nodes are bare until
## their owning module lands (`player.gd`'s `TODO(stats-status)`), so the
## double supplies the component the effect resolves by name, and one case
## asserts the guarded no-op for a player that has none.
##
## Sync: none under test. `Effect` is host-only logic; the client half is
## "clients hold no `Effect` instances" (SPEC-effect-system), which is the
## absence of a client path rather than a replicated field.

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const STAT_BLOCK_SCRIPT_PATH: String = "res://scripts/components/stat_block.gd"
const EFFECT_SCRIPT_PATH: String = "res://scripts/effects/effect.gd"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
const EPSILON: float = 0.0001

## The spec's public surface for the base class (SPEC-effect-system, "Effect
## base class"), minus the helpers the later W4-B2 goals fill in.
const SPEC_MEMBERS: Array[String] = ["player", "source", "stacks", "stat_block", "_handles", "_timers"]
const SPEC_METHODS: Array[String] = ["attach", "detach", "_on_attach", "_on_detach", "listen", "modify"]

var _player: Player
var _block: StatBlock
var _source: ContentData
## Every effect this test attached, so no listener is left on the global bus.
var _effects: Array[Effect] = []


## The effect under test: adds two modifiers, opens one timer and makes one
## listener, counting every lifecycle call so the test can pin them.
class TrackedEffect:
	extends Effect

	const TIMER_SECONDS: float = 30.0

	var attach_calls: int = 0
	var detach_calls: int = 0
	var timer_calls: int = 0
	var kills_seen: int = 0

	func _on_attach() -> void:
		attach_calls += 1
		modify(StatBlock.Stat.ATTACK, 5.0, 0.1)
		modify(StatBlock.Stat.MOVE_SPEED, 0.0, 0.25)
		_start_timer(TIMER_SECONDS, _on_timer)
		listen(Events.enemy_killed, _on_enemy_killed)

	func _on_detach() -> void:
		detach_calls += 1

	func _on_timer() -> void:
		timer_calls += 1

	func _on_enemy_killed(_enemy: Node, _hit: HitData) -> void:
		kills_seen += 1


func before_each() -> void:
	_player = _make_player(true)
	_block = _player.get_node(STAT_BLOCK_NODE) as StatBlock
	_source = ContentData.new()
	_source.id = &"test_relic"
	_source.display_name = "Test Relic"


func after_each() -> void:
	for effect: Effect in _effects:
		effect.detach()
	_effects.clear()


## The real player scene, with the StatBlock component hung on its bare
## `StatBlock` node unless `with_stat_block` is false.
func _make_player(with_stat_block: bool) -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	if with_stat_block:
		var component: Node = player.get_node(STAT_BLOCK_NODE)
		component.set_script(load(STAT_BLOCK_SCRIPT_PATH) as Script)
		var block := component as StatBlock
		block.base = {
			StatBlock.Stat.ATTACK: 100.0,
			StatBlock.Stat.MOVE_SPEED: 120.0,
		}
	add_child_autofree(player)
	return player


func _attach(effect: Effect, source: ContentData = null, stacks: int = 1) -> Effect:
	var content: ContentData = _source if source == null else source
	_player.add_child(effect)
	effect.attach(_player, content, stacks)
	_effects.append(effect)
	return effect


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


## True when the line declaring `func <name>(` is preceded by a `##` doc line,
## so an undocumented method fails rather than passing on its name alone.
func _documented(source: String, method_name: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for i: int in range(1, lines.size()):
		if lines[i].begins_with("func %s(" % method_name):
			return lines[i - 1].strip_edges().begins_with("##")
	return false


func test_the_script_declares_the_spec_surface_documented_and_host_owned() -> void:
	var script: GDScript = load(EFFECT_SCRIPT_PATH) as GDScript
	assert_not_null(script, "scripts/effects/effect.gd must exist")
	if script == null:
		return
	var source: String = FileAccess.get_file_as_string(EFFECT_SCRIPT_PATH)
	assert_true(source.contains("class_name Effect"), "class_name Effect")
	assert_eq(script.get_instance_base_type(), "Node", "extends Node")
	assert_true(source.contains("## Sync: host only"), "the ownership line")
	for member: String in SPEC_MEMBERS:
		assert_true(_script_property_names(script).has(member), "declares member %s" % member)
	for method_name: String in SPEC_METHODS:
		assert_true(_script_method_names(script).has(method_name), "declares method %s" % method_name)
		assert_true(_documented(source, method_name), "%s carries a doc comment" % method_name)


func test_attach_carries_player_source_and_stacks() -> void:
	var effect: Effect = _attach(TrackedEffect.new(), _source, 3)
	assert_eq(effect.player, _player)
	assert_eq(effect.source, _source)
	assert_eq(effect.stacks, 3)
	assert_true(effect.is_attached())


func test_stacks_default_to_one() -> void:
	var effect: Effect = _attach(TrackedEffect.new())
	assert_eq(effect.stacks, 1)


func test_on_attach_and_on_detach_each_run_once_per_cycle() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	assert_eq(effect.attach_calls, 1, "_on_attach runs exactly once")
	assert_eq(effect.detach_calls, 0, "_on_detach has not run yet")
	effect.detach()
	assert_eq(effect.detach_calls, 1, "_on_detach runs exactly once")
	effect.detach()
	assert_eq(effect.detach_calls, 1, "a second detach runs no second _on_detach")
	assert_false(effect.is_attached())


func test_a_second_attach_without_a_detach_is_refused() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	effect.attach(_player, _source, 9)
	assert_eq(effect.attach_calls, 1, "no second _on_attach")
	assert_eq(effect.stacks, 1, "the first attach's stacks stand")


func test_detach_removes_every_modifier_the_effect_added() -> void:
	var effect: Effect = _attach(TrackedEffect.new())
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 115.5, EPSILON, "two modifiers are live")
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), 150.0, EPSILON)
	effect.detach()
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 100.0, EPSILON, "no modifier left behind")
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), 120.0, EPSILON, "no modifier left behind")
	assert_true(effect._handles.is_empty(), "no handle left tracked")


func test_detach_leaves_another_effects_modifier_alone() -> void:
	var other := ContentData.new()
	other.id = &"other_relic"
	var first: Effect = _attach(TrackedEffect.new(), _source)
	var second: Effect = _attach(TrackedEffect.new(), other)
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 132.0, EPSILON, "both effects are live")
	first.detach()
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 115.5, EPSILON, "only the detached effect's modifier went")
	second.detach()
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 100.0, EPSILON)


func test_the_effect_id_is_the_modifier_source() -> void:
	var effect: Effect = _attach(TrackedEffect.new())
	assert_eq(effect.source_id(), &"test_relic")
	_block.remove_source(&"test_relic")
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 100.0, EPSILON, "the modifiers carried the effect's id")


func test_detach_frees_every_timer_and_takes_it_out_of_the_tree() -> void:
	var effect: Effect = _attach(TrackedEffect.new())
	assert_eq(effect._timers.size(), 1, "the effect opened one timer")
	var timer: Timer = effect._timers[0]
	assert_true(timer.is_inside_tree(), "the timer is live while attached")
	effect.detach()
	assert_true(effect._timers.is_empty(), "no timer left tracked")
	await wait_process_frames(1)
	assert_false(is_instance_valid(timer), "the timer is freed")
	assert_eq(effect.get_child_count(), 0, "and out of the tree")


func test_listen_records_a_named_method_and_fires_it() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	assert_eq(effect._connections.size(), 1, "one connection recorded")
	Events.enemy_killed.emit(_player, null)
	assert_eq(effect.kills_seen, 1, "the named method fires while attached")


func test_detach_disconnects_every_listener() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	Events.enemy_killed.emit(_player, null)
	assert_eq(effect.kills_seen, 1)
	effect.detach()
	Events.enemy_killed.emit(_player, null)
	assert_eq(effect.kills_seen, 1, "no event reaches a detached effect")
	assert_false(Events.enemy_killed.is_connected(effect._on_enemy_killed), "the connection is gone")
	assert_true(effect._connections.is_empty(), "and no pair left recorded")


func test_detach_on_an_unattached_effect_is_a_safe_no_op() -> void:
	var effect := TrackedEffect.new()
	autofree(effect)
	assert_false(effect.is_attached())
	effect.detach()
	assert_false(effect.is_attached())
	assert_eq(effect.detach_calls, 0, "_on_detach never runs for a cycle that never started")
	assert_eq(effect.get_child_count(), 0)


func test_modify_is_a_guarded_no_op_without_a_stat_block() -> void:
	var bare: Player = _make_player(false)
	var effect: Effect = TrackedEffect.new()
	bare.add_child(effect)
	effect.attach(bare, _source, 1)
	_effects.append(effect)
	assert_null(effect.stat_block, "the player carries no StatBlock component yet")
	assert_true(effect._handles.is_empty(), "no handle recorded for a modifier that could not land")
	effect.detach()


func test_a_tracked_timer_fires_and_is_still_tracked_afterwards() -> void:
	var effect: Effect = _attach(TrackedEffect.new())
	var timer: Timer = effect._timers[0]
	assert_true(timer.one_shot, "the helper opens one-shot timers")
	timer.start(0.0)
	await wait_process_frames(1)
	assert_true(effect._timers.has(timer), "a fired timer stays tracked so detach can free it")
	assert_true(is_instance_valid(timer))
