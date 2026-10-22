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
## The third instalment — design doc 9.1 nos. 12 to 16, relics, W4-B6 (PLAN G7 /
## raw goal G34) — is Gravity Stone, Leech Fang and Rune of Ricochet on
## `hit_landed` and Volatile Core and Soul Jar on `enemy_killed`. `enemy_killed`
## is the second signal with no `Player` argument, so the On Kill pair filters on
## the killing hit's `owner_player` exactly as the On Hit batch does. Four of the
## five act through a provider this lane does not own, and each case asserts what
## the effect *asks* that provider for rather than a result the game cannot
## produce yet: Gravity Stone's pull is the enemy body's `pull_toward` (**blocked
## on Dev A (W4-A1)**), Leech Fang's heal is combat-core's `Health.heal`
## (**blocked on Dev A (W2-A1)**), Rune of Ricochet's ricochet is the
## projectile's `add_bounce` (**blocked on Dev A (W2-A6)**), and the ghost army
## Volatile Core's sibling releases is a spawned root (**blocked on Dev A
## (W4-A4)** / art-audio). Volatile Core's blast is no ask: it is this lane's own
## `deal_damage()` onto the enemies in range.
##
## Owned by relics. Sync: none under test — relics are host-only content
## (SPEC-relics "Multiplayer ownership") and the harness is one process.
##
## The fourth and last instalment — design doc 9.1 nos. 17 to 20, relics,
## W4-B6 (PLAN G8a / raw goal G35) — is the batch that closes the week's twenty:
## Bloodthirst, Corpse Bloom, Domino and Trophy Belt, all on `enemy_killed`'s
## trigger. Three of the four act on a provider this lane does not own and each
## case says which: Bloodthirst's buff and Trophy Belt's accumulation are the
## player's own `StatBlock` (this lane's), Corpse Bloom's flower is a spawned FX
## root whose healing is its own body (**blocked on Dev A (W4-A4)** /
## art-audio), and Domino's spread reads and writes the enemy-side `StatusEffects`
## component stats-status ships and Dev A's enemy scene composes
## (**blocked on Dev A (W4-A1)**). Trophy Belt listens on `elite_killed` because
## SPEC-enemies-ai names that signal for it — "Elite death emits
## `Events.elite_killed` for `run-economy` (loot, Echo Shards) and Trophy Belt" —
## and the other three on `enemy_killed`, which SPEC-relics names as one of the
## three events the Week 4 relics exercise.
##
## The batch's four stack cases live here too: Hungry Steel's per-enemy step
## (G6), Bloodthirst's five-stack buff and Trophy Belt's run-long accumulation
## (this batch), and Soul Jar's jar (G7).
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
const HIT_ELEMENT: HitInfo.Element = HitInfo.Element.STORM
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

## The second "On Hit" instalment — design doc 9.1 nos. 12 to 14, in that order,
## which are `RelicData.WEEK_4_IDS`' twelfth to fourteenth.
const ON_HIT_TAIL_IDS: Array[StringName] = [
	&"gravity_stone",
	&"leech_fang",
	&"rune_of_ricochet",
]
## The "On Kill" pair — design doc 9.1 nos. 15 and 16, the fifteenth and
## sixteenth of `RelicData.WEEK_4_IDS`, and the batch that opens `enemy_killed`.
const ON_KILL_IDS: Array[StringName] = [
	&"volatile_core",
	&"soul_jar",
]
## Where the second "On Hit" batch starts in 9.1 and how many it holds, and the
## same pair for the On Kill one. The two constants are what the numbered ranges
## below and the data cases are built from.
const ON_HIT_TAIL_FIRST_NUMBER: int = 12
const ON_HIT_TAIL_COUNT: int = 3
const ON_KILL_FIRST_NUMBER: int = 15
const ON_KILL_COUNT: int = 2
## What each `.tres` of the two batches must hold. Soul Jar is the batch's one
## stackable relic — the plan names it with Hungry Steel, Bloodthirst and Trophy
## Belt as W4-B6's four stack cases — and the other four take a single copy.
const LATE_BATCH_MAX_STACKS: Dictionary[StringName, int] = {
	&"gravity_stone": 1,
	&"leech_fang": 1,
	&"rune_of_ricochet": 1,
	&"volatile_core": 1,
	&"soul_jar": 2,
}
## The element tag design doc 9.1's Pyromaniac row gives one of the two batches'
## relics — "Ember Boots, Kindling, Ember Heart, Volatile Core, Glass Cannonball
## (explosions tagged fire), Prism" is the 4-fire list, so Volatile Core is a
## fire relic and its proc id is the fire one. The other four carry their
## trigger's tag alone.
const LATE_BATCH_ELEMENT_TAGS: Dictionary[StringName, StringName] = {
	&"volatile_core": Tags.FIRE,
}
## The numbers the two batches' descriptions state, and the effect-script
## constant each one is — the same read G5's and G6's batches get (SPEC-relics:
## "balance numbers in the description are the source of truth for the effect
## script's constants"). Gravity Stone and Volatile Core state no number.
const LATE_BATCH_NUMBER_LINKS: Array[Dictionary] = [
	{"id": &"leech_fang", "constant": &"HEAL_FRACTION", "text": "2%", "value": 0.02},
	{"id": &"rune_of_ricochet", "constant": &"EXTRA_BOUNCES", "text": "2 more", "value": 2.0},
	{"id": &"soul_jar", "constant": &"SOUL_JAR_KILLS", "text": "20", "value": 20.0},
	{"id": &"soul_jar", "constant": &"GHOST_ARMY_SECONDS", "text": "10s", "value": 10.0},
]

## The last "On Kill" batch — design doc 9.1 nos. 17 to 20 in that order, which
## are `RelicData.WEEK_4_IDS`' seventeenth to twentieth: Bloodthirst, Corpse
## Bloom, Domino, Trophy Belt. The batch that closes the week's twenty.
const FINAL_BATCH_IDS: Array[StringName] = [
	&"bloodthirst",
	&"corpse_bloom",
	&"domino",
	&"trophy_belt",
]
## Where the batch starts in 9.1 and how many it holds.
const FINAL_BATCH_FIRST_NUMBER: int = 17
const FINAL_BATCH_COUNT: int = 4
## What each `.tres` of the batch must hold. Bloodthirst is the one whose
## `(stacks 5x)` the design doc states, so its data file allows five copies —
## the cap is the doc's number and the buff's own cap is the same number.
const FINAL_BATCH_MAX_STACKS: Dictionary[StringName, int] = {
	&"bloodthirst": 5,
	&"corpse_bloom": 1,
	&"domino": 1,
	&"trophy_belt": 1,
}
## The batch carries no element tag, so this table is empty: the design doc gives
## none of the four any elemental language. Their only tag is their trigger's —
## the same read `_check_clause_relic` takes for the other three batches, with an
## empty element table instead of omitting the argument.
const FINAL_BATCH_ELEMENT_TAGS: Dictionary[StringName, StringName] = {}
## The numbers the batch's descriptions state, and the effect-script constant
## each one is — the same read the other three batches get (SPEC-relics: "balance
## numbers in the description are the source of truth for the effect script's
## constants"). Corpse Bloom and Domino state no number.
const FINAL_BATCH_NUMBER_LINKS: Array[Dictionary] = [
	{"id": &"bloodthirst", "constant": &"PER_KILL_BONUS", "text": "10%", "value": 0.10},
	{"id": &"bloodthirst", "constant": &"BLOODTHIRST_SECONDS", "text": "3s", "value": 3.0},
	{"id": &"bloodthirst", "constant": &"MAX_STACKS", "text": "5x", "value": 5.0},
	{"id": &"trophy_belt", "constant": &"PER_ELITE_BONUS", "text": "3%", "value": 0.03},
]

## Where the two batches' neighbours stand: one inside Gravity Stone's pull
## reach and Volatile Core's blast, one well outside both. Both are measured
## from the enemy the hit landed on, which is the centre of each.
const NEARBY_AT: Vector2 = Vector2(32.0, 0.0)
const OUT_OF_REACH_AT: Vector2 = Vector2(400.0, 0.0)
## The damage the Leech Fang case's hits land for, so 2% of them is a round
## number, and what those two hits heal for. Written down rather than derived,
## so the case fails if the fraction changes shape.
const LEECH_DAMAGE: int = 100
const LEECH_HEAL: int = 2
const LEECH_HEAL_HALF: int = 1
## The harness player's HP and the value it starts the Leech Fang case at — below
## the maximum, so the heal visibly moves it instead of clamping at the cap.
const HEALTH_MAX: int = 100
const HEALTH_START: int = 50
## The `Health` component node the heal path looks for, and the double standing
## in for combat-core's (Dev A, W2-A1) heal half.
const HEALTH_NODE: NodePath = ^"Health"
const HEALTH_STUB_PATH: String = "res://tests/helpers/status_health_stub.gd"
## The attack-speed base the Bloodthirst cases seed onto the harness player's
## `StatBlock`. `EffectHarness` fills MOVE_SPEED, ATTACK and LUCK only, and a
## percentage modifier reads `(base + flat) * (1 + percent)` — 0.0 for a stat
## with no base — so the case seeds the spawn-time base itself. The real value
## comes from `CharacterData`/`ClassData` on Dev A's player scene (**blocked on
## Dev A (W2-A1)**); 1.0 is the neutral multiplier the buff multiplies.
const ATTACK_SPEED_BASE: float = 1.0

var _harness: EffectHarness
var _player: Player
var _emitter: EventEmitterHelper
## The six real `.tres` files by id. Null for one that does not exist, which is
## what every case's first assertion reports.
var _sources: Dictionary[StringName, ContentData] = {}
## How many enemies `_enemy_at()` has built this case, so the doubles under one
## root never collide on a name.
var _enemy_count: int = 0


func before_each() -> void:
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_player.global_position = DODGE_AT
	_emitter = EventEmitterHelper.new()
	_sources = {}
	_enemy_count = 0
	for relic_id: StringName in ON_DODGE_IDS:
		_sources[relic_id] = load(_relic_path(relic_id)) as ContentData
	for relic_id: StringName in ON_HIT_IDS:
		_sources[relic_id] = load(_relic_path(relic_id)) as ContentData
	for relic_id: StringName in ON_HIT_TAIL_IDS:
		_sources[relic_id] = load(_relic_path(relic_id)) as ContentData
	for relic_id: StringName in ON_KILL_IDS:
		_sources[relic_id] = load(_relic_path(relic_id)) as ContentData
	for relic_id: StringName in FINAL_BATCH_IDS:
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
	_install_statuses(enemy)
	return enemy


## The `StatusEffects` double on `entity`, added if it carries none — the
## component Domino reads the corpse's statuses off and applies the spread
## through. The real component is stats-status's (`scripts/components/
## status_effects.gd`, W4-B4) and the enemy scene it rides on is Dev A's
## (**blocked on Dev A (W4-A1)**); the double records every `apply_status`, so a
## spread can be read back without a live component on a double's node.
func _install_statuses(entity: Node) -> StatusEffectsStub:
	var existing: Node = entity.get_node_or_null(EffectHarness.STATUS_NODE)
	if existing is StatusEffectsStub:
		return existing as StatusEffectsStub
	var component := StatusEffectsStub.new()
	component.name = EffectHarness.STATUS_NAME
	entity.add_child(component)
	return component


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
func _hit(target: Node, owner: Player) -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = HIT_DAMAGE
	hit.element = HIT_ELEMENT
	hit.owner_player = owner
	hit.target = target
	return hit


## Fires one hit by `owner` onto `target` and returns whether the bus took it.
func _land_hit(target: Node, owner: Player) -> bool:
	return _harness.fire(Events.hit_landed, [_hit(target, owner)])


## An enemy double the two later batches can act on: a `StatusEnemyStub` — a
## `CharacterBody2D` in the `enemy` group carrying a `Health` double — with a
## recording `Hurtbox` added, so a hit dealt to it is recorded by the harness's
## `SpyWorld` exactly as a hit on a `make_target()` node is. Dev A's real enemy
## replaces both halves in place: the body is W4-A1's and the hurtbox is
## W2-A2's, so the swap-in is a delete, not a rewrite (**blocked on Dev A**).
func _enemy_at(at: Vector2, max_hp: int = 100) -> StatusEnemyStub:
	_enemy_count += 1
	var enemy: StatusEnemyStub = StatusEnemyStub.make(_harness.root, at, max_hp)
	enemy.name = "BatchEnemy%d" % _enemy_count
	var hurtbox := SpyHurtbox.new()
	hurtbox.name = &"Hurtbox"
	hurtbox.world = _harness.world
	enemy.add_child(hurtbox)
	return enemy


## One `enemy_killed` for `enemy`, credited to `owner` — the payload Dev A's
## enemy emits when it dies (W4-A4). The killing hit is a weapon hit: depth 0
## and no tags, so it is nobody's proc first.
func _kill(enemy: Node, owner: Player) -> bool:
	var hit: HitInfo = _hit(enemy, owner)
	hit.final_damage = LEECH_DAMAGE
	return _harness.fire(Events.enemy_killed, [enemy, hit])


## Installs the `Health` double on the harness player — the node the heal path
## asks for — and returns it, with the player at part health so a heal has room
## to land. The real `Health` is combat-core's (**blocked on Dev A (W2-A1)**) and
## emits `Events.player_healed`; the double records what arrived instead.
func _install_health() -> StatusHealthStub:
	var node: Node = _player.get_node_or_null(HEALTH_NODE)
	assert_not_null(node, "the player scene carries a %s node to heal" % HEALTH_NODE)
	if node == null:
		return null
	node.set_script(load(HEALTH_STUB_PATH) as Script)
	var health: StatusHealthStub = node as StatusHealthStub
	assert_not_null(health, "the double installs on the player's %s" % HEALTH_NODE)
	if health == null:
		return null
	health.max_hp = HEALTH_MAX
	health.current_hp = HEALTH_START
	return health


## Design doc 9.1 nos. 12 to 14 — the second On Hit batch — as
## `{number: {name, text}}`, parsed out of the document at run time.
func _on_hit_tail_clauses() -> Dictionary:
	return _clauses_in_range(ON_HIT_TAIL_FIRST_NUMBER, ON_HIT_TAIL_FIRST_NUMBER + ON_HIT_TAIL_COUNT - 1)


## Design doc 9.1 nos. 15 and 16 — the On Kill pair — the same read.
func _on_kill_clauses() -> Dictionary:
	return _clauses_in_range(ON_KILL_FIRST_NUMBER, ON_KILL_FIRST_NUMBER + ON_KILL_COUNT - 1)


## Design doc 9.1 nos. 17 to 20 — the last On Kill batch — the same read.
func _final_batch_clauses() -> Dictionary:
	return _clauses_in_range(FINAL_BATCH_FIRST_NUMBER, FINAL_BATCH_FIRST_NUMBER + FINAL_BATCH_COUNT - 1)


## One `elite_killed` for `enemy`, credited to `owner`. SPEC-enemies-ai is the
## sentence that makes this the elitist batch's signal rather than this lane's
## guess: "Elite death emits `Events.elite_killed` for `run-economy` (loot, Echo
## Shards) and Trophy Belt". The payload is the same shape `_kill()` fires —
## `elite_killed(enemy, hit)` and no `Player` argument — so the filter is the
## killing hit's `owner_player`.
func _elite_kill(enemy: Node, owner: Player) -> bool:
	var hit: HitInfo = _hit(enemy, owner)
	hit.final_damage = LEECH_DAMAGE
	return _harness.fire(Events.elite_killed, [enemy, hit])


## The harness player's own `StatBlock`, so a case can seed the spawn-time bases
## `EffectHarness` leaves unset for the stats it does not assert on.
func _player_stat_block() -> StatBlock:
	var node: Node = _player.get_node_or_null(EffectHarness.STAT_BLOCK_NODE)
	return node as StatBlock


## Seeds the harness player's attack-speed base — spawn setup, which is the one
## time `StatBlock.set_base()` is ever the right call. See `ATTACK_SPEED_BASE`.
func _seed_attack_speed() -> void:
	var block: StatBlock = _player_stat_block()
	assert_not_null(block, "the harness player carries a StatBlock")
	if block != null:
		block.set_base(StatBlock.Stat.ATTACK_SPEED, ATTACK_SPEED_BASE)


## The harness player's attack speed right now, through `StatBlock.get_value()`:
## the number Bloodthirst's percentage modifier moves.
func _attack_speed() -> float:
	return _harness.stat_of(_player, StatBlock.Stat.ATTACK_SPEED)


## The harness player's attack right now: the number Trophy Belt's percentage
## modifier moves.
func _attack() -> float:
	return _harness.stat_of(_player, StatBlock.Stat.ATTACK)


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
	var echo: HitInfo = _harness.world.damage_hits(target)[0]
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


# --- the second "On Hit" batch: one case each -------------------------------

## Design doc 9.1 no. 12 — "Gravity Stone: hits pull nearby enemies slightly
## toward the target". The pull is the enemy body's movement (Dev A, W4-A1), so
## the case asserts the request each enemy receives and not a moved position.
func test_gravity_stone_pulls_nearby_enemies_toward_the_hit_target() -> void:
	var source: RelicData = _source(&"gravity_stone")
	assert_not_null(source, "data/relics/gravity_stone.tres exists and loads")
	if source == null:
		return
	var stone: GravityStoneEffect = _harness.attach(source) as GravityStoneEffect
	assert_not_null(stone, "the Gravity Stone effect attaches through the host")
	if stone == null:
		return
	var target: StatusEnemyStub = _enemy_at(HIT_AT)
	var near: StatusEnemyStub = _enemy_at(HIT_AT + NEARBY_AT)
	var far: StatusEnemyStub = _enemy_at(OUT_OF_REACH_AT)

	assert_true(_land_hit(target, _player), "the hit lands")
	assert_eq(near.pulls.size(), 1, "the enemy inside the pull's reach is asked to pull")
	if near.pulls.size() == 1:
		assert_eq(near.pulls[0]["origin"], target, "toward the enemy the hit landed on")
		assert_eq(near.pulls[0]["radius"], GravityStoneEffect.PULL_RADIUS)
	assert_eq(far.pulls.size(), 0, "the enemy outside the reach is not asked")
	assert_eq(target.pulls.size(), 0, "and the target is the centre of the pull, not one of its subjects")
	assert_eq(_harness.damage_count(target), 0, "the pull deals no damage of its own")
	assert_eq(_harness.damage_count(near), 0, "nor to the enemy it moves")
	assert_eq(_harness.spawn_count(&"gravity_stone"), 0, "and spawns nothing")


## The reach is this lane's balance call — the design doc says "slightly" and
## gives no number — so it is pinned here rather than left to drift.
func test_gravity_stone_pulls_from_the_reach_its_own_constant_states() -> void:
	assert_eq(GravityStoneEffect.PULL_RADIUS, 96.0, "Gravity Stone pulls from 96 px")
	assert_true(GravityStoneEffect.PULL_RADIUS < StatusEffects.COLLAPSE_RADIUS,
		"a lesser pull than the Void combo's 128 px")
	assert_eq(StringName(GravityStoneEffect.PULL_METHOD), StatusEffects.PULL_METHOD,
		"and it asks the seam stats-status already publishes, not a second one")


## Design doc 9.1 no. 13 — "Leech Fang: heal 2% of damage dealt". The assertion
## is on the HP that landed, not on the fraction, so a heal path that never ran
## cannot pass by reading a constant.
func test_leech_fang_heals_its_holder_two_percent_of_the_damage_dealt() -> void:
	var source: RelicData = _source(&"leech_fang")
	assert_not_null(source, "data/relics/leech_fang.tres exists and loads")
	if source == null:
		return
	var fang: LeechFangEffect = _harness.attach(source) as LeechFangEffect
	assert_not_null(fang, "the Leech Fang effect attaches through the host")
	if fang == null:
		return
	var health: StatusHealthStub = _install_health()
	var target: Node2D = _harness.make_target(HIT_AT)

	# A hit the pipeline never computed a `final_damage` for dealt nothing, so
	# there is nothing to leech and the heal is not even asked for.
	assert_true(_land_hit(target, _player), "a hit whose damage was never computed lands")
	assert_eq(health.heal_calls.size(), 0, "no damage dealt, so no heal is asked for")
	assert_eq(health.current_hp, HEALTH_START, "and the HP does not move")

	var first: HitInfo = _hit(target, _player)
	first.final_damage = LEECH_DAMAGE
	assert_true(_harness.fire(Events.hit_landed, [first]), "a %d-damage hit lands" % LEECH_DAMAGE)
	assert_eq(health.heal_calls.size(), 1, "the holder is healed once")
	assert_eq(health.healed_total, LEECH_HEAL, "for 2% of the damage that landed")
	assert_eq(health.current_hp, HEALTH_START + LEECH_HEAL, "and the HP moves by it")
	assert_eq(fang.heal_requests, [LEECH_HEAL] as Array[int], "the effect's read names the same amount")
	assert_eq(LeechFangEffect.HEAL_FRACTION, 0.02, "the fraction is the design doc's 2%")

	var second: HitInfo = _hit(target, _player)
	second.final_damage = LEECH_DAMAGE / 2
	assert_true(_harness.fire(Events.hit_landed, [second]), "a %d-damage hit lands" % (LEECH_DAMAGE / 2))
	assert_eq(health.healed_total, LEECH_HEAL + LEECH_HEAL_HALF, "half the damage leeches half as much")

	# The heal is the *holder's*: a hit somebody else landed leeches for them.
	var theirs: HitInfo = _hit(target, null)
	theirs.final_damage = LEECH_DAMAGE
	assert_true(_harness.fire(Events.hit_landed, [theirs]), "a team-mate's hit lands")
	assert_eq(health.heal_calls.size(), 2, "and leeches nothing for this player")
	assert_eq(health.healed_total, LEECH_HEAL + LEECH_HEAL_HALF, "their damage heals nobody here")


## Design doc 9.1 no. 14 — "Rune of Ricochet: projectiles bounce to 2 more
## enemies". The projectile's body and its ricochet are combat-core's (Dev A,
## W2-A6), so the case asserts the ask the relic makes of it and the read it
## publishes beside it.
func test_rune_of_ricochet_asks_the_projectile_for_two_more_bounces() -> void:
	var source: RelicData = _source(&"rune_of_ricochet")
	assert_not_null(source, "data/relics/rune_of_ricochet.tres exists and loads")
	if source == null:
		return
	var rune: RuneOfRicochetEffect = _harness.attach(source) as RuneOfRicochetEffect
	assert_not_null(rune, "the Rune of Ricochet effect attaches through the host")
	if rune == null:
		return
	assert_eq(rune.extra_bounces(), RuneOfRicochetEffect.EXTRA_BOUNCES,
		"the read is the number the relic adds, before anything is fired")

	var shot: ProjectileSeamStub = ProjectileSeamStub.make(_harness.root)
	assert_true(_harness.fire(Events.projectile_fired, [_player, shot]), "the holder's shot is fired")
	assert_eq(shot.bounces, [RuneOfRicochetEffect.EXTRA_BOUNCES] as Array[int],
		"the projectile is asked once for 2 more bounces")
	assert_eq(RuneOfRicochetEffect.EXTRA_BOUNCES, 2, "which is the design doc's `2 more`")
	assert_eq(_harness.spawn_count(&"rune_of_ricochet"), 0, "the relic fires nothing of its own")

	# A team-mate's projectile, fired on the same bus, is asked nothing.
	var teammate: Player = _harness.make_player()
	var theirs: ProjectileSeamStub = ProjectileSeamStub.make(_harness.root)
	assert_true(_harness.fire(Events.projectile_fired, [teammate, theirs]), "a team-mate's shot is fired")
	assert_eq(theirs.bounces.size(), 0, "and the relic asks nothing of it")


# --- the "On Kill" pair: one case each ---------------------------------------

## Design doc 9.1 no. 15 — "Volatile Core: enemies explode on death". The blast
## is this lane's own damage, dealt through the same hurtbox seam every relic's
## damage goes through, and it lands on the enemies around the one that died.
func test_volatile_core_explodes_the_enemies_its_holder_kills() -> void:
	var source: RelicData = _source(&"volatile_core")
	assert_not_null(source, "data/relics/volatile_core.tres exists and loads")
	if source == null:
		return
	var core: VolatileCoreEffect = _harness.attach(source) as VolatileCoreEffect
	assert_not_null(core, "the Volatile Core effect attaches through the host")
	if core == null:
		return
	core.fx_scene = _fx_root_scene()
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)
	var near: StatusEnemyStub = _enemy_at(HIT_AT + NEARBY_AT)
	var far: StatusEnemyStub = _enemy_at(OUT_OF_REACH_AT)

	assert_true(_kill(victim, _player), "the holder's kill is announced")
	assert_eq(_harness.spawn_count(&"volatile_core"), 1, "one explosion is spawned")
	var blast: Node = _spawned(&"volatile_core")
	assert_not_null(blast, "and the seam handed one back")
	if blast is Node2D:
		assert_eq((blast as Node2D).global_position, victim.global_position, "where the enemy died")
	assert_eq(_harness.damage_count(near), 1, "the enemy inside the blast takes a hit")
	assert_eq(_harness.damage_total(near), VolatileCoreEffect.EXPLOSION_DAMAGE, "for the blast's damage")
	assert_eq(_harness.damage_count(far), 0, "the enemy outside it takes none")
	assert_eq(_harness.damage_count(victim), 0, "and the dying enemy is not hit by its own explosion")
	var blast_hit: HitInfo = _harness.world.damage_hits(near)[0]
	assert_true(blast_hit.tags.has(&"volatile_core"), "the blast carries the relic's own id")
	assert_eq(blast_hit.proc_depth, 1, "and is one proc link past the kill that caused it")
	assert_eq(int(blast_hit.element), int(HitInfo.Element.FIRE),
		"its element is the fire the design doc's Pyromaniac row gives this relic")


## A kill nobody attributes — a team-mate's, a hazard's — is not this player's
## kill, so nothing explodes and no jar charges.
func test_the_two_on_kill_relics_fire_for_their_holders_kill_and_not_a_teammates() -> void:
	var core: VolatileCoreEffect = _harness.attach(_source(&"volatile_core")) as VolatileCoreEffect
	assert_not_null(core, "Volatile Core attaches")
	if core == null:
		return
	core.fx_scene = _fx_root_scene()
	var jar: SoulJarEffect = _harness.attach(_source(&"soul_jar")) as SoulJarEffect
	assert_not_null(jar, "Soul Jar attaches")
	if jar == null:
		return
	jar.fx_scene = _fx_root_scene()
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)

	# The bus's own emitter: an unattributed kill, the shape a team-mate's is.
	_emitter.emit_enemy_killed()
	assert_eq(_harness.spawn_count(&"volatile_core"), 0, "a team-mate's kill explodes nothing")
	assert_eq(jar.charge(), 0, "and charges nothing")

	assert_true(_kill(victim, _player), "the holder's kill is announced")
	assert_eq(_harness.spawn_count(&"volatile_core"), 1, "Volatile Core explodes for its holder")
	assert_eq(jar.charge(), 1, "and Soul Jar charges a kill")


## The G17 rule against a real relic: Volatile Core's own blast kills the enemy
## beside it, that death is announced on the bus exactly as Dev A's enemy
## announces one — and the blast carries the relic's id, so the relic does not
## react to its own damage (**blocked on Dev A (W4-A4)**: the emitter is the
## enemy's; the hit and the rule are this lane's).
func test_volatile_cores_own_explosion_does_not_retrigger_itself() -> void:
	var source: RelicData = _source(&"volatile_core")
	assert_not_null(source, "data/relics/volatile_core.tres exists and loads")
	if source == null:
		return
	var core: VolatileCoreEffect = _harness.attach(source) as VolatileCoreEffect
	assert_not_null(core, "the Volatile Core effect attaches through the host")
	if core == null:
		return
	core.fx_scene = _fx_root_scene()
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)
	var near: StatusEnemyStub = _enemy_at(HIT_AT + NEARBY_AT)

	assert_true(_kill(victim, _player), "the holder's kill is announced")
	assert_eq(_harness.spawn_count(&"volatile_core"), 1, "the blast is spawned once")
	assert_eq(_harness.damage_count(near), 1, "and hits the enemy beside it")
	var blast_hit: HitInfo = _harness.world.damage_hits(near)[0]

	assert_true(_harness.fire(Events.enemy_killed, [near, blast_hit]),
		"the blast's victim dies in turn, announced as its death would be")
	assert_eq(_harness.spawn_count(&"volatile_core"), 1, "and the relic does not explode again")
	assert_eq(_harness.world.damage_calls.size(), 1, "the chain stops at the blast's own hit")


## Design doc 9.1 no. 16 — "Soul Jar: kills charge a jar, at 20 kills it releases
## a ghost army for 10s". Nineteen kills charge, the twentieth releases, and the
## twenty-first starts the next jar.
func test_soul_jar_charges_a_kill_at_a_time_and_releases_at_twenty() -> void:
	var source: RelicData = _source(&"soul_jar")
	assert_not_null(source, "data/relics/soul_jar.tres exists and loads")
	if source == null:
		return
	var jar: SoulJarEffect = _harness.attach(source) as SoulJarEffect
	assert_not_null(jar, "the Soul Jar effect attaches through the host")
	if jar == null:
		return
	jar.fx_scene = _fx_root_scene()
	assert_eq(SoulJarEffect.SOUL_JAR_KILLS, 20, "the jar holds the design doc's 20 kills")
	assert_eq(jar.charge(), 0, "a fresh jar is empty")
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)

	for n: int in SoulJarEffect.SOUL_JAR_KILLS - 1:
		assert_true(_kill(victim, _player), "kill %d is announced" % (n + 1))
	assert_eq(jar.charge(), SoulJarEffect.SOUL_JAR_KILLS - 1, "19 kills charge the jar 19 times")
	assert_eq(jar.armies_released(), 0, "and nothing is released before the twentieth")
	assert_eq(_harness.spawn_count(&"soul_jar"), 0, "no army yet")

	assert_true(_kill(victim, _player), "the twentieth kill is announced")
	assert_eq(jar.armies_released(), 1, "the jar releases once")
	assert_eq(jar.charge(), 0, "and empties")
	assert_eq(_harness.spawn_count(&"soul_jar"), 1, "one ghost army is spawned")
	var army: Node = _spawned(&"soul_jar")
	assert_not_null(army, "and the seam handed it back")
	if army is Node2D:
		assert_eq((army as Node2D).global_position, _player.global_position, "at the jar's holder")
	var root: RelicFxRootStub = army as RelicFxRootStub
	assert_not_null(root, "the army is the FX root the seam instantiated")
	if root != null:
		assert_almost_eq(root.lifetime_seconds, SoulJarEffect.GHOST_ARMY_SECONDS, EPSILON,
			"armed to stand for the design doc's 10s")
	assert_eq(SoulJarEffect.GHOST_ARMY_SECONDS, 10.0, "which is the design doc's 10s")

	assert_true(_kill(victim, _player), "a twenty-first kill is announced")
	assert_eq(jar.armies_released(), 1, "the jar does not release again on the 21st")
	assert_eq(jar.charge(), 1, "it starts charging the next army instead")


## The batch's stack case: `soul_jar` is the one relic of the pair whose data
## file allows a second copy, and a second copy charges the jar faster — which
## is what makes `max_stacks = 2` visible rather than decorative.
func test_soul_jar_more_copies_charge_the_jar_faster() -> void:
	var source: RelicData = _source(&"soul_jar")
	assert_not_null(source, "data/relics/soul_jar.tres exists and loads")
	if source == null:
		return
	assert_eq(source.max_stacks, int(LATE_BATCH_MAX_STACKS.get(&"soul_jar", 0)),
		"the data file allows the two copies this case holds")
	var jar: SoulJarEffect = _harness.attach(source, 2) as SoulJarEffect
	assert_not_null(jar, "the Soul Jar effect attaches through the host")
	if jar == null:
		return
	jar.fx_scene = _fx_root_scene()
	assert_eq(jar.stacks, 2, "the effect is held twice")
	assert_eq(jar.charge_per_kill(), 2, "each kill charges the jar once per copy")
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)

	for n: int in SoulJarEffect.SOUL_JAR_KILLS / 2 - 1:
		assert_true(_kill(victim, _player), "kill %d is announced" % (n + 1))
	assert_eq(jar.charge(), SoulJarEffect.SOUL_JAR_KILLS - 2, "nine kills charge a two-copy jar eighteen times")
	assert_eq(jar.armies_released(), 0, "and nothing is released yet")

	assert_true(_kill(victim, _player), "the tenth kill is announced")
	assert_eq(jar.armies_released(), 1, "the two-copy jar releases at ten kills, not twenty")
	assert_eq(_harness.spawn_count(&"soul_jar"), 1, "with one ghost army")


# --- the last "On Kill" batch: one case each --------------------------------

## Design doc 9.1 no. 17 — "Bloodthirst: kills give +10% attack speed for 3s
## (stacks 5x)". The relic's own `StatBlock` modifier, on the player, for the
## doc's three seconds, and the doc's five stacks.
func test_bloodthirst_grants_ten_percent_attack_speed_for_three_seconds() -> void:
	var source: RelicData = _source(&"bloodthirst")
	assert_not_null(source, "data/relics/bloodthirst.tres exists and loads")
	if source == null:
		return
	var blood: BloodthirstEffect = _harness.attach(source) as BloodthirstEffect
	assert_not_null(blood, "the Bloodthirst effect attaches through the host")
	if blood == null:
		return
	_seed_attack_speed()
	var base_speed: float = _attack_speed()
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)

	# A kill nobody attributes — a team-mate's, a hazard's — is not this player's.
	_emitter.emit_enemy_killed()
	assert_eq(blood.buff_stacks(), 0, "a kill nobody attributes grants no stack")
	assert_almost_eq(_attack_speed(), base_speed, EPSILON, "and no attack speed")

	assert_true(_kill(victim, _player), "the holder's kill is announced")
	assert_eq(blood.buff_stacks(), 1, "one kill is one stack")
	assert_almost_eq(_attack_speed(), base_speed * (1.0 + BloodthirstEffect.PER_KILL_BONUS), EPSILON,
		"and the kill grants the doc's +10% attack speed")

	var clock: Timer = _timer_for(blood)
	assert_not_null(clock, "the bonus runs on a clock")
	if clock == null:
		return
	assert_almost_eq(clock.wait_time, BloodthirstEffect.BLOODTHIRST_SECONDS, EPSILON,
		"armed with the relic's own three seconds")

	for n: int in BloodthirstEffect.MAX_STACKS - 1:
		assert_true(_kill(victim, _player), "kill %d is announced" % (n + 2))
	assert_eq(blood.buff_stacks(), BloodthirstEffect.MAX_STACKS, "five kills fill the doc's five stacks")
	assert_almost_eq(_attack_speed(), base_speed * (1.0 + BloodthirstEffect.PER_KILL_BONUS * 5.0), EPSILON,
		"which is +50% attack speed")

	assert_true(_kill(victim, _player), "a sixth kill is announced")
	assert_eq(blood.buff_stacks(), BloodthirstEffect.MAX_STACKS, "and the stacks stop at five")
	assert_eq(BloodthirstEffect.MAX_STACKS, 5, "the cap is the design doc's `5x`")

	clock.timeout.emit()
	assert_eq(blood.buff_stacks(), 0, "when the clock runs out the stacks are gone")
	assert_almost_eq(_attack_speed(), base_speed, EPSILON, "and so is the attack speed")

	assert_true(_kill(victim, _player), "a kill after the window lapses is announced")
	assert_eq(blood.buff_stacks(), 1, "and the buff starts again from one stack")


## The batch's third stack case: Bloodthirst's `max_stacks = 5` is what makes a
## second copy of the relic worth holding — each copy adds a stack per kill, so
## five copies fill the doc's five-stack cap in one kill rather than five.
func test_bloodthirst_stacks_five_deep_and_more_copies_fill_it_faster() -> void:
	var source: RelicData = _source(&"bloodthirst")
	assert_not_null(source, "data/relics/bloodthirst.tres exists and loads")
	if source == null:
		return
	assert_eq(source.max_stacks, int(FINAL_BATCH_MAX_STACKS.get(&"bloodthirst", 0)),
		"the data file allows the five copies this case holds")
	var blood: BloodthirstEffect = _harness.attach(source, BloodthirstEffect.MAX_STACKS) as BloodthirstEffect
	assert_not_null(blood, "the Bloodthirst effect attaches through the host")
	if blood == null:
		return
	_seed_attack_speed()
	var base_speed: float = _attack_speed()
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)

	assert_eq(blood.stacks, BloodthirstEffect.MAX_STACKS, "the effect is held five times")
	assert_eq(blood.stacks_per_kill(), BloodthirstEffect.MAX_STACKS, "and each kill grants one stack per copy")

	assert_true(_kill(victim, _player), "one kill is announced")
	assert_eq(blood.buff_stacks(), BloodthirstEffect.MAX_STACKS,
		"which fills the five-stack cap in a single kill")
	assert_almost_eq(_attack_speed(), base_speed * (1.0 + BloodthirstEffect.PER_KILL_BONUS * 5.0), EPSILON,
		"with the doc's +50% at the cap")

	assert_true(_harness.detach(source), "the relic detaches")
	assert_almost_eq(_attack_speed(), base_speed, EPSILON, "and its buff leaves with it")


## Design doc 9.1 no. 18 — "Corpse Bloom: dead enemies sprout healing flowers".
## The flower is a spawned FX-with-gameplay root, so the case asserts the spawn,
## where it lands and that the corpse sprouts exactly one — the flower's healing
## is the root's own body (**blocked on Dev A (W4-A4)** / art-audio).
func test_corpse_bloom_sprouts_a_flower_where_the_enemy_died() -> void:
	var source: RelicData = _source(&"corpse_bloom")
	assert_not_null(source, "data/relics/corpse_bloom.tres exists and loads")
	if source == null:
		return
	var bloom: CorpseBloomEffect = _harness.attach(source) as CorpseBloomEffect
	assert_not_null(bloom, "the Corpse Bloom effect attaches through the host")
	if bloom == null:
		return
	bloom.fx_scene = _fx_root_scene()
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)

	_emitter.emit_enemy_killed()
	assert_eq(bloom.flowers_planted(), 0, "a kill nobody attributes sprouts nothing")
	assert_eq(_harness.spawn_count(&"corpse_bloom"), 0, "and spawns nothing")

	assert_true(_kill(victim, _player), "the holder's kill is announced")
	assert_eq(bloom.flowers_planted(), 1, "the corpse sprouts one flower")
	assert_eq(_harness.spawn_count(&"corpse_bloom"), 1, "which is one spawn, attributed to the relic")
	var flower: Node = _spawned(&"corpse_bloom")
	assert_not_null(flower, "and the seam handed it back")
	if flower is Node2D:
		assert_eq((flower as Node2D).global_position, victim.global_position, "where the enemy died")
	var root: RelicFxRootStub = flower as RelicFxRootStub
	assert_not_null(root, "the flower is the FX root the seam instantiated")
	if root != null:
		# The doc states no number for what a flower heals, so this lane asks the
		# root for no contract it has not chosen a shape for: the flower is
		# spawned, and the healing inside it is the root's own body
		# (**blocked on Dev A (W4-A4)**).
		assert_false(root.armed, "the flower is spawned, not armed by this relic")

	assert_true(_kill(victim, _player), "a second kill is announced")
	assert_eq(bloom.flowers_planted(), 2, "and a second corpse sprouts its own flower")
	assert_eq(_harness.spawn_count(&"corpse_bloom"), 2, "one flower per death, not one for the batch")


## Design doc 9.1 no. 19 — "Domino: killing an enemy with a status effect spreads
## it to nearby enemies". The corpse's own statuses, with the stacks they were
## held at, reach every enemy inside `SPREAD_RADIUS` and nothing outside it. The
## read is the enemy's `StatusEffects` component — stats-status's own, composed
## onto the enemy by Dev A's enemy scene (**blocked on Dev A (W4-A1)**) — driven
## here through the recording double.
func test_domino_spreads_the_corpses_statuses_to_the_enemies_beside_it() -> void:
	var source: RelicData = _source(&"domino")
	assert_not_null(source, "data/relics/domino.tres exists and loads")
	if source == null:
		return
	var domino: DominoEffect = _harness.attach(source) as DominoEffect
	assert_not_null(domino, "the Domino effect attaches through the host")
	if domino == null:
		return
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)
	var near: StatusEnemyStub = _enemy_at(HIT_AT + NEARBY_AT)
	var far: StatusEnemyStub = _enemy_at(OUT_OF_REACH_AT)
	var victim_statuses: StatusEffectsStub = _install_statuses(victim)
	var near_statuses: StatusEffectsStub = _install_statuses(near)
	var far_statuses: StatusEffectsStub = _install_statuses(far)

	# A corpse with nothing on it spreads nothing: the doc's trigger is "killing
	# an enemy *with a status effect*".
	assert_true(_kill(victim, _player), "the holder's unattributed-status kill is announced")
	assert_eq(domino.spread_count(), 0, "a corpse with no status spreads nothing")
	assert_eq(near_statuses.applications.size(), 0, "and nothing arrives at the enemy beside it")

	victim_statuses.apply_status(int(StatusEffects.Status.BURN), 3, _player)
	victim_statuses.apply_status(int(StatusEffects.Status.TOXIN), 1, _player)
	assert_true(_kill(victim, _player), "the holder's kill of the burning, toxined enemy is announced")

	assert_eq(domino.spread_count(), 2, "both of the corpse's statuses are spread")
	assert_eq(near_statuses.applications.size(), 2, "and both arrive at the enemy beside it")
	assert_eq(near_statuses.stacks(int(StatusEffects.Status.BURN)), 3,
		"the burn arrives with the stacks the corpse held it at")
	assert_eq(near_statuses.stacks(int(StatusEffects.Status.TOXIN)), 1, "and so does the toxin")
	assert_eq(far_statuses.applications.size(), 0, "an enemy outside the spread is untouched")
	assert_eq(DominoEffect.SPREAD_RADIUS, 96.0, "the spread reaches SHOCK's own chain radius")

	# A kill attributed to nobody is not this player's kill.
	_emitter.emit_enemy_killed()
	assert_eq(domino.spread_count(), 2, "a kill nobody attributes spreads nothing")


## Design doc 9.1 no. 20 — "Trophy Belt: every elite killed gives +3% damage for
## the rest of the run". SPEC-enemies-ai names the signal this relic hangs off:
## "Elite death emits `Events.elite_killed` … and Trophy Belt".
func test_trophy_belt_grants_damage_for_every_elite_its_holder_kills() -> void:
	var source: RelicData = _source(&"trophy_belt")
	assert_not_null(source, "data/relics/trophy_belt.tres exists and loads")
	if source == null:
		return
	var belt: TrophyBeltEffect = _harness.attach(source) as TrophyBeltEffect
	assert_not_null(belt, "the Trophy Belt effect attaches through the host")
	if belt == null:
		return
	var base_damage: float = _attack()
	var elite: StatusEnemyStub = _enemy_at(HIT_AT)
	var teammate: Player = _harness.make_player()

	# The bus's own emitter: an unattributed elite death and a team-mate's, the
	# two shapes that must not count for this player.
	_emitter.emit_elite_killed()
	assert_eq(belt.elites_killed(), 0, "an elite nobody attributes gives nothing")
	assert_almost_eq(_attack(), base_damage, EPSILON, "and no damage")

	assert_true(_elite_kill(elite, teammate), "a team-mate's elite kill is announced")
	assert_eq(belt.elites_killed(), 0, "which is not this player's either")

	assert_true(_elite_kill(elite, _player), "the holder's elite kill is announced")
	assert_eq(belt.elites_killed(), 1, "the belt counts it")
	assert_almost_eq(_attack(), base_damage * (1.0 + TrophyBeltEffect.PER_ELITE_BONUS), EPSILON,
		"and gives the doc's +3% damage")

	# A plain kill is not an elite kill: only the elites the doc names count.
	assert_true(_kill(elite, _player), "an ordinary kill is announced")
	assert_eq(belt.elites_killed(), 1, "and the belt does not count it")


## The batch's fourth stack case: Trophy Belt's bonus is an accumulation, one
## +3% per elite for the **rest of the run** — it survives the rooms and floors
## that follow and is only taken back with the relic itself.
func test_trophy_belt_stacks_its_damage_bonus_for_the_rest_of_the_run() -> void:
	var source: RelicData = _source(&"trophy_belt")
	assert_not_null(source, "data/relics/trophy_belt.tres exists and loads")
	if source == null:
		return
	var belt: TrophyBeltEffect = _harness.attach(source) as TrophyBeltEffect
	assert_not_null(belt, "the Trophy Belt effect attaches through the host")
	if belt == null:
		return
	var base_damage: float = _attack()
	var first: StatusEnemyStub = _enemy_at(HIT_AT)
	var second: StatusEnemyStub = _enemy_at(HIT_AT + NEARBY_AT)
	var third: StatusEnemyStub = _enemy_at(OUT_OF_REACH_AT)

	assert_true(_elite_kill(first, _player), "the first elite kill is announced")
	assert_true(_elite_kill(second, _player), "a second elite kill is announced")
	assert_eq(belt.elites_killed(), 2, "two elites are counted")
	assert_almost_eq(belt.damage_bonus(), 2.0 * TrophyBeltEffect.PER_ELITE_BONUS, EPSILON,
		"and the two are +6% damage")

	# The rest of the run, not the room: the next room and the next floor leave
	# the accumulation alone (nothing here is `once_per_room`).
	_emitter.emit_room_entered()
	_emitter.emit_floor_entered()
	assert_almost_eq(_attack(), base_damage * (1.0 + 2.0 * TrophyBeltEffect.PER_ELITE_BONUS), EPSILON,
		"and it stands across rooms and floors within the run")

	assert_true(_elite_kill(third, _player), "a third elite kill is announced")
	assert_eq(belt.elites_killed(), 3, "three elites are counted")
	assert_almost_eq(_attack(), base_damage * (1.0 + 3.0 * TrophyBeltEffect.PER_ELITE_BONUS), EPSILON,
		"which is +9% damage and no cap")

	assert_true(_harness.detach(source), "the relic detaches")
	assert_almost_eq(_attack(), base_damage, EPSILON, "and the run's accumulated bonus goes with it")


## The four are On Kill relics, and the batch's signal rule is one signal each:
## Bloodthirst, Corpse Bloom and Domino hang off `enemy_killed` (every death is
## announced there — SPEC-enemies-ai's "Events emitted" list carries it), and
## Trophy Belt alone off the `elite_killed` the same spec names it for. So one
## kill the holder made moves all four, a kill attributed to nobody moves none,
## and a death announced on *both* signals — which is what an elite's is — is
## still one death: the case fires `_kill()` and `_elite_kill()` for the same
## corpse and asserts each relic counted it exactly once. `EventEmitterHelper` is
## the bus's own emitter, whose hits carry no `owner_player`.
func test_the_four_final_on_kill_relics_fire_for_their_holders_kill_and_not_a_teammates() -> void:
	var blood: BloodthirstEffect = _harness.attach(_source(&"bloodthirst")) as BloodthirstEffect
	assert_not_null(blood, "Bloodthirst attaches")
	if blood == null:
		return
	var bloom: CorpseBloomEffect = _harness.attach(_source(&"corpse_bloom")) as CorpseBloomEffect
	assert_not_null(bloom, "Corpse Bloom attaches")
	if bloom == null:
		return
	var domino: DominoEffect = _harness.attach(_source(&"domino")) as DominoEffect
	assert_not_null(domino, "Domino attaches")
	if domino == null:
		return
	var belt: TrophyBeltEffect = _harness.attach(_source(&"trophy_belt")) as TrophyBeltEffect
	assert_not_null(belt, "Trophy Belt attaches")
	if belt == null:
		return
	bloom.fx_scene = _fx_root_scene()
	_seed_attack_speed()
	var base_speed: float = _attack_speed()
	var base_damage: float = _attack()
	var victim: StatusEnemyStub = _enemy_at(HIT_AT)
	var near: StatusEnemyStub = _enemy_at(HIT_AT + NEARBY_AT)
	_install_statuses(victim)
	_install_statuses(near)
	var victim_statuses: StatusEffectsStub = _install_statuses(victim)
	victim_statuses.apply_status(int(StatusEffects.Status.BURN), 1, _player)

	_emitter.emit_enemy_killed()
	_emitter.emit_elite_killed()
	assert_eq(blood.buff_stacks(), 0, "a kill nobody attributes grants Bloodthirst nothing")
	assert_eq(bloom.flowers_planted(), 0, "sprouts Corpse Bloom nothing")
	assert_eq(domino.spread_count(), 0, "spreads Domino nothing")
	assert_eq(belt.elites_killed(), 0, "and counts Trophy Belt nothing")

	assert_true(_kill(victim, _player), "the holder's kill is announced")
	assert_true(_elite_kill(victim, _player), "and the holder's elite kill is announced")
	assert_eq(blood.buff_stacks(), 1, "Bloodthirst counts that death once, on the kill signal")
	assert_eq(bloom.flowers_planted(), 1, "Corpse Bloom plants one flower for it")
	assert_eq(domino.spread_count(), 1, "Domino spreads the corpse's status once")
	assert_eq(belt.elites_killed(), 1, "and Trophy Belt counts the elite, on its own signal")
	assert_almost_eq(_attack_speed(), base_speed * (1.0 + BloodthirstEffect.PER_KILL_BONUS), EPSILON,
		"the buff landed on the player's own StatBlock")
	assert_almost_eq(_attack(), base_damage * (1.0 + TrophyBeltEffect.PER_ELITE_BONUS), EPSILON,
		"and so did the belt's damage")


## The three are On Hit relics like G6's five: one hit the holder landed moves all
## three, and the same hit attributed to anybody else moves none. The negative
## control is `EventEmitterHelper` again — the bus's own emitter, whose hit carries
## no `owner_player` — read on this batch's own three tells: no pull asked, no heal
## asked, no bounce asked.
func test_the_three_later_on_hit_relics_fire_for_their_own_players_hit_and_none_for_a_teammates() -> void:
	for relic_id: StringName in ON_HIT_TAIL_IDS:
		assert_not_null(_attach(relic_id), "%s attaches" % relic_id)
	var health: StatusHealthStub = _install_health()
	var target: StatusEnemyStub = _enemy_at(HIT_AT)
	var near: StatusEnemyStub = _enemy_at(HIT_AT + NEARBY_AT)
	var shot: ProjectileSeamStub = ProjectileSeamStub.make(_harness.root)
	var teammate: Player = _harness.make_player()
	var theirs: ProjectileSeamStub = ProjectileSeamStub.make(_harness.root)

	# A teammate's hit on the bus's own emitter, and a teammate's shot: neither
	# moves anything this player holds.
	_emitter.emit_hit_landed()
	assert_true(_harness.fire(Events.projectile_fired, [teammate, theirs]), "a team-mate's shot is fired")
	assert_eq(near.pulls.size(), 0, "a teammate's hit pulls nobody for this player")
	assert_eq(health.heal_calls.size(), 0, "and leeches nothing for them")
	assert_eq(theirs.bounces.size(), 0, "and their shot is asked for no bounce")

	# The holder's own hit and shot, and all three react.
	var mine: HitInfo = _hit(target, _player)
	mine.final_damage = LEECH_DAMAGE
	assert_true(_harness.fire(Events.hit_landed, [mine]), "the holder's hit lands")
	assert_true(_harness.fire(Events.projectile_fired, [_player, shot]), "the holder's shot is fired")
	assert_eq(near.pulls.size(), 1, "Gravity Stone pulls from that one hit")
	assert_eq(health.healed_total, LEECH_HEAL, "Leech Fang heals from it")
	assert_eq(shot.bounces, [RuneOfRicochetEffect.EXTRA_BOUNCES] as Array[int],
		"Rune of Ricochet asks for its bounces")


# --- the data: the second On Hit batch and the On Kill pair -----------------

## One relic against the design doc clause it was copied from: the id being its
## file name, the name, the sentence its description contains, its kind, its stack
## rule, its tags from the vocabulary with the trigger's own on it, and — where it
## has an element — the element tag first, which is what SPEC-art-audio's
## `relic_proc_<tag>` rule turns into the proc it names.
func _check_clause_relic(
	relic_id: StringName,
	expected: Dictionary,
	stack_rules: Dictionary[StringName, int],
	element_tags: Dictionary[StringName, StringName],
	trigger_tag: StringName,
) -> void:
	var data: RelicData = _source(relic_id)
	assert_not_null(data, "%s.tres loads as a RelicData" % relic_id)
	if data == null:
		return
	assert_eq(String(data.id), String(relic_id), "the id is the file name")
	assert_eq(String(data.display_name), String(expected["name"]), "%s is the design doc's name" % relic_id)
	var sentence: String = String(expected["text"]).to_lower()
	assert_true(String(data.description).to_lower().contains(sentence),
		"%s's description is the design doc's sentence (%s)" % [relic_id, sentence])
	assert_eq(data.kind, RelicData.Kind.PASSIVE, "%s is a passive relic" % relic_id)
	assert_eq(data.max_stacks, int(stack_rules.get(relic_id, 0)),
		"%s's stack rule is the batch's own" % relic_id)
	assert_between(data.tags.size(), 1, 2, "%s carries 1 to 2 tags" % relic_id)
	assert_true(data.tags.has(trigger_tag), "%s carries the %s tag its trigger gives it" % [relic_id, trigger_tag])
	for tag: StringName in data.tags:
		assert_true(Tags.is_valid(tag), "%s's tag `%s` is in the vocabulary" % [relic_id, tag])
	if element_tags.has(relic_id):
		assert_eq(data.tags[0], element_tags[relic_id],
			"%s's element tag comes first, so its proc id is the element's" % relic_id)
	# SPEC-art-audio: "relic_proc_<tag> (one per relic tag)" — the proc a relic
	# plays is named for the first tag it carries.
	if not data.tags.is_empty():
		assert_eq(String(data.vfx_id), "relic_proc_%s" % data.tags[0],
			"%s names SPEC-art-audio's proc id for its own tag" % relic_id)


## Criterion 1 read against the document it was copied from, for design doc 9.1
## nos. 12 to 14, parsed out of `SINKHOLE_SPEC.md` at run time rather than restated.
func test_the_three_on_hit_tail_data_files_are_the_design_docs_own_text() -> void:
	var clauses: Dictionary = _on_hit_tail_clauses()
	assert_eq(clauses.size(), ON_HIT_TAIL_COUNT, "design doc 9.1 nos. 12 to 14 parse out of the document")

	var art_spec: String = FileAccess.get_file_as_string(ART_SPEC_PATH)
	assert_true(art_spec.contains("relic_proc_<tag>"), "SPEC-art-audio states the relic proc id rule")

	for number: int in range(ON_HIT_TAIL_FIRST_NUMBER, ON_HIT_TAIL_FIRST_NUMBER + ON_HIT_TAIL_COUNT):
		var expected: Dictionary = clauses.get(number, {}) as Dictionary
		assert_false(expected.is_empty(), "design doc 9.1 no. %d was read" % number)
		if expected.is_empty():
			continue
		var relic_id: StringName = _id_from_display_name(String(expected["name"]))
		assert_eq(ON_HIT_TAIL_IDS[number - ON_HIT_TAIL_FIRST_NUMBER], relic_id,
			"no. %d is %s in the batch order" % [number, relic_id])
		_check_clause_relic(relic_id, expected, LATE_BATCH_MAX_STACKS, LATE_BATCH_ELEMENT_TAGS, Tags.ON_HIT)


## The same read for the On Kill pair, design doc 9.1 nos. 15 and 16 — the first
## relics of the batch that hang off `enemy_killed` rather than `hit_landed`, which
## is what the `on_kill` tag on both of them says.
func test_the_two_on_kill_data_files_are_the_design_docs_own_text() -> void:
	var clauses: Dictionary = _on_kill_clauses()
	assert_eq(clauses.size(), ON_KILL_COUNT, "design doc 9.1 nos. 15 and 16 parse out of the document")

	for number: int in range(ON_KILL_FIRST_NUMBER, ON_KILL_FIRST_NUMBER + ON_KILL_COUNT):
		var expected: Dictionary = clauses.get(number, {}) as Dictionary
		assert_false(expected.is_empty(), "design doc 9.1 no. %d was read" % number)
		if expected.is_empty():
			continue
		var relic_id: StringName = _id_from_display_name(String(expected["name"]))
		assert_eq(ON_KILL_IDS[number - ON_KILL_FIRST_NUMBER], relic_id,
			"no. %d is %s in the batch order" % [number, relic_id])
		_check_clause_relic(relic_id, expected, LATE_BATCH_MAX_STACKS, LATE_BATCH_ELEMENT_TAGS, Tags.ON_KILL)


## The same read for the last On Kill batch, design doc 9.1 nos. 17 to 20 — the
## four relics that close the week's twenty, all of them on `enemy_killed`'s
## trigger (the `on_kill` tag on every one of them).
func test_the_final_batch_data_files_are_the_design_docs_own_text() -> void:
	var clauses: Dictionary = _final_batch_clauses()
	assert_eq(clauses.size(), FINAL_BATCH_COUNT, "design doc 9.1 nos. 17 to 20 parse out of the document")

	for number: int in range(FINAL_BATCH_FIRST_NUMBER, FINAL_BATCH_FIRST_NUMBER + FINAL_BATCH_COUNT):
		var expected: Dictionary = clauses.get(number, {}) as Dictionary
		assert_false(expected.is_empty(), "design doc 9.1 no. %d was read" % number)
		if expected.is_empty():
			continue
		var relic_id: StringName = _id_from_display_name(String(expected["name"]))
		assert_eq(FINAL_BATCH_IDS[number - FINAL_BATCH_FIRST_NUMBER], relic_id,
			"no. %d is %s in the batch order" % [number, relic_id])
		_check_clause_relic(relic_id, expected, FINAL_BATCH_MAX_STACKS, FINAL_BATCH_ELEMENT_TAGS, Tags.ON_KILL)


## The numbers the last batch's descriptions state are the effect scripts'
## constants, read out of the scripts rather than restated here — Bloodthirst's
## "10%", "3s" and "5x" and Trophy Belt's "3%".
func test_the_final_batch_descriptions_numbers_are_the_effect_scripts_constants() -> void:
	for link: Dictionary in FINAL_BATCH_NUMBER_LINKS:
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


## The numbers these five descriptions state are the effect scripts' constants,
## read out of the scripts rather than restated here — "2%", "2 more", "20", "10s".
## The two On Kill relics share a data file each and both are read through the same
## table, so a description that drifts from its script fails on the pair of them.
func test_the_late_batch_descriptions_numbers_are_the_effect_scripts_constants() -> void:
	for link: Dictionary in LATE_BATCH_NUMBER_LINKS:
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
