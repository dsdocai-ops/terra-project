extends Node
## Global signal bus. Owned by effect-system. Signals only, no logic.
## Sync: emitted on the host where gameplay runs; the presentation signals
## (hit_landed, enemy_killed, relic_picked, room_cleared, currency_gained)
## are also emitted on clients from replicated state. See SPEC-effect-system
## for who emits what. Adding or changing a signal is "Ask first".
##
## The signal set, the parameter names and the parameter types below are the
## table in SPEC-effect-system "Events bus", and are enforced by
## tests/unit/test_events_bus.gd against that document at run time.
##
## Parameter types use the nearest existing class until the owning module
## defines the real one. Where the real class already exists the signal names
## it (`HitInfo` is combat-core's, `RunResult` is run-economy's).
## Every remaining placeholder carries exactly one pinned line below, naming
## the class that replaces it and the module that owns that class; the test
## fails if a placeholder loses its line or a line loses its owner.
## TODO(combat-core): Projectile <- Node (blocked on Dev A, W2-A6)
## TODO(enemies-ai): Enemy <- Node (blocked on Dev A, W2-A9)
## TODO(floor-generation): Room <- Node (blocked on Dev A, W3-A2)
## TODO(relics): SynergyData <- Resource (blocked on Dev B, W4-B5)
## TODO(weapons): WeaponData <- Resource (blocked on Dev A, W2-A7)
## TODO(weapons): MutationData <- Resource (blocked on Dev A, W7-A3)
## TODO(abilities): AbilityData <- Resource (blocked on Dev A, W5-A1)
## TODO(classes-characters): AscensionData <- Resource (blocked on Dev A, W5-A4)
## TODO(stats-status): StatusEffects.Status <- int (blocked on Dev B, W4-B4)

# combat (combat-core)
signal hit_landed(hit: HitInfo)
signal crit_landed(hit: HitInfo)
signal player_damaged(player: Player, hit: HitInfo)
signal player_healed(player: Player, amount: int, source: Node)
signal heavy_attack_released(player: Player, charge: float)
signal weapon_swapped(player: Player, slot: int)
signal projectile_fired(player: Player, projectile: Node)
# movement (player-controller)
signal player_dodged(player: Player, perfect: bool)
signal player_downed(player: Player)
signal player_revived(player: Player, by: Player)
signal player_died(player: Player)
# enemies (enemies-ai)
signal enemy_spawned(enemy: Node)
signal enemy_killed(enemy: Node, hit: HitInfo)
signal elite_killed(enemy: Node, hit: HitInfo)
signal boss_defeated(boss_id: StringName)
# status (stats-status)
signal status_applied(target: Node, status: int, stacks: int, source: Node)
signal combo_triggered(target: Node, combo: Combo, source: Node)
# abilities (abilities)
signal ability_cast(player: Player, ability: Resource, rank: int)
signal ultimate_used(player: Player, ultimate: Resource)
signal class_skill_used(player: Player)
# rooms and run (floor-generation, run-economy)
signal room_entered(room: Node, player: Player)
signal room_cleared(room: Node)
signal floor_entered(floor_index: int)
signal floor_cleared(floor_index: int)
signal run_started(seed: int)
signal run_ended(result: RunResult)
signal rope_vote_updated(votes: Dictionary)
# loot (run-economy, relics, weapons, abilities)
signal currency_gained(player: Player, currency: StringName, amount: int)
signal pickup_collected(player: Player, pickup: Pickup)
signal relic_picked(player: Player, relic: RelicData)
signal relic_removed(player: Player, relic: RelicData)
signal synergy_activated(player: Player, synergy: Resource)
signal mutation_applied(player: Player, weapon: Resource, mutation: Resource)
signal ascension_chosen(player: Player, ascension: Resource, tier: int)
# story (story-dialogue)
signal story_flag_set(flag: StringName)
signal lore_unlocked(page_id: StringName)
signal miner_rescued(miner_id: StringName)
