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
const SPEC_METHODS: Array[String] = ["attach", "detach", "_on_attach", "_on_detach", "listen", "every_seconds", "once_per_room", "modify"]

## The listeners `TrackedEffect` makes in `_on_attach()`, in order: two signals
## with no `Player` argument but a hit payload (`enemy_killed`, wrapped for the
## proc gate), one with neither (`room_cleared`, connected untouched), two whose
## `Player` argument is filtered (index 0 on `player_dodged`, index 1 on
## `room_entered`), plus the base class's own `room_entered` reset subscription.
const LISTENERS_PER_EFFECT: int = 5

var _player: Player
var _other_player: Player
var _block: StatBlock
var _source: ContentData
## Every effect this test attached, so no listener is left on the global bus.
var _effects: Array[Effect] = []


## The effect under test: adds two modifiers, opens one timer and makes its
## listeners, counting every lifecycle call so the test can pin them.
class TrackedEffect:
	extends Effect

	const TIMER_SECONDS: float = 30.0

	var attach_calls: int = 0
	var detach_calls: int = 0
	var timer_calls: int = 0
	var kills_seen: int = 0
	## Dodges seen at all, and dodges that belonged to someone else. The second
	## only moves if a foreign event is forwarded, so it is the filter's
	## negative control rather than a second way to say the same thing.
	var dodge_calls: int = 0
	var foreign_dodges: int = 0
	var last_dodge_player: Player = null
	var last_perfect: bool = false
	var rooms_seen: int = 0
	## `room_cleared` events seen: the signal with no `Player` argument and no
	## hit, which `listen()` therefore connects untouched.
	var clears_seen: int = 0

	func _on_attach() -> void:
		attach_calls += 1
		modify(StatBlock.Stat.ATTACK, 5.0, 0.1)
		modify(StatBlock.Stat.MOVE_SPEED, 0.0, 0.25)
		_start_timer(TIMER_SECONDS, _on_timer)
		listen(Events.enemy_killed, _on_enemy_killed)
		listen(Events.room_cleared, _on_room_cleared)
		listen(Events.player_dodged, _on_player_dodged)
		listen(Events.room_entered, _on_room_seen)

	func _on_detach() -> void:
		detach_calls += 1

	func _on_timer() -> void:
		timer_calls += 1

	func _on_enemy_killed(_enemy: Node, _hit: HitData) -> void:
		kills_seen += 1

	func _on_room_cleared(_room: Node) -> void:
		clears_seen += 1

	func _on_player_dodged(event_player: Player, perfect: bool) -> void:
		dodge_calls += 1
		if event_player != player:
			foreign_dodges += 1
		last_dodge_player = event_player
		last_perfect = perfect

	func _on_room_seen(_room: Node, event_player: Player) -> void:
		rooms_seen += 1
		if event_player != player:
			foreign_dodges += 1


func before_each() -> void:
	_player = _make_player(true)
	_other_player = _make_player(true)
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


## A hit payload at `depth`, for the proc-gate case: the only thing that makes
## an event a link in a proc chain.
func _hit_at_depth(depth: int) -> HitData:
	var hit := HitData.new()
	hit.proc_depth = depth
	return hit


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
	assert_eq(effect._connections.size(), LISTENERS_PER_EFFECT, "every listener is recorded for detach")
	Events.enemy_killed.emit(_player, null)
	assert_eq(effect.kills_seen, 1, "the named method fires while attached")


## A signal with no `Player` argument is connected untouched, and the named
## method itself is the connection — the filter must not wrap what it has no
## reason to look at. `room_cleared(room)` is that signal: no player, no hit.
func test_listen_leaves_a_signal_without_a_player_argument_unfiltered() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	assert_true(Events.room_cleared.is_connected(effect._on_room_cleared), "connected directly")
	Events.room_cleared.emit(_other_player)
	assert_eq(effect.clears_seen, 1, "any node reaches the handler; nothing is looked at")


## A signal that carries a hit is wrapped even though it has no `Player`
## argument: the proc depth limit is applied on the way in (W4-B3, goal G16), so
## `hit_landed` — the busiest event in the game — cannot skip the gate by having
## no player to filter on. The filter itself still does not gate it: an enemy
## that is not a Player reaches the handler, as before.
func test_listen_wraps_a_hit_carrying_signal_without_a_player_argument() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	assert_false(
		Events.enemy_killed.is_connected(effect._on_enemy_killed),
		"wrapped, so the proc gate runs before the handler"
	)
	Events.enemy_killed.emit(_other_player, null)
	assert_eq(effect.kills_seen, 1, "an argument that is not a Player does not gate it")
	Events.enemy_killed.emit(_other_player, _hit_at_depth(Effect.MAX_PROC_DEPTH))
	assert_eq(effect.kills_seen, 1, "a hit that has reached the depth limit does")


## The filter: an effect attached to player 1 reacts to player 1's dodge and
## never to player 2's. The negative control is `dodge_calls` staying at zero —
## the handler did not run at all — rather than a counter merely being lower.
func test_listen_filters_an_event_that_belongs_to_another_player() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	Events.player_dodged.emit(_other_player, true)
	assert_eq(effect.dodge_calls, 0, "player 2's dodge never reaches player 1's effect")
	assert_eq(effect.foreign_dodges, 0, "and nothing was forwarded to be counted")
	Events.player_dodged.emit(_player, true)
	assert_eq(effect.dodge_calls, 1, "player 1's own dodge does")
	assert_eq(effect.last_dodge_player, _player, "and the handler saw the real arguments")
	assert_true(effect.last_perfect, "including everything after the player argument")


## The `Player` argument is found where the signal declares it, not assumed to
## be first: `room_entered(room, player)` carries it at index 1.
func test_listen_finds_the_player_argument_where_the_signal_declares_it() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	var room: Node = add_child_autofree(Node.new())
	Events.room_entered.emit(room, _other_player)
	assert_eq(effect.rooms_seen, 0, "a teammate's entry does not reach this effect's handler")
	Events.room_entered.emit(room, _player)
	assert_eq(effect.rooms_seen, 1, "its own player's entry does")


func test_detach_disconnects_a_filtered_listener() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	Events.player_dodged.emit(_player, false)
	assert_eq(effect.dodge_calls, 1)
	effect.detach()
	assert_false(Events.player_dodged.is_connected(effect._on_player_dodged), "the wrapper is gone")
	Events.player_dodged.emit(_player, false)
	assert_eq(effect.dodge_calls, 1, "no event reaches a detached effect")


func test_once_per_room_is_true_once_and_false_after() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	assert_true(effect.once_per_room(&"second_wind"), "the first ask in a room is granted")
	assert_false(effect.once_per_room(&"second_wind"), "and every later ask is refused")
	assert_false(effect.once_per_room(&"second_wind"))


func test_once_per_room_keys_are_independent() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	assert_true(effect.once_per_room(&"second_wind"))
	assert_true(effect.once_per_room(&"panic_button"), "another key is its own budget")
	assert_false(effect.once_per_room(&"second_wind"))
	assert_false(effect.once_per_room(&"panic_button"))


func test_once_per_room_resets_when_a_room_is_entered() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	var room: Node = add_child_autofree(Node.new())
	assert_true(effect.once_per_room(&"cracked_shell"))
	assert_false(effect.once_per_room(&"cracked_shell"))
	Events.room_entered.emit(room, _player)
	assert_true(effect.once_per_room(&"cracked_shell"), "a new room grants it again")


## The reset is the room's, not the entering player's: `room_entered` fires once
## per player who walks in, and a teammate's entry must not leave a class
## passive spent from the previous room (the base subscribes directly, never
## through the player filter).
func test_once_per_room_resets_on_any_players_room_entry() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	var room: Node = add_child_autofree(Node.new())
	assert_true(effect.once_per_room(&"cracked_shell"))
	Events.room_entered.emit(room, _other_player)
	assert_true(effect.once_per_room(&"cracked_shell"))


func test_once_per_room_is_its_own_budget_on_each_effect() -> void:
	var first: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	var second: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	assert_true(first.once_per_room(&"second_wind"))
	assert_false(first.once_per_room(&"second_wind"))
	assert_true(second.once_per_room(&"second_wind"), "one effect's spend is not another's")


func test_detach_disconnects_the_room_listener_and_clears_the_keys() -> void:
	var effect: TrackedEffect = _attach(TrackedEffect.new()) as TrackedEffect
	assert_true(Events.room_entered.is_connected(effect._on_room_entered), "the base subscribed")
	assert_true(effect.once_per_room(&"second_wind"))
	effect.detach()
	assert_false(Events.room_entered.is_connected(effect._on_room_entered), "the reset listener is gone")
	assert_true(effect._room_keys.is_empty(), "and no spent key survives the detach")
	effect.attach(_player, _source, 1)
	assert_true(effect.once_per_room(&"second_wind"), "a fresh cycle starts with a fresh budget")


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
