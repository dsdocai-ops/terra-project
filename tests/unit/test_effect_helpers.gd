extends GutTest
## Tests for `Effect`'s four data helpers — effect-system, W4-B2 (goal G12).
##
## These four are the whole surface a data relic's effect script uses to change
## the game: `modify` adds a stat modifier through a handle, `chance` rolls on
## the host's own seeded generator, `apply_status` applies one of the seven
## statuses, and `deal_damage` stamps a hit's proc depth and delivers it to the
## target. `test_effect_base.gd` covers the attach/detach lifecycle those
## helpers hang off; this file pins the helper contracts themselves, including
## their negative controls: no base stat is ever written, `chance` draws nothing
## at the extremes, and `apply_status` / `deal_damage` are guarded no-ops when
## the target carries no component to receive them.
##
## The `StatusEffects` component (stats-status, W4-B4 / goal G20) and Dev A's
## `Hurtbox` (combat-core, W2-A2) do not exist yet, so both call sites are
## asserted against `tests/helpers/` doubles carrying the spec's own
## signatures: `StatusEffectsStub` and `HurtboxStub`. The player double is the
## real player scene with those components hung on its bare nodes — the shape
## `test_effect_base.gd` and `test_hud_model.gd` already use.
##
## Sync: none under test. All four helpers are host-only logic, and clients hold
## no `Effect` instances at all (SPEC-effect-system, "Multiplayer ownership").

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const STAT_BLOCK_SCRIPT_PATH: String = "res://scripts/components/stat_block.gd"
const STATUS_STUB_SCRIPT_PATH: String = "res://tests/helpers/status_effects_stub.gd"
const HURTBOX_STUB_SCRIPT_PATH: String = "res://tests/helpers/hurtbox_stub.gd"
const EFFECT_SCRIPT_PATH: String = "res://scripts/effects/effect.gd"
const EFFECTS_DIR: String = "res://scripts/effects"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
const STATUS_NODE: NodePath = ^"StatusEffects"
const HURTBOX_NODE: NodePath = ^"Hurtbox"

## The four helpers this goal ships, in the spec's own order.
const SPEC_HELPERS: Array[String] = ["modify", "chance", "apply_status", "deal_damage"]

const SEED: int = 20261020
const SAMPLE: int = 64
const EPSILON: float = 0.0001

## A status id, a stack count and a depth, so an assertion failure reads as a
## wrong value rather than a wrong constant.
const TEST_STATUS: int = 1
const TEST_STACKS: int = 3
const TEST_TRIGGER_DEPTH: int = 2

var _player: Player
var _block: StatBlock
var _status: StatusEffectsStub
var _hurtbox: HurtboxStub
var _source: ContentData
var _effects: Array[Effect] = []


func before_each() -> void:
	_player = _make_player(true)
	_block = _player.get_node(STAT_BLOCK_NODE) as StatBlock
	_status = _player.get_node(STATUS_NODE) as StatusEffectsStub
	_hurtbox = _player.get_node(HURTBOX_NODE) as HurtboxStub
	_source = ContentData.new()
	_source.id = &"test_relic"
	_source.display_name = "Test Relic"


func after_each() -> void:
	for effect: Effect in _effects:
		effect.detach()
	_effects.clear()
	# Autoload state leaks across test files (LESSONS): one case starts a run to
	# read its seed, and the solo session it needs must not outlive it.
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.disconnect_all()


## The real player scene with the three component doubles hung on its bare
## component nodes, unless `with_components` is false (the guarded-no-op cases).
func _make_player(with_components: bool) -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	if with_components:
		var block_node: Node = player.get_node(STAT_BLOCK_NODE)
		block_node.set_script(load(STAT_BLOCK_SCRIPT_PATH) as Script)
		(block_node as StatBlock).base = {
			StatBlock.Stat.ATTACK: 100.0,
			StatBlock.Stat.LUCK: 0.0,
		}
		player.get_node(STATUS_NODE).set_script(load(STATUS_STUB_SCRIPT_PATH) as Script)
		player.get_node(HURTBOX_NODE).set_script(load(HURTBOX_STUB_SCRIPT_PATH) as Script)
	else:
		# The scene now ships the real StatBlock script; a bare double must
		# have a plain Node there, or the no-component path is never reached.
		player.get_node(STAT_BLOCK_NODE).set_script(null)
	add_child_autofree(player)
	return player


func _attach(source: ContentData = null) -> Effect:
	var content: ContentData = _source if source == null else source
	var effect := Effect.new()
	_player.add_child(effect)
	effect.attach(_player, content, 1)
	_effects.append(effect)
	return effect


## An effect with a generator of its own at a fixed seed, so every draw in this
## file is reproducible.
func _attach_seeded(seed_value: int = SEED) -> Effect:
	var effect: Effect = _attach()
	effect.rng = RandomNumberGenerator.new()
	effect.rng.seed = seed_value
	return effect


func _script_method_names(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for method: Dictionary in script.get_script_method_list():
		names.append(String(method["name"]))
	return names


## True when the line declaring `func <name>(` is preceded by a `##` doc line,
## so an undocumented helper fails rather than passing on its name alone.
func _documented(source: String, method_name: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for i: int in range(1, lines.size()):
		if lines[i].begins_with("func %s(" % method_name):
			return lines[i - 1].strip_edges().begins_with("##")
	return false


## Every `.gd` under `scripts/effects/`, recursively — the files the "no base
## stat is ever written" rule covers.
func _effect_script_paths() -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(EFFECTS_DIR)
	if dir == null:
		return found
	_collect_scripts(dir, EFFECTS_DIR, found)
	return found


func _collect_scripts(dir: DirAccess, path: String, found: Array[String]) -> void:
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = "%s/%s" % [path, entry]
		if dir.current_is_dir():
			if not entry.begins_with("."):
				var sub: DirAccess = DirAccess.open(full)
				if sub != null:
					_collect_scripts(sub, full, found)
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func test_the_four_helpers_are_declared_and_documented() -> void:
	var script: GDScript = load(EFFECT_SCRIPT_PATH) as GDScript
	var source: String = FileAccess.get_file_as_string(EFFECT_SCRIPT_PATH)
	var names: Array[String] = _script_method_names(script)
	for helper: String in SPEC_HELPERS:
		assert_true(names.has(helper), "Effect declares %s()" % helper)
		assert_true(_documented(source, helper), "%s() carries a doc comment" % helper)


# --- modify ---------------------------------------------------------------

func test_modify_uses_the_effect_id_as_the_modifier_source() -> void:
	var effect: Effect = _attach()
	effect.modify(StatBlock.Stat.ATTACK, 5.0, 0.1)
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 115.5, EPSILON, "flat then percent")
	_block.remove_source(&"test_relic")
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 100.0, EPSILON, "the modifier carried the effect's id")


func test_modify_records_the_handle_so_detach_removes_it() -> void:
	var effect: Effect = _attach()
	effect.modify(StatBlock.Stat.ATTACK, 5.0, 0.1)
	effect.modify(StatBlock.Stat.LUCK, 3.0, 0.0)
	assert_eq(effect._handles.size(), 2, "both handles are tracked")
	assert_almost_eq(_block.get_value(StatBlock.Stat.LUCK), 3.0, EPSILON)
	effect.detach()
	assert_true(effect._handles.is_empty(), "no handle left tracked")
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 100.0, EPSILON, "both modifiers are gone")
	assert_almost_eq(_block.get_value(StatBlock.Stat.LUCK), 0.0, EPSILON)


func test_modify_never_writes_a_base_stat() -> void:
	var effect: Effect = _attach()
	var before: Dictionary = _block.base.duplicate()
	effect.modify(StatBlock.Stat.ATTACK, 50.0, 1.0)
	assert_eq(_block.base, before, "the base Dictionary is untouched by a modifier")
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK), 300.0, EPSILON, "the change is visible through get_value()")


## The rule is not "modify happens to be careful": nothing under
## `scripts/effects/` may write a base stat at all. The negative control for
## this test is the literal it searches for — dropping the same line into any
## effect script fails it.
func test_no_effect_script_writes_a_base_stat() -> void:
	var paths: Array[String] = _effect_script_paths()
	assert_gt(paths.size(), 0, "the effect scripts were found to search")
	var offenders: Array[String] = []
	for path: String in paths:
		if FileAccess.get_file_as_string(path).contains(".base["):
			offenders.append(path)
	assert_eq(offenders.size(), 0, "no effect script writes a base stat, found: %s" % [offenders])


func test_modify_without_a_stat_block_is_a_guarded_no_op() -> void:
	var bare: Player = _make_player(false)
	var effect := Effect.new()
	bare.add_child(effect)
	effect.attach(bare, _source, 1)
	_effects.append(effect)
	assert_null(effect.stat_block)
	effect.modify(StatBlock.Stat.ATTACK, 5.0, 0.0)
	assert_true(effect._handles.is_empty(), "no handle recorded for a modifier that could not land")


# --- chance ---------------------------------------------------------------

func test_chance_returns_false_at_or_below_zero_and_true_at_or_above_one() -> void:
	var effect: Effect = _attach_seeded()
	assert_false(effect.chance(0.0), "p = 0 never fires")
	assert_false(effect.chance(-1.0), "a negative p never fires")
	assert_true(effect.chance(1.0), "p = 1 always fires")
	assert_true(effect.chance(2.0), "a p above 1 always fires")


## "Without drawing" is asserted by comparing the generator's stream across the
## calls: the value drawn after the two extremes must be the very next value of
## the sequence, so neither extreme consumed one.
func test_chance_draws_nothing_at_the_extremes() -> void:
	var effect: Effect = _attach_seeded()
	var control := RandomNumberGenerator.new()
	control.seed = SEED
	var expected_next: float = control.randf()
	var expected_after: float = control.randf()
	effect.chance(0.0)
	effect.chance(1.0)
	assert_almost_eq(effect.rng.randf(), expected_next, EPSILON, "the first real draw is still the first draw")
	assert_almost_eq(effect.rng.randf(), expected_after, EPSILON, "and the stream is where it would have been")


func test_chance_is_reproducible_from_a_seeded_generator() -> void:
	var effect: Effect = _attach_seeded()
	var first: Array[bool] = []
	for i: int in SAMPLE:
		first.append(effect.chance(0.5))
	effect.rng.seed = SEED
	var second: Array[bool] = []
	for i: int in SAMPLE:
		second.append(effect.chance(0.5))
	assert_eq(first, second, "the same seed replays the same sequence")
	var hits: int = 0
	for result: bool in first:
		if result:
			hits += 1
	assert_gt(hits, 0, "an even roll over %d draws fires at least once" % SAMPLE)
	assert_lt(hits, SAMPLE, "and does not fire every time")


func test_chance_draws_from_the_effects_own_generator() -> void:
	var effect: Effect = _attach_seeded()
	var control := RandomNumberGenerator.new()
	control.seed = SEED
	var expected: Array[bool] = []
	for i: int in SAMPLE:
		expected.append(control.randf() < 0.5)
	var actual: Array[bool] = []
	for i: int in SAMPLE:
		actual.append(effect.chance(0.5))
	assert_eq(actual, expected, "every result is this generator's next draw compared with p")


func test_chance_creates_a_seeded_generator_when_none_was_given() -> void:
	var effect: Effect = _attach()
	assert_null(effect.rng, "no generator until something needs one")
	effect.chance(0.5)
	assert_not_null(effect.rng, "chance() makes one rather than rolling globally")
	var other: Effect = _attach()
	other.chance(0.5)
	assert_eq(other.rng.seed, effect.rng.seed, "both effects resolve the same fallback seed, not clock entropy")
	assert_eq(other.rng.seed, Effect.DEFAULT_RNG_SEED, "and it is the named fallback")


func test_chance_uses_the_run_seed_when_a_run_is_live() -> void:
	NetworkManager.start_solo()
	GameState.forced_seed = 4242
	GameState.start_run(0, 1, [])
	assert_not_null(GameState.run, "a run is live")
	var effect: Effect = _attach()
	assert_not_null(effect._resolve_rng(), "the generator resolves")
	assert_eq(effect.rng.seed, 4242, "the run's seed, not clock entropy")


# --- apply_status ---------------------------------------------------------

func test_apply_status_reaches_the_status_component() -> void:
	var effect: Effect = _attach()
	effect.apply_status(_player, TEST_STATUS, TEST_STACKS)
	assert_eq(_status.applications.size(), 1, "the component was asked once")
	assert_eq(int(_status.applications[0]["status"]), TEST_STATUS)
	assert_eq(int(_status.applications[0]["stacks"]), TEST_STACKS)
	assert_eq(_status.applications[0]["source"], effect, "the source names the effect that applied it")


func test_apply_status_defaults_to_a_single_stack() -> void:
	var effect: Effect = _attach()
	effect.apply_status(_player, TEST_STATUS)
	assert_eq(_status.stacks(TEST_STATUS), 1)


func test_apply_status_reaches_a_target_other_than_its_own_player() -> void:
	var enemy: Player = _make_player(true)
	var enemy_status: StatusEffectsStub = enemy.get_node(STATUS_NODE) as StatusEffectsStub
	var effect: Effect = _attach()
	effect.apply_status(enemy, TEST_STATUS, 2)
	assert_eq(_status.applications.size(), 0, "the effect's own player is untouched")
	assert_eq(enemy_status.stacks(TEST_STATUS), 2, "the named target got it")


func test_apply_status_without_a_component_is_a_guarded_no_op() -> void:
	var bare: Player = _make_player(false)
	var effect: Effect = _attach()
	assert_null(bare.get_node(STATUS_NODE).get_script(), "the bare target carries no component")
	effect.apply_status(bare, TEST_STATUS, 1)
	assert_eq(_status.applications.size(), 0, "nothing was applied anywhere")
	effect.apply_status(null, TEST_STATUS, 1)
	assert_eq(_status.applications.size(), 0, "a null target is refused too")


# --- deal_damage ----------------------------------------------------------

func test_deal_damage_increments_the_proc_depth_and_tags_the_hit() -> void:
	var effect: Effect = _attach()
	var hit := HitInfo.new()
	hit.base_damage = 10.0
	effect.deal_damage(_player, hit)
	assert_eq(hit.proc_depth, 1, "a fresh hit from an effect is one link deep")
	assert_true(hit.tags.has(&"proc"), "the hit is tagged as a proc: %s" % [hit.tags])


func test_deal_damage_produces_a_result_one_link_deeper_than_its_trigger() -> void:
	var effect: Effect = _attach()
	effect.trigger_depth = TEST_TRIGGER_DEPTH
	var hit := HitInfo.new()
	effect.deal_damage(_player, hit)
	assert_eq(hit.proc_depth, TEST_TRIGGER_DEPTH + 1, "proc_depth = trigger.proc_depth + 1")


func test_deal_damage_delivers_the_hit_to_the_targets_damage_sink() -> void:
	var effect: Effect = _attach()
	var hit := HitInfo.new()
	hit.base_damage = 12.0
	effect.deal_damage(_player, hit)
	assert_eq(_hurtbox.received.size(), 1, "the hurtbox was asked to receive it")
	assert_eq(_hurtbox.received[0], hit, "and it is the stamped hit, not a copy")


func test_deal_damage_does_not_tag_proc_twice() -> void:
	var effect: Effect = _attach()
	var hit := HitInfo.new()
	hit.tags.append(&"proc")
	effect.deal_damage(_player, hit)
	assert_eq(hit.tags.count(&"proc"), 1, "an already-tagged hit keeps one tag")


func test_deal_damage_without_a_damage_sink_is_a_guarded_no_op() -> void:
	var bare: Player = _make_player(false)
	var effect: Effect = _attach()
	var hit := HitInfo.new()
	effect.deal_damage(bare, hit)
	assert_eq(hit.proc_depth, 1, "the hit is still stamped")
	effect.deal_damage(null, hit)
	assert_eq(hit.proc_depth, 1, "a null target changes nothing")


func test_deal_damage_keeps_other_tags_the_caller_set() -> void:
	var effect: Effect = _attach()
	var hit := HitInfo.new()
	hit.tags.append(&"fire")
	effect.deal_damage(_player, hit)
	assert_eq(hit.tags, [&"fire", &"proc"] as Array[StringName], "the caller's tags survive")
