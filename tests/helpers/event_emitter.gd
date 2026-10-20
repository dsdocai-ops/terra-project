class_name EventEmitterHelper
extends RefCounted
## The test-only `Events` emitter: one named method per signal on the bus, each
## emitting that signal with valid fake arguments built from the `tests/helpers/`
## doubles, so an effect that listens to an event can be exercised before the
## module that owns the event exists.
##
## `Events` is emitted in production by the owning modules (SPEC-effect-system
## "Events bus"). Dev B's own emitters land across W4-B4/B5/B8/B9 and are wired
## where they belong: `GameState` emits `run_started`/`run_ended` and counts
## `room_cleared`, `NetworkManager` emits `player_downed`/`player_revived`,
## `StoryManager` emits the story signals. Dev A's production emitters are
## combat-core's W4-A4, and the nine signals that task names are still pending:
##
##   hit_landed          blocked on Dev A (W4-A4)
##   crit_landed         blocked on Dev A (W4-A4)
##   player_damaged      blocked on Dev A (W4-A4)
##   heavy_attack_released  blocked on Dev A (W4-A4)
##   weapon_swapped      blocked on Dev A (W4-A4)
##   projectile_fired    blocked on Dev A (W4-A4)
##   enemy_killed        blocked on Dev A (W4-A4)
##   enemy_spawned       blocked on Dev A (W4-A4)
##   player_dodged       blocked on Dev A (W4-A4)
##
## The rest are Dev B's or later-week tasks: `Room`/floor events wait on
## floor-generation (W3-A2), the ability/ascension signals on weeks 5 to 7, and
## the loot signals on W4-B5/B8. Until each lands, this helper is their emitter
## — which is exactly what the W4-B6 relic harness needs, and what
## `tests/unit/test_events_emitters.gd` checks signal by signal against the
## spec's table.
##
## Usage:
##   var emitter := EventEmitterHelper.new()
##   Events.hit_landed.connect(_on_hit)      # a named method, never a lambda
##   emitter.emit_hit_landed()
##   emitter.cleanup()                        # in after_each — frees the doubles
##
## Call `cleanup()` in `after_each`: every node the helper created to carry an
## argument is freed there, so no `Player` or stub outlives the test.
##
## Owned by tests (effect-system). Sync: none. A test double — its arguments are
## built locally and never replicated.


## Every signal on the bus, in the order `SPEC-effect-system.md` "Events bus"
## lists them. `tests/unit/test_events_emitters.gd` asserts this set equals the
## spec's, so a signal added to the bus without an emitter here fails the suite.
const SIGNAL_NAMES: Array[StringName] = [
	# combat (combat-core)
	&"hit_landed",
	&"crit_landed",
	&"player_damaged",
	&"player_healed",
	&"heavy_attack_released",
	&"weapon_swapped",
	&"projectile_fired",
	# movement (player-controller)
	&"player_dodged",
	&"player_downed",
	&"player_revived",
	&"player_died",
	# enemies (enemies-ai)
	&"enemy_spawned",
	&"enemy_killed",
	&"elite_killed",
	&"boss_defeated",
	# status (stats-status)
	&"status_applied",
	&"combo_triggered",
	# abilities (abilities)
	&"ability_cast",
	&"ultimate_used",
	&"class_skill_used",
	# rooms and run (floor-generation, run-economy)
	&"room_entered",
	&"room_cleared",
	&"floor_entered",
	&"floor_cleared",
	&"run_started",
	&"run_ended",
	&"rope_vote_updated",
	# loot (run-economy, relics, weapons, abilities)
	&"currency_gained",
	&"pickup_collected",
	&"relic_picked",
	&"relic_removed",
	&"synergy_activated",
	&"mutation_applied",
	&"ascension_chosen",
	# story (story-dialogue)
	&"story_flag_set",
	&"lore_unlocked",
	&"miner_rescued",
]

## The nine signals whose production emitter is Dev A's W4-A4 (combat-core).
const DEV_A_OWNED: Array[StringName] = [
	&"hit_landed",
	&"crit_landed",
	&"player_damaged",
	&"heavy_attack_released",
	&"weapon_swapped",
	&"projectile_fired",
	&"enemy_killed",
	&"enemy_spawned",
	&"player_dodged",
]

## The peer id the fake players carry, and the one the "reviver" carries.
const FAKE_PEER_ID: int = 1
const FAKE_REVIVER_PEER_ID: int = 2
## The fake floor / seed / amount values every emitter uses. They are plausible
## rather than meaningful: nothing in the bus reads them.
const FAKE_FLOOR: int = 2
const FAKE_SEED: int = 4242
const FAKE_BOSS_ID: StringName = &"grub_queen"
const FAKE_CURRENCY: StringName = &"gold"
const FAKE_CURRENCY_AMOUNT: int = 5
const FAKE_STATUS_STACKS: int = 2
const FAKE_HIT_BASE_DAMAGE: float = 10.0

## Nodes this helper created to carry an argument. Freed by `cleanup()`.
var _nodes: Array[Node] = []


## Frees every double this helper built. Call it from `after_each`.
func cleanup() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


## Every signal on the bus, as a copy so a caller cannot mutate the table.
static func all_signal_names() -> Array[StringName]:
	return SIGNAL_NAMES.duplicate()


## The nine signals W4-A4 owns, as a copy.
static func dev_a_owned_signals() -> Array[StringName]:
	return DEV_A_OWNED.duplicate()


## The named emitter method for one signal: `emit_hit_landed` for `hit_landed`.
static func emitter_method_name(signal_name: StringName) -> StringName:
	return StringName("emit_%s" % signal_name)


## A `Callable` for the named emitter method, so a test can drive an emitter
## without writing the method name as a literal. Returns an invalid `Callable`
## (and warns) for a name that is not a bus signal.
func callable_for(signal_name: StringName) -> Callable:
	var method: StringName = emitter_method_name(signal_name)
	if not SIGNAL_NAMES.has(signal_name) or not has_method(method):
		push_warning("[emitter] %s is not an Events signal" % signal_name)
		return Callable()
	return Callable(self, method)


# --- combat (combat-core) ---------------------------------------------------

func emit_hit_landed() -> void:
	Events.hit_landed.emit(_hit())


func emit_crit_landed() -> void:
	Events.crit_landed.emit(_hit())


func emit_player_damaged() -> void:
	Events.player_damaged.emit(_player(FAKE_PEER_ID), _hit())


func emit_player_healed() -> void:
	Events.player_healed.emit(_player(FAKE_PEER_ID), FAKE_CURRENCY_AMOUNT, _node(&"source"))


func emit_heavy_attack_released() -> void:
	Events.heavy_attack_released.emit(_player(FAKE_PEER_ID), 0.75)


func emit_weapon_swapped() -> void:
	Events.weapon_swapped.emit(_player(FAKE_PEER_ID), 1)


func emit_projectile_fired() -> void:
	Events.projectile_fired.emit(_player(FAKE_PEER_ID), _node(&"projectile"))


# --- movement (player-controller) -------------------------------------------

func emit_player_dodged() -> void:
	Events.player_dodged.emit(_player(FAKE_PEER_ID), true)


func emit_player_downed() -> void:
	Events.player_downed.emit(_player(FAKE_PEER_ID))


func emit_player_revived() -> void:
	Events.player_revived.emit(_player(FAKE_PEER_ID), _player(FAKE_REVIVER_PEER_ID))


func emit_player_died() -> void:
	Events.player_died.emit(_player(FAKE_PEER_ID))


# --- enemies (enemies-ai) ---------------------------------------------------

func emit_enemy_spawned() -> void:
	Events.enemy_spawned.emit(_enemy())


func emit_enemy_killed() -> void:
	Events.enemy_killed.emit(_enemy(), _hit())


func emit_elite_killed() -> void:
	var enemy: EnemyBaseStub = _enemy()
	enemy.elite = true
	Events.elite_killed.emit(enemy, _hit())


func emit_boss_defeated() -> void:
	Events.boss_defeated.emit(FAKE_BOSS_ID)


# --- status (stats-status) --------------------------------------------------

func emit_status_applied() -> void:
	# `status` and `combo` are declared `int` until StatusEffects and Combos
	# land (W4-B4); 0 is the first enum row, which is what the placeholder type
	# can carry today.
	Events.status_applied.emit(_enemy(), 0, FAKE_STATUS_STACKS, _node(&"source"))


func emit_combo_triggered() -> void:
	Events.combo_triggered.emit(_enemy(), 0, _node(&"source"))


# --- abilities (abilities) --------------------------------------------------

func emit_ability_cast() -> void:
	Events.ability_cast.emit(_player(FAKE_PEER_ID), _resource(&"ability"), 1)


func emit_ultimate_used() -> void:
	Events.ultimate_used.emit(_player(FAKE_PEER_ID), _resource(&"ultimate"))


func emit_class_skill_used() -> void:
	Events.class_skill_used.emit(_player(FAKE_PEER_ID))


# --- rooms and run (floor-generation, run-economy) --------------------------

func emit_room_entered() -> void:
	Events.room_entered.emit(_node(&"room"), _player(FAKE_PEER_ID))


func emit_room_cleared() -> void:
	Events.room_cleared.emit(_node(&"room"))


func emit_floor_entered() -> void:
	Events.floor_entered.emit(FAKE_FLOOR)


func emit_floor_cleared() -> void:
	Events.floor_cleared.emit(FAKE_FLOOR)


func emit_run_started() -> void:
	Events.run_started.emit(FAKE_SEED)


func emit_run_ended() -> void:
	Events.run_ended.emit(RunResult.new(RunEndReason.Reason.ABORT, FAKE_SEED, FAKE_FLOOR - 1))


func emit_rope_vote_updated() -> void:
	var votes: Dictionary = {FAKE_PEER_ID: true, FAKE_REVIVER_PEER_ID: false}
	Events.rope_vote_updated.emit(votes)


# --- loot (run-economy, relics, weapons, abilities) -------------------------

func emit_currency_gained() -> void:
	Events.currency_gained.emit(_player(FAKE_PEER_ID), FAKE_CURRENCY, FAKE_CURRENCY_AMOUNT)


func emit_pickup_collected() -> void:
	Events.pickup_collected.emit(_player(FAKE_PEER_ID), _node(&"pickup"))


func emit_relic_picked() -> void:
	Events.relic_picked.emit(_player(FAKE_PEER_ID), _resource(&"relic"))


func emit_relic_removed() -> void:
	Events.relic_removed.emit(_player(FAKE_PEER_ID), _resource(&"relic"))


func emit_synergy_activated() -> void:
	Events.synergy_activated.emit(_player(FAKE_PEER_ID), _resource(&"synergy"))


func emit_mutation_applied() -> void:
	Events.mutation_applied.emit(
		_player(FAKE_PEER_ID), _resource(&"weapon"), _resource(&"mutation")
	)


func emit_ascension_chosen() -> void:
	Events.ascension_chosen.emit(_player(FAKE_PEER_ID), _resource(&"ascension"), 1)


# --- story (story-dialogue) -------------------------------------------------

func emit_story_flag_set() -> void:
	Events.story_flag_set.emit(&"met_the_miner")


func emit_lore_unlocked() -> void:
	Events.lore_unlocked.emit(&"page_sinkhole_01")


func emit_miner_rescued() -> void:
	Events.miner_rescued.emit(&"miner_01")


# --- fake arguments ---------------------------------------------------------

## A bare `Player.new()` that is never added to the tree, so Dev A's `_ready`
## never runs — the double shape test_run_end_defeat.gd established.
func _player(peer_id: int) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	_nodes.append(player)
	return player


## An `EnemyBaseStub` — the W2-B3 double, reused so the enemy argument matches
## the node shape specs/enemies-ai describes (`elite`, `current_hp`).
func _enemy() -> EnemyBaseStub:
	var enemy: EnemyBaseStub = EnemyBaseStub.new()
	_nodes.append(enemy)
	return enemy


func _node(kind: StringName) -> Node:
	var stub: EventEmitterNodeStub = EventEmitterNodeStub.new()
	stub.stub_kind = kind
	stub.name = String(kind)
	_nodes.append(stub)
	return stub


## A plain Resource carrying a name, standing in for the RelicData /
## SynergyData / AbilityData / WeaponData / MutationData / AscensionData
## Resources their owning modules define later. A preset (not generated) change
## of `resource_name` keeps this a pure test double.
func _resource(kind: StringName) -> Resource:
	var res: Resource = Resource.new()
	res.resource_name = String(kind)
	return res


func _hit() -> HitData:
	var hit: HitData = HitData.new()
	hit.base_damage = FAKE_HIT_BASE_DAMAGE
	hit.tags = [&"emitter"] as Array[StringName]
	return hit
