extends GutTest
## The Mimic Crown duplication rule — effect-system, W4-B3 (goal G19b).
##
## SPEC-effect-system, "Proc chain limits", rule 4: "Mimic Crown copies the last
## picked relic's effect; the copy is a second `Effect` instance with its own id
## suffix so rule 2 still applies." That sentence is the whole deliverable of
## this file, and it is asserted against the spec text itself rather than
## against a transcription, so a reworded rule fails here instead of becoming a
## rule nobody implements.
##
## Four properties, each its own case:
##
## 1. the copy is a **second `Effect`** attached under a **suffixed id**
##    (`ember_boots` -> `ember_boots__crown`), produced by attaching a
##    `mimic_crown` source, not by a second attach path;
## 2. **both effects react to the same event** — the copy is not suppressed by
##    the original and does not replace it;
## 3. the copy's **self-tag check uses the suffixed id** (rule 2, goal G17), so
##    a hit tagged `ember_boots` suppresses the original and still reaches the
##    copy, and a hit tagged `ember_boots__crown` does the reverse. This is the
##    clause "so rule 2 still applies" means;
## 4. removing Mimic Crown **detaches only the copy**: the copied relic stays
##    attached and keeps reacting.
##
## The chain is driven through `ProcChainProbe` (`tests/helpers/`) and the
## trigger-test harness (`tests/helpers/effect_harness.gd`, goal G19a), so the
## effects under test listen through the real `Effect.listen()` wrapper and are
## attached through the real `EffectHost.add()`. The crown's own behaviour is
## `MimicCrownStub`, the week-8 relic's double.
##
## Sync: none under test. The duplication rule is host-only logic — an effect
## never runs on a client — so there is no client half to drive in one process.
## Nothing here reads input, writes a replicated field or branches on
## `multiplayer`.

const HOST_PATH: String = "res://scripts/effects/effect_host.gd"
const SPEC_PATH: String = "res://specs/SPEC-effect-system.md"
const PROBE_SCRIPT_PATH: String = "res://tests/helpers/proc_chain_probe.gd"
const CROWN_SCRIPT_PATH: String = "res://tests/helpers/mimic_crown_stub.gd"

## SPEC-effect-system, "Proc chain limits", rule 4, verbatim. Quoted here so a
## spec edit that changes the rule is a failure in this file rather than a rule
## that quietly stops being implemented. (Copied by hand; if it drifts, this
## assertion is what notices.)
const SPEC_RULE_4: String = "4. Mimic Crown copies the last picked relic's effect; the copy is a second `Effect` instance with its own id suffix so rule 2 still applies."

## The exact form of the suffix. Named here as well as on `EffectHost` so the
## id a copy is keyed under is pinned by the test and not only by the class
## under test: a copy whose id silently changed shape would make every store
## that looks a copy up by id (the HUD, the debug overlay, a save) miss it.
const SUFFIX: StringName = &"__crown"
const RELIC_ID: StringName = &"ember_boots"
const COPY_ID: StringName = &"ember_boots__crown"
const CROWN_ID: StringName = &"mimic_crown"
const RELIC_NAME: String = "Ember Boots"
const CROWN_NAME: String = "Mimic Crown"
## 1 to 2 tags from the `Tags` vocabulary, as every content item carries.
const RELIC_TAGS: Array[StringName] = [&"fire", &"dodge"]
const CROWN_TAGS: Array[StringName] = [&"transformation"]
const BASE_DAMAGE: float = 9.0

var _harness: EffectHarness
var _player: Player
var _host: EffectHost
var _relic: ContentData
var _crown: ContentData
## Every probe in a case writes into this one log, so a reaction can be read
## back per effect id rather than as a total.
var _log: ProcChainLog


func before_each() -> void:
	NetworkManager.start_solo()
	_log = ProcChainLog.new()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_host = EffectHostPlayer.install(_player)
	_host.spawner = _harness.world
	_relic = _harness.source(RELIC_ID, RELIC_NAME, load(PROBE_SCRIPT_PATH) as GDScript, RELIC_TAGS)
	_crown = _harness.source(CROWN_ID, CROWN_NAME, load(CROWN_SCRIPT_PATH) as GDScript, CROWN_TAGS)


func after_each() -> void:
	# Autoload state leaks across test files (LESSONS): the solo session this
	# file opens must not outlive it.
	EffectHarness.reset_globals()


# --- the rule the spec states --------------------------------------------

## The failing path this file would otherwise only assume: if the spec sentence
## is edited, this is what notices.
func test_the_spec_still_states_rule_four_verbatim() -> void:
	var text: String = FileAccess.get_file_as_string(SPEC_PATH)
	assert_true(text.contains(SPEC_RULE_4), "SPEC-effect-system, \"Proc chain limits\", rule 4 is unchanged")


# --- 1. a second Effect under a suffixed id ------------------------------

func test_the_suffix_is_named_and_is_what_makes_the_copys_id() -> void:
	assert_eq(typeof(EffectHost.MIMIC_CROWN_SUFFIX), TYPE_STRING_NAME, "the suffix is a StringName constant")
	assert_eq(EffectHost.MIMIC_CROWN_SUFFIX, SUFFIX, "and its exact form is pinned here too")
	assert_eq(EffectHost.suffixed_id(RELIC_ID, SUFFIX), COPY_ID, "a copy's id is the relic's id plus the suffix")
	assert_eq(EffectHost.suffixed_id(RELIC_ID, &""), RELIC_ID, "no suffix leaves an id alone")
	assert_ne(COPY_ID, RELIC_ID, "so the copy and the original are keyed apart")


func test_attaching_a_mimic_crown_copies_the_last_picked_relics_effect() -> void:
	var original: ProcChainProbe = _attach_relic()
	var crown: MimicCrownStub = _attach_crown()
	assert_not_null(crown, "the crown attached")
	var copy: Effect = _host.get_effect(COPY_ID)
	assert_not_null(copy, "attaching the crown produced a second Effect under the suffixed id")
	assert_ne(copy, original, "and it is a second instance, not the original")
	assert_eq(copy.source, _relic, "holding the same content as the relic it copies")
	assert_eq(copy.source_id(), COPY_ID, "but reporting the suffixed id")
	assert_eq(copy.name, COPY_ID, "and named by it, so the two nodes cannot collide under the host")
	assert_eq(_host.effect_count(), 3, "relic + crown + copy")
	assert_true(_host.has_mimic_copy_of(RELIC_ID, CROWN_ID), "and the host records the crown as the copy's owner")
	assert_false(_host.has_mimic_copy_of(RELIC_ID, RELIC_ID), "so no other effect is read as its owner")
	assert_false(_host.has_mimic_copy_of(CROWN_ID, CROWN_ID), "and the crown is not recorded as a copy of itself")


## The duplication path is `EffectHost.add()` with the constant named — not a
## second attach mechanism that could drift from the lifecycle, the seeding or
## the ownership `add()` establishes.
func test_the_copy_is_attached_by_the_one_attach_path() -> void:
	var original: ProcChainProbe = _attach_relic()
	_attach_crown()
	var copy: Effect = _host.get_effect(COPY_ID)
	assert_eq(copy.get_parent(), _host, "the copy is parented by the host, as add() parents")
	assert_eq(copy.host, _host, "and carries the host, as add() hands over")
	assert_not_null(copy.rng, "and the host's generator, as add() injects")
	assert_true(copy.is_attached(), "and went through the attach lifecycle")
	# The two effects share their player's generator on purpose: one seed replays
	# one run's procs for the whole player.
	assert_same(copy.rng, original.rng, "and both draw from the player's one stream")
	var source_text: String = FileAccess.get_file_as_string(HOST_PATH)
	assert_true(source_text.contains("MIMIC_CROWN_SUFFIX"), "the host names the suffix constant")
	assert_eq(
		_count_occurrences(source_text, "effect_script.new()"),
		1,
		"and there is exactly one place an effect script is instantiated: no second attach mechanism",
	)


# --- 2. both react to the same event -------------------------------------

func test_both_the_original_and_its_copy_react_to_the_same_event() -> void:
	var original: ProcChainProbe = _attach_relic()
	_attach_crown()
	var copy: ProcChainProbe = _configure_copy()
	_fire_hit([])
	assert_eq(original.handler_calls, 1, "the original reacted to the hit")
	assert_eq(copy.handler_calls, 1, "and so did its copy")
	assert_eq(_log.count(), 2, "two reactions, one from each effect")
	assert_eq(_log.depths_for_source(RELIC_ID, &"hit_landed"), [0] as Array[int], "the original reacts at the hit's depth")
	assert_eq(_log.depths_for_source(COPY_ID, &"hit_landed"), [0] as Array[int], "and the copy reacts at the same depth")


# --- 3. the copy's self-tag check uses the suffixed id --------------------

func test_a_hit_tagged_with_the_originals_id_suppresses_only_the_original() -> void:
	var original: ProcChainProbe = _attach_relic()
	_attach_crown()
	var copy: ProcChainProbe = _configure_copy()
	_fire_hit([RELIC_ID])
	assert_eq(original.handler_calls, 0, "rule 2 suppresses the original's own hit reaching it")
	assert_eq(copy.handler_calls, 1, "but the copy's id is not in those tags, so it still reacts")
	assert_true(_log.reacted(COPY_ID), "and the copy is who the reaction is attributed to")
	assert_false(_log.reacted(RELIC_ID), "the suppressed original recorded nothing")


func test_a_hit_tagged_with_the_copys_id_suppresses_only_the_copy() -> void:
	var original: ProcChainProbe = _attach_relic()
	_attach_crown()
	var copy: ProcChainProbe = _configure_copy()
	_fire_hit([COPY_ID])
	assert_eq(copy.handler_calls, 0, "rule 2 suppresses the copy's own hit reaching it")
	assert_eq(original.handler_calls, 1, "and the original — whose id is not the suffixed one — still reacts")
	assert_true(_log.reacted(RELIC_ID), "attributed to the original")
	assert_false(_log.reacted(COPY_ID), "and not to the copy")


## The two effects suppress each other's hits *independently* rather than
## sharing one id: a single untagged hit reaches both, and only the tag of the
## effect it belongs to stops that one.
func test_the_two_effects_do_not_suppress_each_other() -> void:
	var original: ProcChainProbe = _attach_relic()
	_attach_crown()
	var copy: ProcChainProbe = _configure_copy()
	_fire_hit([])
	assert_eq(original.handler_calls, 1, "the untagged hit reached the original")
	assert_eq(copy.handler_calls, 1, "and the copy")
	_fire_hit([RELIC_ID, COPY_ID])
	assert_eq(original.handler_calls, 1, "a hit tagged with both ids reaches neither")
	assert_eq(copy.handler_calls, 1, "so neither counter moved")


# --- 4. removing the crown detaches only the copy -------------------------

func test_removing_mimic_crown_detaches_only_the_copy() -> void:
	var original: ProcChainProbe = _attach_relic()
	_attach_crown()
	_configure_copy()
	assert_true(_host.has_mimic_copy_of(RELIC_ID, CROWN_ID), "the crown owns the copy while it is attached")
	assert_true(_host.remove(_crown), "the crown is removed")
	assert_false(_host.has_effect(COPY_ID), "its copy goes with it")
	assert_false(_host.has_effect(CROWN_ID), "and so does the crown itself")
	assert_false(_host.has_mimic_copy_of(RELIC_ID, CROWN_ID), "and the copy's ownership record goes with it, so the bookkeeping cannot leak an entry")
	assert_true(_host.has_effect(RELIC_ID), "the copied relic stays attached")
	assert_true(original.is_attached(), "and is still live, not merely still keyed")
	assert_eq(_host.effect_count(), 1, "one effect left: the relic the player still holds")
	_fire_hit([])
	assert_eq(original.handler_calls, 1, "and it still reacts")
	assert_false(_log.reacted(COPY_ID), "while the detached copy no longer does")


## The other direction: a relic the player no longer holds cannot leave its
## copy behind. The copy is of a gone effect, so it goes with it.
func test_removing_the_copied_relic_takes_its_copy_with_it() -> void:
	var original: ProcChainProbe = _attach_relic()
	_attach_crown()
	_configure_copy()
	assert_true(_host.remove(_relic), "the relic is removed")
	assert_false(_host.has_effect(RELIC_ID), "the relic is gone")
	assert_false(_host.has_effect(COPY_ID), "and a copy of a relic the player no longer holds goes too")
	assert_true(_host.has_effect(CROWN_ID), "while the crown itself stays attached")


func test_a_crown_with_nothing_picked_yet_copies_nothing() -> void:
	var crown: MimicCrownStub = _attach_crown()
	assert_not_null(crown, "the crown still attaches")
	assert_eq(_host.effect_count(), 1, "but nothing is copied")
	assert_false(_host.has_effect(COPY_ID), "there is no copy")


# --- refusals and counts -------------------------------------------------

func test_add_mimic_copy_refuses_what_it_cannot_own() -> void:
	assert_null(_host.add_mimic_copy(null, CROWN_ID), "no source to copy")
	assert_null(_host.add_mimic_copy(_relic, &""), "no owning effect to clean the copy up with")
	assert_null(_host.add_mimic_copy(_relic, CROWN_ID), "the relic is not attached, so there is nothing to copy")
	_attach_relic()
	assert_not_null(_host.add_mimic_copy(_relic, CROWN_ID), "once it is attached, the copy attaches")
	assert_null(_host.add_mimic_copy(_relic, CROWN_ID), "and a second copy of one relic is refused")


## The counting policy, pinned rather than implied: a copy is a second attached
## `Effect`, so `list_tags()` counts the relic's tags twice while it is held.
## Judgement call, recorded in HANDOFF: `list_tags()` answers "what does this
## build carry", and a copied effect is carried. Excluding copies would be a
## one-line change here if the week-8 balance pass prefers the other reading.
func test_list_tags_counts_the_copy_once_alongside_the_relic() -> void:
	_attach_relic()
	_attach_crown()
	var counts: Dictionary = _host.list_tags()
	assert_eq(int(counts.get(&"fire", 0)), 2, "the relic's fire tag counts for the relic and again for its copy")
	assert_eq(int(counts.get(&"dodge", 0)), 2, "so does its dodge tag")
	assert_eq(int(counts.get(&"transformation", 0)), 1, "and the crown's own tag counts once")


# --- fixtures -------------------------------------------------------------

## The probe standing in for the picked relic, attached through the real
## `EffectHost.add()` and wired to this case's log.
func _attach_relic() -> ProcChainProbe:
	var probe: ProcChainProbe = _harness.attach(_relic) as ProcChainProbe
	assert_not_null(probe, "%s attached through the host" % RELIC_ID)
	return _configure(probe)


## The crown stub, attached through the same host. Its `_on_attach()` is where
## the duplication happens.
func _attach_crown() -> MimicCrownStub:
	var crown: MimicCrownStub = _harness.attach(_crown) as MimicCrownStub
	assert_not_null(crown, "%s attached through the host" % CROWN_ID)
	return crown


## The copy the crown made, wired to this case's log. A copy is a second
## instance of the relic's own effect script, so it needs the same case
## configuration the original got.
func _configure_copy() -> ProcChainProbe:
	return _configure(_host.get_effect(COPY_ID) as ProcChainProbe)


## Observe-only and logged: the probe records every reaction the dispatch
## wrapper let through and produces nothing further, so these cases assert the
## rule and not a chain's length.
func _configure(probe: ProcChainProbe) -> ProcChainProbe:
	assert_not_null(probe, "the effect under test exists")
	if probe == null:
		return null
	probe.log = _log
	probe.link_limit = 0
	return probe


## One landed hit on the bus, tagged as the case asks, through the harness's
## arity-checked `fire()` so a signal that changed shape is a refusal and not an
## error inside an effect.
func _fire_hit(tags: Array[StringName]) -> void:
	var hit := HitInfo.new()
	hit.base_damage = BASE_DAMAGE
	hit.tags = tags
	assert_true(_harness.fire(Events.hit_landed, [hit]), "the bus announced a landed hit")


## How many times `needle` occurs in `haystack`, for the "one instantiation
## path" assertion above.
func _count_occurrences(haystack: String, needle: String) -> int:
	if needle.is_empty():
		return 0
	var total: int = 0
	var from: int = 0
	while true:
		var at: int = haystack.find(needle, from)
		if at < 0:
			break
		total += 1
		from = at + needle.length()
	return total
