extends GutTest
## Template case and self-test for the trigger-test harness — effect-system,
## W4-B3 (goal G19a).
##
## SPEC-effect-system, "Interfaces provided", names `tests/helpers/effect_harness.gd`
## as the shared instrument every content module uses: "creates a headless
## player with `EffectHost`, attaches an effect, fires any `Events` signal with
## fake arguments, asserts spawns, stat changes, statuses, and damage via a
## `SpyWorld`." Twenty relics in W4-B6, twenty more in week 8, plus mutations,
## passives, Ascensions and skill nodes all write their cases against it, so
## this file is two things at once:
##
## 1. a **template** — every case below is shaped exactly like the case a
##    content author copies for a new relic (`before_each` builds the harness,
##    the player and the source; the case attaches, fires and asserts), and the
##    recipe is repeated verbatim in the harness's own `##` doc comment;
## 2. a **self-test** — the harness's own assertions are exercised on a real
##    effect (`HarnessSampleEffect`, a double shaped like a dodge relic) *and*
##    on a deliberately broken one, so "the assertion that would catch a broken
##    relic" is pinned rather than assumed (BRIEF C13: an assertion whose
##    failing path was never observed is an assumption).
##
## The harness itself is `tests/helpers/effect_harness.gd`; `SpyWorld`
## (`tests/helpers/spy_world.gd`) is the recorder behind it. Nothing here runs
## in a game: the harness is test-only, and the effects it drives are host-only
## (SPEC-effect-system, "Multiplayer ownership").
##
## Sync: none under test. The harness is one process; host-only behaviour is
## asserted through the same `can_spawn()` seam the other effect tests use, and
## the real co-op path is the two-instance smoke.

const SAMPLE_EFFECT_PATH: String = "res://tests/helpers/harness_sample_effect.gd"
const HARNESS_PATH: String = "res://tests/helpers/effect_harness.gd"

const SOURCE_ID: StringName = &"ember_boots"
const SOURCE_NAME: String = "Ember Boots"
const SOURCE_TAGS: Array[StringName] = [&"fire", &"dodge"]
const TRAIL_AT: Vector2 = Vector2(96.0, 48.0)
const SPEED_BONUS: float = 0.25
const MOVE_SPEED_BASE: float = 100.0
const STATUS_ID: int = 1
const STATUS_STACKS: int = 3
const HIT_DAMAGE: float = 18.0
const EPSILON: float = 0.0001

var _harness: EffectHarness
var _player: Player
var _target: Node2D
var _source: ContentData
## Hits `SpyWorld` announced on the bus, for the chain-case affordance.
var _announced: Array[HitData] = []


func before_each() -> void:
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_target = _harness.make_target(TRAIL_AT)
	_source = _harness.source(SOURCE_ID, SOURCE_NAME, load(SAMPLE_EFFECT_PATH) as GDScript, SOURCE_TAGS)


func after_each() -> void:
	# Autoload state leaks across test files (LESSONS): the solo session this
	# file opens must not outlive it. `reset_globals()` is the harness's own
	# copy-paste line for exactly this.
	EffectHarness.reset_globals()


## The effect under test, configured like a content author configures a relic's
## data before firing the trigger. `attach()` goes through the real
## `EffectHost.add()`, so the effect is parented, hosted and seeded exactly as
## it is in the game.
func _attach_sample() -> HarnessSampleEffect:
	var effect: HarnessSampleEffect = _harness.attach(_source) as HarnessSampleEffect
	assert_not_null(effect, "the sample effect attached through the host")
	effect.trail_scene = _harness.marker_scene()
	effect.trail_at = TRAIL_AT
	effect.speed_bonus = SPEED_BONUS
	effect.status_id = STATUS_ID
	effect.status_stacks = STATUS_STACKS
	effect.status_target = _target
	effect.damage_target = _target
	effect.hit_damage = HIT_DAMAGE
	return effect


# --- the harness's own shape ---------------------------------------------

## The recipe the harness must document, so a content author has something to
## copy. Checked here rather than trusted: the doc comment is the deliverable.
func test_the_harness_documents_the_copy_paste_recipe() -> void:
	var source: String = FileAccess.get_file_as_string(HARNESS_PATH)
	assert_true(source.contains(EffectHarness.RECIPE_HEADING), "the harness carries the recipe heading")
	assert_true(source.contains("EffectHarness.new(self)"), "and the construction line")
	assert_true(source.contains("_harness.make_player()"), "the player line")
	assert_true(source.contains("_harness.attach("), "the attach line")
	assert_true(source.contains("_harness.fire("), "the fire line")
	assert_true(source.contains("_harness.assert_"), "and the assertion lines")


func test_the_harness_builds_a_player_with_an_effect_host_and_components() -> void:
	var host: Node = _player.get_node_or_null(NodePath(EffectHost.NODE_NAME))
	assert_not_null(host, "the player double carries an EffectHost")
	assert_true(host is EffectHost, "and it is the real EffectHost, not a stub")
	assert_not_null(_player.get_node_or_null(EffectHarness.STAT_BLOCK_NODE), "with a StatBlock component")
	assert_not_null(_player.get_node_or_null(EffectHarness.STATUS_NODE), "and a StatusEffects component")
	assert_not_null(_player.get_node_or_null(EffectHarness.HURTBOX_NODE), "and a Hurtbox")


func test_the_harness_makes_a_target_that_records_damage_and_statuses() -> void:
	assert_not_null(_target.get_node_or_null(EffectHarness.HURTBOX_NODE), "the target has a hurtbox")
	assert_not_null(_target.get_node_or_null(EffectHarness.STATUS_NODE), "and a StatusEffects component")
	assert_eq(_harness.damage_count(_target), 0, "and starts with no damage recorded")
	assert_eq(_harness.status_stacks(_target, STATUS_ID), 0, "and no statuses")


# --- the template: one case that walks every affordance -------------------

## The case a content author copies. It attaches a source, fires one `Events`
## signal with fake arguments, then asserts the four things the spec lists —
## a spawn, a stat change, a status and damage — using both the pure
## `check_*` predicates and the GUT-reporting `assert_*` wrappers.
func test_the_template_walks_every_harness_affordance() -> void:
	var effect: HarnessSampleEffect = _attach_sample()
	assert_true(_harness.check_attached(SOURCE_ID), "the source is attached and lookup-able by id")
	assert_eq(_harness.attached_id(_player), SOURCE_ID, "and it is the player's one effect")

	# Fire the trigger the relic listens to, with fake arguments.
	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "the harness fired the signal")

	# 1. spawns
	_harness.assert_spawned(1, "Ember Boots leaves one trail behind the dodge")
	assert_eq(_harness.spawn_count(SOURCE_ID), 1, "and the spawn is attributed to the relic")
	assert_true(_harness.check_spawned(1), "the pure predicate agrees")

	# 2. stat changes
	_harness.assert_stat(_player, StatBlock.Stat.MOVE_SPEED, MOVE_SPEED_BASE * (1.0 + SPEED_BONUS), "the dodge buff landed")
	assert_true(_harness.check_stat(_player, StatBlock.Stat.MOVE_SPEED, MOVE_SPEED_BASE * (1.0 + SPEED_BONUS)))

	# 3. statuses
	_harness.assert_status(_target, STATUS_ID, STATUS_STACKS, "the target was set alight")
	assert_true(_harness.check_status(_target, STATUS_ID, STATUS_STACKS))

	# 4. damage
	_harness.assert_damage(_target, 1, "the trail hit the target once")
	assert_almost_eq(_harness.damage_total(_target), HIT_DAMAGE, EPSILON, "for the hit's damage")
	assert_true(_harness.check_damage(_target, 1))

	# detaching the source takes its stat modifier with it — the lifecycle a
	# content case is expected to check.
	assert_true(_harness.detach(_source), "the source detaches")
	assert_almost_eq(_harness.stat_of(_player, StatBlock.Stat.MOVE_SPEED), MOVE_SPEED_BASE, EPSILON, "and its modifier is gone")
	assert_false(_harness.check_attached(SOURCE_ID), "and it is no longer attached")
	assert_not_null(effect, "the effect was the one the harness returned")


## The signal guard: firing something that is not on the bus, or with the wrong
## number of arguments, is refused with a warning and returns false rather than
## exploding inside a content author's case.
func test_the_harness_refuses_an_unknown_signal_and_a_wrong_arity() -> void:
	assert_false(_harness.fire(Signal(Events, &"not_a_signal_on_the_bus"), []), "an unknown signal is refused")
	assert_false(_harness.fire(Events.player_dodged, [_player]), "a one-argument dodge is refused")
	assert_false(_harness.fire(Events.player_dodged, [_player, false, 3]), "a three-argument dodge is refused")
	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "the correct arity fires")


## `SpyWorld` can announce a landed hit on the bus the way the real hurtbox
## does, which is what a chain case needs. Off by default so a content case
## asserting a relic's damage is not surprised by its own hit echoing back.
func test_the_harness_can_announce_a_landed_hit_for_a_chain_case() -> void:
	_harness.world.announce_hits = true
	Events.hit_landed.connect(_on_hit_landed)
	var effect: HarnessSampleEffect = _attach_sample()
	effect.trail_scene = null
	effect.speed_bonus = 0.0
	effect.status_target = null
	_harness.fire(Events.player_dodged, [_player, false])
	Events.hit_landed.disconnect(_on_hit_landed)
	assert_eq(_announced.size(), 1, "the landed hit was announced on the bus")
	assert_almost_eq(_announced[0].base_damage, HIT_DAMAGE, EPSILON, "carrying the hit the effect produced")


func _on_hit_landed(hit: HitData) -> void:
	_announced.append(hit)


# --- the self-test: the assertion that catches a broken relic -------------

## A relic wired to the wrong player is the classic broken relic: the effect
## attaches and listens, but the trigger never reaches it. The harness's own
## assertion must report that — `check_*` is false — which is exactly what makes
## a content case fail when the relic is wrong.
func test_the_harness_assertion_catches_a_relic_that_did_not_fire() -> void:
	var other: Player = _harness.make_player()
	_attach_sample()
	assert_true(_harness.fire(Events.player_dodged, [other, false]), "another player dodged")

	assert_false(_harness.check_spawned(1), "the harness reports no spawn for the wrong player's dodge")
	assert_eq(_harness.spawn_count(), 0, "nothing spawned at all")
	assert_false(_harness.check_stat(_player, StatBlock.Stat.MOVE_SPEED, MOVE_SPEED_BASE * (1.0 + SPEED_BONUS)),
		"the stat assertion would have failed on the broken relic")
	assert_false(_harness.check_status(_target, STATUS_ID, STATUS_STACKS), "and so would the status assertion")
	assert_false(_harness.check_damage(_target, 1), "and the damage assertion")

	# The same relic, fired for its own player, does fire — so the harness is
	# not passing or failing for a reason unrelated to the trigger.
	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "its own player dodges")
	assert_true(_harness.check_spawned(1), "and now the relic reacts")
