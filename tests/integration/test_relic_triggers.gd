extends GutTest
## The week-4 "On Dodge" relics — design doc 9.1 nos. 1 to 6 — relics, W4-B6
## (PLAN G5 / raw goal G32).
##
## SPEC-relics "Testing" names this file: "Harness `test_relic_triggers.gd`: one
## case per relic (88) asserting the trigger fires the documented result once".
## This file is the batch's six: one case per relic, each loading the real
## `data/relics/<id>.tres`, attaching it through the real `EffectHost` on a
## harness player, and firing `Events.player_dodged` **once**. What each case
## asserts is the sentence the design doc writes for that relic, and every case
## that can count the result asserts *exactly one* — the same dodge twice is two
## dodges, one dodge is one trail, one shock, one clone.
##
## Two of the six are answered by a provider this lane does not own, so their
## cases assert **what the effect asks the seam for** rather than a result the
## game cannot produce yet (BRIEF C6, PLAN G5's sub-task):
##
## - the three FX-with-gameplay roots (the trail, the clone, the freezing patch)
##   are art-audio's `scenes/vfx/relic_proc_<tag>.tscn` scenes — SPEC-art-audio:
##   "one emitter scene per id", "relic_proc_<tag> (one per relic tag)" — and
##   the spawner that parents them is Dev A's W4-A4 (`EffectSpawner` says so
##   itself). The cases inject a `RelicFxRootStub` scene through the effect's
##   `fx_scene` field (the injection point `test_effect_template.gd` established)
##   and assert the spawn, where it landed, and the arming call the effect makes
##   on the root it was handed;
## - Rebound Spring's wall bounce is the Dodge state's movement (Dev A, W2-A8),
##   so the case asserts the request the effect makes on the `DodgeSeam` node.
##
## Both swap-ins are one node each and are recorded as blocked in HANDOFF.md.
##
## `EffectHarness` drives the trigger for the case's own player; `EventEmitterHelper`
## emits the same signal for a *different* player, which is how the last case
## proves the player filter — a teammate's dodge must fire none of the six.
##
## The second half of the file is the "On Hit" batch — design doc 9.1 nos. 7 to
## 11, relics, W4-B6 (PLAN G6 / raw goal G33): Echo Blade, Spark Plug, Hungry
## Steel, Venom Gland, Splitting Shot. They listen to `hit_landed`, which is the
## bus's one signal that carries **no `Player` argument** — its payload is the
## hit itself — so `Effect.listen()`'s player filter has nothing to read and the
## batch's own filter is the hit's `owner_player` (the field SPEC-effect-system
## names: "hit.source / hit.owner_player / target in hit"). Every case here fires
## the hit through the harness as the relic holder, and the batch case at the end
## fires the same hit for a teammate, which must move nothing.
##
## Two more of the batch's needs are the payload's: *which* entity the hit
## landed on (`hit.target`, so "strikes twice", "the same enemy" and "splits"
## know what they act on) and the energy the hit carried (`hit.element`, what a
## split inherits). Both are the mirror of `HitInfo`'s own fields and both are
## additive — an unattributed hit (a hazard's, an older payload's) is inert
## rather than mis-attributed.
##
## Two of the five are answered by a provider this lane does not own:
##
## - Splitting Shot's real projectiles are combat-core's (Dev A), so its case
##   asserts **what the effect asks the projectile seam for** — the three
##   `ProjectileSpec`s it hands `fire_projectile()` — and the gap is recorded as
##   `blocked on Dev A (W2-A6)`;
## - Hungry Steel's "+5% more" belongs on the hit *the enemy is taking*, which is
##   computed and delivered by Dev A's `Hurtbox` before `hit_landed` is emitted.
##   The relic therefore deals the difference itself (the same total damage
##   lands) through `deal_damage` and publishes `damage_multiplier_for(enemy)` as
##   the read the damage pipeline consults when that seam lands.
##
## Owned by relics. Sync: none under test — relics are host-only content
## (SPEC-relics "Multiplayer ownership") and the harness is one process.
##

## The six ids, in design doc 9.1 order. `RelicData.WEEK_4_IDS`' first six, and
## the file names under `data/relics/` (SPEC-project: the id is the file name).
const ON_DODGE_IDS: Array[StringName] = [
	&"ember_boots",
	&"storm_sandals",
	&"mirror_step",
	&"frostwalkers",
	&"ghost_wrap",
	&"rebound_spring",
]
## The five "On Hit" ids, design doc 9.1 nos. 7 to 11 in that order —
## `RelicData.WEEK_4_IDS`' seventh to eleventh.
const ON_HIT_IDS: Array[StringName] = [
	&"echo_blade",
	&"spark_plug",
	&"hungry_steel",
	&"venom_gland",
	&"splitting_shot",
]
const RELIC_DIR: String = "res://data/relics"
const DESIGN_DOC_PATH: String = "res://SINKHOLE_SPEC.md"
const SPEC_RELICS_PATH: String = "res://specs/SPEC-relics.md"
const ART_SPEC_PATH: String = "res://specs/SPEC-art-audio.md"
## The design doc's passive-relic group heading that opens its numbered list.
const DESIGN_DOC_HEADING: String = "### 9.1 Passive relics (70 listed)"
## Where SPEC-art-audio puts the per-id emitter scenes the FX roots live in.
const FX_SCENE_DIR: String = "res://scenes/vfx"
const ON_DODGE_COUNT: int = 6
## Design doc 9.1 no. 7 is the batch's first, and the last is no. 11.
const ON_HIT_FIRST_NUMBER: int = 7
const ON_HIT_COUNT: int = 5
const TRAILING_PERIOD: String = "."
const EPSILON: float = 0.0001
## Where the harness player stands when it dodges, and where an enemy the dodge
## never reached stands. 96 px is one dodge (SPEC-player-controller: "Fixed
## distance (~96 px …)"), so `FAR_AT` is comfortably outside every radius here.
const DODGE_AT: Vector2 = Vector2(96.0, 48.0)
const FAR_AT: Vector2 = Vector2(448.0, 48.0)
## Where the harness target stands for the On Hit cases: one hit's reach from
## the player, which is what a split sprays along.
const HIT_AT: Vector2 = Vector2(64.0, 0.0)
## The base damage every hit the On Hit cases fire carries, so a relic's
## fraction of it is a round number the case can state.
const HIT_DAMAGE: float = 100.0
## The element every hit the On Hit cases fire carries, so "the split inherits
## the hit's element" is asserted against something that is not the default.
const HIT_ELEMENT: HitData.Element = HitData.Element.STORM
## The five relics do not all stack: the design doc marks no. 9 as "(stacks)"
## and gives the other four no stack rule at all. What each `.tres` must hold.
const ON_HIT_MAX_STACKS: Dictionary[StringName, int] = {
	&"echo_blade": 1,
	&"spark_plug": 1,
	&"hungry_steel": 3,
	&"venom_gland": 1,
	&"splitting_shot": 1,
}
## The energy tag design doc 9.1 gives each of the batch's two elemental relics.
## The other three are their trigger's alone.
const ON_HIT_ELEMENT_TAGS: Dictionary[StringName, StringName] = {
	&"spark_plug": Tags.STORM,
	&"venom_gland": Tags.POISON,
}

## Every description in the batch that states a number, and the effect-script
## constant that number is: SPEC-relics — "balance numbers in the description are
## the source of truth for the effect script's constants". The check below reads
## the constant out of the script and the number out of the text, so the two
## cannot drift apart silently.
const NUMBER_LINKS: Array[Dictionary] = [
	{"id": &"mirror_step", "constant": &"CLONE_FUSE_SECONDS", "text": "1s", "value": 1.0},
	{"id": &"ghost_wrap", "constant": &"INVISIBLE_SECONDS", "text": "2s", "value": 2.0},
	{"id": &"rebound_spring", "constant": &"DODGE_DISTANCE_MULTIPLIER", "text": "doubled", "value": 2.0},
]

## The same rule for the On Hit batch's stated numbers: Echo Blade's "every 4th
## hit", Spark Plug's "10% chance", Hungry Steel's "+5% more" and Splitting
## Shot's "split into 3".
const ON_HIT_NUMBER_LINKS: Array[Dictionary] = [
	{"id": &"echo_blade", "constant": &"HITS_PER_ECHO", "text": "4th", "value": 4.0},
	{"id": &"spark_plug", "constant": &"CHAIN_CHANCE", "text": "10%", "value": 0.10},
	{"id": &"hungry_steel", "constant": &"PER_HIT_STACK_BONUS", "text": "5%", "value": 0.05},
	{"id": &"splitting_shot", "constant": &"SPLIT_COUNT", "text": "3", "value": 3.0},
]

var _harness: EffectHarness
var _player: Player
var _emitter: EventEmitterHelper
## The six real `.tres` files by id. Null for one that does not exist, which is
## what every case's first assertion reports.
var _sources: Dictionary[StringName, ContentData] = {}


func before_each() -> void:
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_player.global_position = DODGE_AT
	_emitter = EventEmitterHelper.new()
	_sources = {}
	for relic_id: StringName in ON_DODGE_IDS:
		_sources[relic_id] = load(_relic_path(relic_id)) as ContentData
	for relic_id: StringName in ON_HIT_IDS:
		_sources[relic_id] = load(_relic_path(relic_id)) as ContentData


func after_each() -> void:
	# Autoload state leaks across test files (LESSONS): the solo session this
	# file opens and the emitter's doubles must not outlive it.
	_emitter.cleanup()
	EffectHarness.reset_globals()


# --- helpers ---------------------------------------------------------------

func _relic_path(relic_id: StringName) -> String:
	return "%s/%s.tres" % [RELIC_DIR, relic_id]


## The relic the case loads, or null when the file is missing.
func _source(relic_id: StringName) -> RelicData:
	return _sources.get(relic_id) as RelicData


## Attaches `relic_id` to the harness player through the real host. Returns the
## live effect as the base class; a case that needs its own relic's fields casts.
func _attach(relic_id: StringName) -> Effect:
	return _harness.attach(_sources.get(relic_id))


## A `PackedScene` holding a `RelicFxRootStub` — the double an art-audio FX root
## scene stands in for. Built in memory, so the batch's cases depend on no art
## scene (SPEC-art-audio's relic procs are W4-B12/B13 and out of week 4).
func _fx_root_scene() -> PackedScene:
	var root := RelicFxRootStub.new()
	root.name = &"RelicFxRootStub"
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the FX root double packs into a scene")
	root.free()
	return packed


## The one node spawned for `relic_id`, or null.
func _spawned(relic_id: StringName) -> Node:
	var entries: Array[Dictionary] = _harness.world.spawns_for(relic_id)
	if entries.is_empty():
		return null
	return entries[0]["node"] as Node


## An enemy double for the shock case: a `StatusEnemyStub` (in the `enemy`
## group, with a `Health` double) carrying a `StatusEffects` double, so a status
## applied to it is recorded rather than warned away.
func _enemy(at: Vector2) -> StatusEnemyStub:
	var enemy: StatusEnemyStub = StatusEnemyStub.make(_harness.root, at)
	var component := StatusEffectsStub.new()
	component.name = EffectHarness.STATUS_NAME
	enemy.add_child(component)
	return enemy


## The one-shot `Timer` an effect parented, or null.
func _timer_for(effect: Effect) -> Timer:
	for child: Node in effect.get_children():
		if child is Timer:
			return child as Timer
	return null


## An id derived from a design-doc display name, the way the data-driven test
## derives it: "Rebound Spring" -> `rebound_spring`.
func _id_from_display_name(display_name: String) -> StringName:
	return StringName(display_name.strip_edges().to_lower().replace("'", "").replace(" ", "_"))


## Design doc 9.1 nos. 1 to 6 as `{number: {name, text}}`, parsed out of the
## document at run time so the names and sentences the data files must carry
## cannot drift from the section they were copied from.
func _on_dodge_clauses() -> Dictionary:
	return _clauses_in_range(1, ON_DODGE_COUNT)


## The same read, for the On Hit batch's five numbers.
func _on_hit_clauses() -> Dictionary:
	return _clauses_in_range(ON_HIT_FIRST_NUMBER, ON_HIT_FIRST_NUMBER + ON_HIT_COUNT - 1)


## Design doc 9.1's numbered lines `first` to `last` inclusive as
## `{number: {name, text}}`, parsed out of the document at run time.
func _clauses_in_range(first: int, last: int) -> Dictionary:
	var re := RegEx.new()
	re.compile("^(\\d+)\\. \\*\\*(.+?):\\*\\* (.+)$")
	var clauses: Dictionary = {}
	var in_section: bool = false
	var file := FileAccess.open(DESIGN_DOC_PATH, FileAccess.READ)
	assert_not_null(file, "the design doc opens")
	if file == null:
		return clauses
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	for raw: String in lines:
		var line: String = raw.strip_edges()
		if line.begins_with("### "):
			in_section = line == DESIGN_DOC_HEADING
			continue
		if not in_section:
			continue
		var m: RegExMatch = re.search(line)
		if m == null:
			continue
		var number: int = int(m.get_string(1))
		if number >= first and number <= last:
			clauses[number] = {"name": m.get_string(2), "text": m.get_string(3)}
	return clauses


## One hit landed on `target` by `owner`, carrying the batch's base damage and
## element — the payload `combat-core`'s real hurtbox will emit once W4-A4 lands.
## `proc_depth` stays 0: this is a weapon-class hit, the only kind a relic counts
## as "a hit".
func _hit(target: Node, owner: Player) -> HitData:
	var hit := HitData.new()
	hit.base_damage = HIT_DAMAGE
	hit.element = HIT_ELEMENT
	hit.owner_player = owner
	hit.target = target
	return hit


## Fires one hit by `owner` onto `target` and returns whether the bus took it.
func _land_hit(target: Node, owner: Player) -> bool:
	return _harness.fire(Events.hit_landed, [_hit(target, owner)])


# --- the six relics: one case each -----------------------------------------

## Design doc 9.1 no. 1 — "Ember Boots: dodge leaves a fire trail".
func test_ember_boots_leaves_a_fire_trail_on_a_dodge() -> void:
	var source: RelicData = _source(&"ember_boots")
	assert_not_null(source, "data/relics/ember_boots.tres exists and loads")
	if source == null:
		return
	var boots: EmberBootsEffect = _harness.attach(source) as EmberBootsEffect
	assert_not_null(boots, "the Ember Boots effect attaches through the host")
	if boots == null:
		return
	boots.fx_scene = _fx_root_scene()

	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "the player dodges")
	_harness.assert_spawned(1, "the dodge leaves exactly one trail")
	assert_eq(_harness.spawn_count(&"ember_boots"), 1, "and it is attributed to the relic")

	var trail: RelicFxRootStub = _spawned(&"ember_boots") as RelicFxRootStub
	assert_not_null(trail, "the spawned root is the scene the relic was handed")
	if trail == null:
		return
	assert_eq(trail.position, DODGE_AT, "the trail is left where the dodge happened")
	assert_true(trail.armed, "the trail is armed before it enters the tree")
	assert_eq(trail.armed_status, int(EmberBootsEffect.TRAIL_STATUS), "with the fire it is a trail of")
	assert_eq(int(EmberBootsEffect.TRAIL_STATUS), int(StatusEffects.Status.BURN), "which is BURN")


## Design doc 9.1 no. 2 — "Storm Sandals: dodging through an enemy shocks it".
func test_storm_sandals_shocks_the_enemy_the_dodge_went_through() -> void:
	var source: RelicData = _source(&"storm_sandals")
	assert_not_null(source, "data/relics/storm_sandals.tres exists and loads")
	if source == null:
		return
	var sandals: StormSandalsEffect = _harness.attach(source) as StormSandalsEffect
	assert_not_null(sandals, "the Storm Sandals effect attaches through the host")
	if sandals == null:
		return

	var through: StatusEnemyStub = _enemy(DODGE_AT)
	var untouched: StatusEnemyStub = _enemy(FAR_AT)
	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "the player dodges")

	assert_eq(_harness.status_stacks(through, StatusEffects.Status.SHOCK), 1,
		"the enemy the dodge went through is shocked, once")
	assert_eq(_harness.status_stacks(untouched, StatusEffects.Status.SHOCK), 0,
		"an enemy the dodge never reached is not")
	assert_eq(_harness.spawn_count(&"storm_sandals"), 0, "the shock is applied, not spawned")


## Design doc 9.1 no. 3 — "Mirror Step: dodge leaves a clone that explodes after 1s".
func test_mirror_step_leaves_a_clone_armed_to_explode_after_one_second() -> void:
	var source: RelicData = _source(&"mirror_step")
	assert_not_null(source, "data/relics/mirror_step.tres exists and loads")
	if source == null:
		return
	var step: MirrorStepEffect = _harness.attach(source) as MirrorStepEffect
	assert_not_null(step, "the Mirror Step effect attaches through the host")
	if step == null:
		return
	step.fx_scene = _fx_root_scene()

	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "the player dodges")
	_harness.assert_spawned(1, "the dodge leaves exactly one clone")
	assert_eq(_harness.spawn_count(&"mirror_step"), 1, "and it is attributed to the relic")

	var clone: RelicFxRootStub = _spawned(&"mirror_step") as RelicFxRootStub
	assert_not_null(clone, "the spawned root is the scene the relic was handed")
	if clone == null:
		return
	assert_eq(clone.position, DODGE_AT, "the clone stands where the dodge happened")
	assert_true(clone.armed, "the clone is armed before it enters the tree")
	assert_almost_eq(clone.fuse_seconds, MirrorStepEffect.CLONE_FUSE_SECONDS, EPSILON,
		"and armed with the relic's own fuse")
	# The explosion itself is a hurtbox and a damage pass the clone's scene owns:
	# the request is what this case can assert, and the plan's sub-task says so.
	assert_almost_eq(MirrorStepEffect.CLONE_FUSE_SECONDS, 1.0, EPSILON,
		"the fuse is the design doc's 1s (blocked on Dev A W4-A4: the clone's explosion hurtbox)")


## Design doc 9.1 no. 4 — "Frostwalkers: dodge freezes the ground, enemies slip".
func test_frostwalkers_drops_a_freezing_ground_patch() -> void:
	var source: RelicData = _source(&"frostwalkers")
	assert_not_null(source, "data/relics/frostwalkers.tres exists and loads")
	if source == null:
		return
	var walkers: FrostwalkersEffect = _harness.attach(source) as FrostwalkersEffect
	assert_not_null(walkers, "the Frostwalkers effect attaches through the host")
	if walkers == null:
		return
	walkers.fx_scene = _fx_root_scene()

	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "the player dodges")
	_harness.assert_spawned(1, "the dodge drops exactly one patch")
	assert_eq(_harness.spawn_count(&"frostwalkers"), 1, "and it is attributed to the relic")

	var patch: RelicFxRootStub = _spawned(&"frostwalkers") as RelicFxRootStub
	assert_not_null(patch, "the spawned root is the scene the relic was handed")
	if patch == null:
		return
	assert_eq(patch.position, DODGE_AT, "the patch freezes the ground the dodge crossed")
	assert_true(patch.armed, "the patch is armed before it enters the tree")
	assert_eq(int(FrostwalkersEffect.PATCH_STATUS), int(StatusEffects.Status.FREEZE),
		"the patch freezes rather than chills")
	assert_eq(patch.armed_status, int(FrostwalkersEffect.PATCH_STATUS),
		"and the patch is armed with exactly that (blocked on Dev A W4-A4: who the patch touches)")


## Design doc 9.1 no. 5 — "Ghost Wrap: perfect dodges make you invisible for 2s".
func test_ghost_wrap_hides_a_perfect_dodge_for_two_seconds() -> void:
	var source: RelicData = _source(&"ghost_wrap")
	assert_not_null(source, "data/relics/ghost_wrap.tres exists and loads")
	if source == null:
		return
	var wrap: GhostWrapEffect = _harness.attach(source) as GhostWrapEffect
	assert_not_null(wrap, "the Ghost Wrap effect attaches through the host")
	if wrap == null:
		return
	var alpha_before: float = _player.modulate.a

	assert_true(_harness.fire(Events.player_dodged, [_player, true]), "the player perfect-dodges")
	assert_almost_eq(_player.modulate.a, GhostWrapEffect.INVISIBLE_ALPHA, EPSILON,
		"a perfect dodge turns the player invisible")

	var clock: Timer = _timer_for(wrap)
	assert_not_null(clock, "the invisibility runs on a clock")
	if clock == null:
		return
	assert_almost_eq(clock.wait_time, GhostWrapEffect.INVISIBLE_SECONDS, EPSILON,
		"for the relic's own two seconds")
	clock.timeout.emit()
	assert_almost_eq(_player.modulate.a, alpha_before, EPSILON, "and it ends when the clock runs out")

	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "now the player dodges plainly")
	assert_almost_eq(_player.modulate.a, alpha_before, EPSILON, "which is not a perfect dodge, so no invisibility")
	assert_almost_eq(GhostWrapEffect.INVISIBLE_SECONDS, 2.0, EPSILON, "the two seconds are the design doc's 2s")


## Design doc 9.1 no. 6 — "Rebound Spring: dodge distance doubled, dodging into
## walls bounces you off them".
func test_rebound_spring_doubles_the_dodge_and_asks_for_the_wall_bounce() -> void:
	var source: RelicData = _source(&"rebound_spring")
	assert_not_null(source, "data/relics/rebound_spring.tres exists and loads")
	if source == null:
		return
	var spring: ReboundSpringEffect = _harness.attach(source) as ReboundSpringEffect
	assert_not_null(spring, "the Rebound Spring effect attaches through the host")
	if spring == null:
		return
	# SPEC-player-controller exposes the dodge's distance as
	# `dodge_distance_mult`; the relic doubles it through that field.
	assert_almost_eq(_player.dodge_distance_mult, ReboundSpringEffect.DODGE_DISTANCE_MULTIPLIER, EPSILON,
		"the held relic doubles the dodge distance")
	assert_almost_eq(ReboundSpringEffect.DODGE_DISTANCE_MULTIPLIER, 2.0, EPSILON,
		"which is what the design doc's 'doubled' means")

	# The reflection is the Dodge state's movement (Dev A, W2-A8), so the relic
	# asks a `DodgeSeam` node for it when one is there and this is the ask.
	var seam := DodgeSeamStub.new()
	seam.name = ReboundSpringEffect.DODGE_SEAM_NAME
	_player.add_child(seam)

	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "the player dodges")
	assert_eq(seam.wall_bounce_requests, 1, "the relic asks the Dodge seam to bounce once")
	assert_eq(_player.dodge_distance_mult, ReboundSpringEffect.DODGE_DISTANCE_MULTIPLIER,
		"and the doubled distance stands while the relic is held")

	assert_true(_harness.detach(source), "the relic detaches")
	assert_almost_eq(_player.dodge_distance_mult, 1.0, EPSILON, "and the dodge distance goes back")


# --- the batch's two halves, together --------------------------------------

## The six are dodge relics: one dodge fires all six, and a dodge by anybody
## else fires none. `EventEmitterHelper` is the bus's own emitter and carries its
## own fake player, which is exactly the teammate this case needs.
func test_the_six_fire_for_their_own_players_dodge_and_none_for_a_teammates() -> void:
	var attached: Array[Effect] = []
	for relic_id: StringName in ON_DODGE_IDS:
		var effect: Effect = _attach(relic_id)
		assert_not_null(effect, "%s attaches" % relic_id)
		if effect == null:
			return
		attached.append(effect)
	var boots: EmberBootsEffect = attached[0] as EmberBootsEffect
	var step: MirrorStepEffect = attached[2] as MirrorStepEffect
	var walkers: FrostwalkersEffect = attached[3] as FrostwalkersEffect
	boots.fx_scene = _fx_root_scene()
	step.fx_scene = _fx_root_scene()
	walkers.fx_scene = _fx_root_scene()

	var through: StatusEnemyStub = _enemy(DODGE_AT)

	# A teammate's dodge, emitted by the bus's own emitter for its own player.
	_emitter.emit_player_dodged()
	_harness.assert_no_spawns("a teammate's dodge leaves nothing behind")
	assert_eq(_harness.status_stacks(through, StatusEffects.Status.SHOCK), 0, "and shocks nobody")
	assert_almost_eq(_player.modulate.a, 1.0, EPSILON, "and hides nobody")

	# The relic holder's own dodge, and the same three relics react.
	assert_true(_harness.fire(Events.player_dodged, [_player, true]), "the holder perfect-dodges")
	assert_eq(_harness.spawn_count(), 3, "the three spawning relics each leave one thing")
	assert_eq(_harness.status_stacks(through, StatusEffects.Status.SHOCK), 1, "the sandals shock")
	assert_almost_eq(_player.modulate.a, GhostWrapEffect.INVISIBLE_ALPHA, EPSILON, "the wrap hides")


# --- the data: names, sentences, tags, vfx ids ------------------------------

## Criterion 4: the display names, the descriptions and the tags are the design
## doc's, and the sentences keep the numbers the effect scripts use.
func test_the_six_data_files_are_the_design_docs_own_text() -> void:
	var clauses: Dictionary = _on_dodge_clauses()
	assert_eq(clauses.size(), ON_DODGE_COUNT, "design doc 9.1 nos. 1 to 6 parse out of the document")

	var art_spec: String = FileAccess.get_file_as_string(ART_SPEC_PATH)
	assert_true(art_spec.contains("relic_proc_<tag>"), "SPEC-art-audio states the relic proc id rule")

	for number: int in range(1, ON_DODGE_COUNT + 1):
		var expected: Dictionary = clauses.get(number, {}) as Dictionary
		assert_false(expected.is_empty(), "design doc 9.1 no. %d was read" % number)
		if expected.is_empty():
			continue
		var display_name: String = String(expected["name"])
		var relic_id: StringName = _id_from_display_name(display_name)
		assert_eq(ON_DODGE_IDS[number - 1], relic_id, "no. %d is %s in the batch order" % [number, relic_id])

		var data: RelicData = _source(relic_id)
		assert_not_null(data, "%s.tres loads as a RelicData" % relic_id)
		if data == null:
			continue
		assert_eq(String(data.id), String(relic_id), "the id is the file name")
		assert_eq(String(data.display_name), display_name, "%s is the design doc's name" % relic_id)
		var sentence: String = String(expected["text"]).to_lower()
		assert_true(String(data.description).to_lower().contains(sentence),
			"%s's description is the design doc's sentence (%s)" % [relic_id, sentence])
		assert_eq(data.kind, RelicData.Kind.PASSIVE, "%s is a passive relic" % relic_id)
		assert_eq(data.max_stacks, 1, "%s does not stack" % relic_id)
		assert_between(data.tags.size(), 1, 2, "%s carries 1 to 2 tags" % relic_id)
		assert_true(data.tags.has(Tags.DODGE), "%s carries the Dodge tag Phantom Dancer counts" % relic_id)
		for tag: StringName in data.tags:
			assert_true(Tags.is_valid(tag), "%s's tag `%s` is in the vocabulary" % [relic_id, tag])
		# SPEC-art-audio: "relic_proc_<tag> (one per relic tag)". The proc a relic
		# plays is named for the first tag it carries — its element, where it has
		# one — and the scene it spawns is that id under `scenes/vfx/`.
		if not data.tags.is_empty():
			assert_eq(String(data.vfx_id), "relic_proc_%s" % data.tags[0],
				"%s names SPEC-art-audio's proc id for its own tag" % relic_id)


## Criterion 4's second half: the numbers a description states are the effect
## script's constants, read out of the script rather than restated here.
func test_the_descriptions_numbers_are_the_effect_scripts_constants() -> void:
	for link: Dictionary in NUMBER_LINKS:
		var relic_id: StringName = link["id"]
		var data: RelicData = _source(relic_id)
		assert_not_null(data, "%s.tres loads" % relic_id)
		if data == null:
			continue
		var script: GDScript = data.effect_script
		assert_not_null(script, "%s's effect_script is set" % relic_id)
		if script == null:
			continue
		var constants: Dictionary = script.get_script_constant_map()
		var name: StringName = link["constant"]
		assert_true(constants.has(name), "%s's script declares %s" % [relic_id, name])
		if not constants.has(name):
			continue
		assert_almost_eq(float(constants[name]), float(link["value"]), EPSILON,
			"%s's %s is the design doc's number" % [relic_id, name])
		assert_true(String(data.description).to_lower().contains(String(link["text"])),
			"%s's description states it as `%s` (grep it in both: %s and %s.tres)" % [
				relic_id, link["text"], script.resource_path, relic_id])


## The three spawning relics take their scene from the relic's own `vfx_id`
## under SPEC-art-audio's folder — `scenes/vfx/<vfx_id>.tscn`, the layout that
## spec fixes — and a relic whose scene is not in the library yet drops the
## spawn rather than erroring. The art library's relic procs are W4-B12/B13;
## when they land, this case's second half asserts a spawn instead of a drop
## without changing a line.
func test_the_spawning_relics_take_their_scene_from_the_relics_own_vfx_id() -> void:
	for relic_id: StringName in ON_DODGE_IDS:
		var data: RelicData = _source(relic_id)
		if data == null:
			fail_test("%s.tres loads" % relic_id)
			continue
		assert_eq(String(data.vfx_id), "relic_proc_%s" % data.tags[0],
			"%s names SPEC-art-audio's proc id for its own first tag" % relic_id)

	# The three that spawn resolve their scene themselves out of that folder.
	assert_eq(EmberBootsEffect.SCENE_DIR, FX_SCENE_DIR, "Ember Boots spawns out of SPEC-art-audio's folder")
	assert_eq(MirrorStepEffect.SCENE_DIR, FX_SCENE_DIR, "Mirror Step spawns out of SPEC-art-audio's folder")
	assert_eq(FrostwalkersEffect.SCENE_DIR, FX_SCENE_DIR, "Frostwalkers spawn out of SPEC-art-audio's folder")

	# Nothing injected: the relic's own resolution decides, so it spawns exactly
	# when the scene exists and stays quiet when it does not.
	var source: RelicData = _source(&"ember_boots")
	assert_not_null(source, "ember_boots.tres loads")
	if source == null:
		return
	var scene_path: String = FX_SCENE_DIR.path_join("%s.tscn" % source.vfx_id)
	var scene_exists: bool = ResourceLoader.exists(scene_path)
	var boots: EmberBootsEffect = _harness.attach(source) as EmberBootsEffect
	assert_not_null(boots, "the Ember Boots effect attaches")
	if boots == null:
		return
	assert_true(_harness.fire(Events.player_dodged, [_player, false]), "the player dodges")
	assert_eq(_harness.spawn_count(&"ember_boots"), 1 if scene_exists else 0,
		"exactly one trail is spawned when %s exists (art-audio's W4-B12/B13 scene)" % scene_path)


# --- the five "On Hit" relics: one case each --------------------------------

## Design doc 9.1 no. 7 — "Echo Blade: every 4th hit strikes twice".
func test_echo_blade_makes_every_fourth_hit_strike_twice() -> void:
	var source: RelicData = _source(&"echo_blade")
	assert_not_null(source, "data/relics/echo_blade.tres exists and loads")
	if source == null:
		return
	var blade: EchoBladeEffect = _harness.attach(source) as EchoBladeEffect
	assert_not_null(blade, "the Echo Blade effect attaches through the host")
	if blade == null:
		return
	var target: Node2D = _harness.make_target(HIT_AT)

	for n: int in 3:
		assert_true(_land_hit(target, _player), "hit %d lands" % (n + 1))
	assert_eq(_harness.damage_count(target), 0, "the first three hits strike once, as the weapon's own")

	assert_true(_land_hit(target, _player), "the fourth hit lands")
	assert_eq(_harness.damage_count(target), 1, "and it strikes twice: one echo lands on the same target")
	var echo: HitData = _harness.world.damage_hits(target)[0]
	assert_almost_eq(echo.base_damage, HIT_DAMAGE, EPSILON, "the echo is a full hit, not a fraction of one")
	assert_true(echo.tags.has(&"echo_blade"), "and it carries the relic's own id, so it cannot echo itself")
	assert_eq(echo.proc_depth, 1, "it is one proc link deeper than the hit that caused it")

	assert_true(_land_hit(target, _player), "the fifth hit lands")
	assert_eq(_harness.damage_count(target), 1, "and does not echo")
	for n: int in 2:
		assert_true(_land_hit(target, _player), "hit %d lands" % (n + 6))
	assert_true(_land_hit(target, _player), "the eighth hit lands")
	assert_eq(_harness.damage_count(target), 2, "every fourth hit echoes, not only the fourth")


## Design doc 9.1 no. 8, the roll forced good — "Spark Plug: 10% chance on hit
## to fire chain lightning".
func test_spark_plug_fires_chain_lightning_when_its_roll_comes_good() -> void:
	var source: RelicData = _source(&"spark_plug")
	assert_not_null(source, "data/relics/spark_plug.tres exists and loads")
	if source == null:
		return
	var plug: SparkPlugEffect = _harness.attach(source) as SparkPlugEffect
	assert_not_null(plug, "the Spark Plug effect attaches through the host")
	if plug == null:
		return
	var target: Node2D = _harness.make_target(HIT_AT)
	plug.chain_chance = 1.0

	assert_true(_land_hit(target, _player), "the hit lands")
	assert_eq(_harness.status_stacks(target, SparkPlugEffect.CHAIN_STATUS), 1,
		"with the roll forced good the hit chains, once")
	assert_eq(int(SparkPlugEffect.CHAIN_STATUS), int(StatusEffects.Status.SHOCK),
		"and the chain is SHOCK's own — stats-status chains it on application")
	assert_eq(_harness.spawn_count(&"spark_plug"), 0, "the lightning is applied, not spawned")
	assert_eq(_harness.damage_count(target), 0, "and the relic deals no damage of its own")


## Design doc 9.1 no. 8, the roll forced bad: the same hit, nothing chained.
func test_spark_plug_stays_quiet_when_its_roll_comes_bad() -> void:
	var source: RelicData = _source(&"spark_plug")
	assert_not_null(source, "data/relics/spark_plug.tres exists and loads")
	if source == null:
		return
	var plug: SparkPlugEffect = _harness.attach(source) as SparkPlugEffect
	assert_not_null(plug, "the Spark Plug effect attaches through the host")
	if plug == null:
		return
	var target: Node2D = _harness.make_target(HIT_AT)
	plug.chain_chance = 0.0

	assert_true(_land_hit(target, _player), "the hit lands")
	assert_eq(_harness.status_stacks(target, SparkPlugEffect.CHAIN_STATUS), 0,
		"with the roll forced bad nothing chains")


## The roll a live relic makes is the design doc's 10 %, and the injection point
## a case forces is a default rather than a second number.
func test_spark_plug_defaults_its_roll_to_the_design_docs_ten_percent() -> void:
	var source: RelicData = _source(&"spark_plug")
	assert_not_null(source, "data/relics/spark_plug.tres exists and loads")
	if source == null:
		return
	var plug: SparkPlugEffect = _harness.attach(source) as SparkPlugEffect
	assert_not_null(plug, "the Spark Plug effect attaches through the host")
	if plug == null:
		return
	assert_almost_eq(plug.chain_chance, SparkPlugEffect.CHAIN_CHANCE, EPSILON,
		"an untouched relic rolls the constant")
	assert_almost_eq(SparkPlugEffect.CHAIN_CHANCE, 0.10, EPSILON, "which is the design doc's 10%")


## Design doc 9.1 no. 9 — "Hungry Steel: each hit on the same enemy deals +5 %
## more (stacks)". One stack and three.
func test_hungry_steel_deals_five_percent_more_per_hit_on_the_same_enemy() -> void:
	var source: RelicData = _source(&"hungry_steel")
	assert_not_null(source, "data/relics/hungry_steel.tres exists and loads")
	if source == null:
		return
	var steel: HungrySteelEffect = _harness.attach(source) as HungrySteelEffect
	assert_not_null(steel, "the Hungry Steel effect attaches through the host")
	if steel == null:
		return
	var enemy: Node2D = _harness.make_target(HIT_AT)
	assert_almost_eq(steel.damage_multiplier_for(enemy), 1.0, EPSILON,
		"an enemy this player has never hit carries no bonus")

	assert_true(_land_hit(enemy, _player), "the first hit lands")
	assert_eq(steel.stacks_for(enemy), 1, "one stack on that enemy")
	assert_almost_eq(steel.damage_multiplier_for(enemy), 1.0 + HungrySteelEffect.PER_HIT_STACK_BONUS, EPSILON,
		"and the hit deals +5% more")
	assert_almost_eq(_harness.damage_total(enemy), HIT_DAMAGE * HungrySteelEffect.PER_HIT_STACK_BONUS, EPSILON,
		"the 5% lands on the enemy as the relic's own hit")

	for n: int in 2:
		assert_true(_land_hit(enemy, _player), "hit %d lands" % (n + 2))
	assert_eq(steel.stacks_for(enemy), 3, "three stacks on that enemy")
	assert_almost_eq(steel.damage_multiplier_for(enemy), 1.0 + 3.0 * HungrySteelEffect.PER_HIT_STACK_BONUS, EPSILON,
		"and the hit deals +15% more")
	assert_almost_eq(_harness.damage_total(enemy),
		HIT_DAMAGE * HungrySteelEffect.PER_HIT_STACK_BONUS * (1.0 + 2.0 + 3.0), EPSILON,
		"each hit's step is its own: 5%, 10%, 15%")


## The stack is the *enemy's*: a second enemy starts its own count, and hitting
## it does not advance the first one's.
func test_hungry_steel_stacks_are_per_enemy_and_start_again_on_a_new_target() -> void:
	var source: RelicData = _source(&"hungry_steel")
	assert_not_null(source, "data/relics/hungry_steel.tres exists and loads")
	if source == null:
		return
	var steel: HungrySteelEffect = _harness.attach(source) as HungrySteelEffect
	assert_not_null(steel, "the Hungry Steel effect attaches through the host")
	if steel == null:
		return
	var first: Node2D = _harness.make_target(HIT_AT)
	var second: Node2D = _harness.make_target(FAR_AT)

	assert_true(_land_hit(first, _player), "the first enemy takes a hit")
	assert_true(_land_hit(first, _player), "and a second")
	assert_true(_land_hit(second, _player), "a different enemy takes one")
	assert_eq(steel.stacks_for(first), 2, "the first enemy holds two")
	assert_eq(steel.stacks_for(second), 1, "the second starts at one")
	assert_almost_eq(steel.damage_multiplier_for(first), 1.0 + 2.0 * HungrySteelEffect.PER_HIT_STACK_BONUS, EPSILON,
		"the first enemy's bonus is its own count")
	assert_almost_eq(steel.damage_multiplier_for(second), 1.0 + HungrySteelEffect.PER_HIT_STACK_BONUS, EPSILON,
		"and the second enemy's is its own")

	assert_true(_land_hit(second, _player), "the second enemy takes another")
	assert_eq(steel.stacks_for(first), 2, "which does not advance the first enemy's count")
	assert_eq(steel.stacks_for(second), 2, "the second enemy's own count moves")


## The batch's stack case: `hungry_steel` is the one relic of the five whose data
## file allows more than one copy, and every copy deepens the same step.
func test_hungry_steel_more_copies_of_the_relic_deepen_the_same_step() -> void:
	var source: RelicData = _source(&"hungry_steel")
	assert_not_null(source, "data/relics/hungry_steel.tres exists and loads")
	if source == null:
		return
	assert_eq(source.max_stacks, int(ON_HIT_MAX_STACKS.get(&"hungry_steel", 0)),
		"the data file allows the three copies this case holds")
	var steel: HungrySteelEffect = _harness.attach(source, 3) as HungrySteelEffect
	assert_not_null(steel, "the Hungry Steel effect attaches through the host")
	if steel == null:
		return
	assert_eq(steel.stacks, 3, "the effect is held three times")
	var enemy: Node2D = _harness.make_target(HIT_AT)

	assert_true(_land_hit(enemy, _player), "the first hit lands")
	assert_eq(steel.stacks_for(enemy), 1, "one stack on that enemy")
	assert_almost_eq(steel.damage_multiplier_for(enemy),
		1.0 + 3.0 * HungrySteelEffect.PER_HIT_STACK_BONUS, EPSILON,
		"three copies make the first stack worth +15%")
	assert_almost_eq(_harness.damage_total(enemy),
		HIT_DAMAGE * 3.0 * HungrySteelEffect.PER_HIT_STACK_BONUS, EPSILON,
		"and three times the step lands")


## Design doc 9.1 no. 10 — "Venom Gland: hits apply Toxin".
func test_venom_gland_applies_toxin_on_hit() -> void:
	var source: RelicData = _source(&"venom_gland")
	assert_not_null(source, "data/relics/venom_gland.tres exists and loads")
	if source == null:
		return
	var gland: VenomGlandEffect = _harness.attach(source) as VenomGlandEffect
	assert_not_null(gland, "the Venom Gland effect attaches through the host")
	if gland == null:
		return
	assert_eq(int(VenomGlandEffect.HIT_STATUS), int(StatusEffects.Status.TOXIN),
		"the description's Toxin is the status the relic applies")
	var enemy: Node2D = _harness.make_target(HIT_AT)

	assert_true(_land_hit(enemy, _player), "the hit lands")
	assert_eq(_harness.status_stacks(enemy, StatusEffects.Status.TOXIN), VenomGlandEffect.TOXIN_STACKS,
		"the hit applies one stack of Toxin")
	assert_eq(_harness.damage_count(enemy), 0, "the relic deals no damage of its own")
	assert_eq(_harness.spawn_count(&"venom_gland"), 0, "and spawns nothing")


## Design doc 9.1 no. 11 — "Splitting Shot: projectiles split into 3 on hit".
## The real projectiles are combat-core's, so what this case can assert is the
## ask: the three `ProjectileSpec`s the effect hands the seam.
func test_splitting_shot_asks_the_projectile_seam_for_three_splits() -> void:
	var source: RelicData = _source(&"splitting_shot")
	assert_not_null(source, "data/relics/splitting_shot.tres exists and loads")
	if source == null:
		return
	var shot: SplittingShotEffect = _harness.attach(source) as SplittingShotEffect
	assert_not_null(shot, "the Splitting Shot effect attaches through the host")
	if shot == null:
		return
	var target: Node2D = _harness.make_target(_player.global_position + HIT_AT)
	var axis: Vector2 = HIT_AT.normalized()

	assert_true(_land_hit(target, _player), "the hit lands")
	var asked: Array[Dictionary] = _harness.world.projectiles
	assert_eq(asked.size(), SplittingShotEffect.SPLIT_COUNT, "the seam is asked for three splits")
	assert_eq(SplittingShotEffect.SPLIT_COUNT, 3, "which is the design doc's 3")

	var directions: Array[Vector2] = []
	for entry: Dictionary in asked:
		var spec: ProjectileSpec = entry["spec"] as ProjectileSpec
		assert_not_null(spec, "a spec travels whole to the seam")
		if spec == null:
			continue
		assert_almost_eq(spec.damage, HIT_DAMAGE * SplittingShotEffect.SPLIT_DAMAGE_FRACTION, EPSILON,
			"each split carries a fraction of the hit's damage")
		assert_eq(spec.element, HIT_ELEMENT, "and the element the hit carried")
		assert_null(spec.scene, "the projectile's body is combat-core's (blocked on Dev A W2-A6)")
		assert_eq(StringName(entry["proc_source_id"]), &"splitting_shot", "attributed to the relic")
		assert_eq(int(entry["proc_depth"]), 1, "one proc link deeper than the hit")
		var from: Vector2 = entry["from"]
		assert_eq(from, target.global_position, "the split starts where the hit landed")
		var dir: Vector2 = entry["direction"]
		assert_almost_eq(dir.length(), 1.0, EPSILON, "the direction is a unit vector")
		assert_true(absf(rad_to_deg(dir.angle_to(axis))) <= SplittingShotEffect.SPLIT_SPREAD_DEGREES * 0.5 + EPSILON,
			"and it sprays forward from the hit, not behind it")
		directions.append(dir)

	assert_eq(directions.size(), SplittingShotEffect.SPLIT_COUNT, "three directions were read back")
	if directions.size() == 3:
		assert_ne(directions[0], directions[1], "the three splits do not overlap")
		assert_ne(directions[1], directions[2], "the three splits do not overlap")
		assert_ne(directions[0], directions[2], "the three splits do not overlap")


# --- the batch's five, together ---------------------------------------------

## The five are On Hit relics: one hit the holder landed moves all five, and the
## same hit attributed to anybody else moves none. `EventEmitterHelper` is the
## bus's own emitter and its hit carries no `owner_player`, which is exactly the
## teammate's hit this case needs — `hit_landed` has no `Player` argument, so the
## filter the relic system applies to a dodge does not exist here and the batch's
## own `owner_player` read is the whole of it.
func test_the_five_fire_for_their_own_players_hit_and_none_for_a_teammates() -> void:
	var attached: Array[Effect] = []
	for relic_id: StringName in ON_HIT_IDS:
		var effect: Effect = _attach(relic_id)
		assert_not_null(effect, "%s attaches" % relic_id)
		if effect == null:
			return
		attached.append(effect)
	var plug: SparkPlugEffect = attached[1] as SparkPlugEffect
	plug.chain_chance = 1.0
	var target: Node2D = _harness.make_target(HIT_AT)

	# A teammate's hit, emitted by the bus's own emitter for its own player.
	_emitter.emit_hit_landed()
	assert_eq(_harness.damage_count(target), 0, "a teammate's hit lands no bonus")
	assert_eq(_harness.world.projectiles.size(), 0, "and fires no split")
	assert_eq(_harness.status_stacks(target, StatusEffects.Status.SHOCK), 0, "and chains nothing")
	assert_eq(_harness.status_stacks(target, StatusEffects.Status.TOXIN), 0, "and poisons nobody")

	# The relic holder's own hit, and all five react.
	assert_true(_land_hit(target, _player), "the holder's hit lands")
	assert_eq(_harness.damage_count(target), 1, "Hungry Steel's step lands")
	assert_eq(_harness.world.projectiles.size(), SplittingShotEffect.SPLIT_COUNT, "Splitting Shot splits")
	assert_eq(_harness.status_stacks(target, StatusEffects.Status.SHOCK), 1, "Spark Plug chains")
	assert_eq(_harness.status_stacks(target, StatusEffects.Status.TOXIN), 1, "Venom Gland poisons")
	assert_eq((attached[0] as EchoBladeEffect).hits_counted(), 1, "Echo Blade counts the hit")


# --- the data: names, sentences, tags, stacks -------------------------------

## Criterion 4, for the On Hit batch: the display names, the descriptions and
## the tags are the design doc's, and each data file's stack rule is the one the
## batch's own table states.
func test_the_five_on_hit_data_files_are_the_design_docs_own_text() -> void:
	var clauses: Dictionary = _on_hit_clauses()
	assert_eq(clauses.size(), ON_HIT_COUNT, "design doc 9.1 nos. 7 to 11 parse out of the document")

	var art_spec: String = FileAccess.get_file_as_string(ART_SPEC_PATH)
	assert_true(art_spec.contains("relic_proc_<tag>"), "SPEC-art-audio states the relic proc id rule")

	for number: int in range(ON_HIT_FIRST_NUMBER, ON_HIT_FIRST_NUMBER + ON_HIT_COUNT):
		var expected: Dictionary = clauses.get(number, {}) as Dictionary
		assert_false(expected.is_empty(), "design doc 9.1 no. %d was read" % number)
		if expected.is_empty():
			continue
		var display_name: String = String(expected["name"])
		var relic_id: StringName = _id_from_display_name(display_name)
		assert_eq(ON_HIT_IDS[number - ON_HIT_FIRST_NUMBER], relic_id,
			"no. %d is %s in the batch order" % [number, relic_id])

		var data: RelicData = _source(relic_id)
		assert_not_null(data, "%s.tres loads as a RelicData" % relic_id)
		if data == null:
			continue
		assert_eq(String(data.id), String(relic_id), "the id is the file name")
		assert_eq(String(data.display_name), display_name, "%s is the design doc's name" % relic_id)
		var sentence: String = String(expected["text"]).to_lower()
		assert_true(String(data.description).to_lower().contains(sentence),
			"%s's description is the design doc's sentence (%s)" % [relic_id, sentence])
		assert_eq(data.kind, RelicData.Kind.PASSIVE, "%s is a passive relic" % relic_id)
		assert_eq(data.max_stacks, int(ON_HIT_MAX_STACKS.get(relic_id, 0)),
			"%s's stack rule is the batch's own" % relic_id)
		assert_between(data.tags.size(), 1, 2, "%s carries 1 to 2 tags" % relic_id)
		assert_true(data.tags.has(Tags.ON_HIT), "%s carries the On Hit tag its trigger gives it" % relic_id)
		for tag: StringName in data.tags:
			assert_true(Tags.is_valid(tag), "%s's tag `%s` is in the vocabulary" % [relic_id, tag])
		if ON_HIT_ELEMENT_TAGS.has(relic_id):
			assert_eq(data.tags[0], ON_HIT_ELEMENT_TAGS[relic_id],
				"%s's element tag comes first, so its proc id is the element's" % relic_id)
		# SPEC-art-audio: "relic_proc_<tag> (one per relic tag)". The proc a relic
		# plays is named for the first tag it carries — its element, where it has
		# one — and the scene it spawns is that id under `scenes/vfx/`.
		if not data.tags.is_empty():
			assert_eq(String(data.vfx_id), "relic_proc_%s" % data.tags[0],
				"%s names SPEC-art-audio's proc id for its own tag" % relic_id)


## Criterion 4's second half, for the On Hit batch: the numbers a description
## states are the effect script's constants, read out of the script rather than
## restated here.
func test_the_on_hit_descriptions_numbers_are_the_effect_scripts_constants() -> void:
	for link: Dictionary in ON_HIT_NUMBER_LINKS:
		var relic_id: StringName = link["id"]
		var data: RelicData = _source(relic_id)
		assert_not_null(data, "%s.tres loads" % relic_id)
		if data == null:
			continue
		var script: GDScript = data.effect_script
		assert_not_null(script, "%s's effect_script is set" % relic_id)
		if script == null:
			continue
		var constants: Dictionary = script.get_script_constant_map()
		var name: StringName = link["constant"]
		assert_true(constants.has(name), "%s's script declares %s" % [relic_id, name])
		if not constants.has(name):
			continue
		assert_almost_eq(float(constants[name]), float(link["value"]), EPSILON,
			"%s's %s is the design doc's number" % [relic_id, name])
		assert_true(String(data.description).to_lower().contains(String(link["text"])),
			"%s's description states it as `%s` (grep it in both: %s and %s.tres)" % [
				relic_id, link["text"], script.resource_path, relic_id])
