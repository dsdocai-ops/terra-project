extends Node
## Global signal bus. Owned by effect-system. Signals only, no logic.
## Sync: emitted on the host where gameplay runs; the presentation signals
## (hit_landed, enemy_killed, relic_picked, room_cleared, currency_gained)
## are also emitted on clients from replicated state. See SPEC-effect-system
## for who emits what. Adding or changing a signal is "Ask first".
##
## Parameter types use the nearest existing base class until the owning
## module defines the real one:
## TODO(combat-core): hit: RefCounted -> HitInfo, projectile: Node -> Projectile
## TODO(enemies-ai): enemy: Node -> Enemy
## TODO(stats-status): status: int -> StatusEffects.Status, combo: int -> Combo
## TODO(abilities): ability, ultimate: Resource -> AbilityData
## TODO(floor-generation): room: Node -> Room
## TODO(run-economy): result: RefCounted -> RunResult, pickup: Node -> Pickup
## TODO(relics): relic, synergy: Resource -> RelicData, SynergyData
## TODO(weapons): weapon, mutation: Resource -> WeaponData, MutationData
## TODO(classes-characters): ascension: Resource -> AscensionData

# combat (combat-core)
signal hit_landed(hit: RefCounted)
signal crit_landed(hit: RefCounted)
signal player_damaged(player: Player, hit: RefCounted)
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
signal enemy_killed(enemy: Node, hit: RefCounted)
signal elite_killed(enemy: Node, hit: RefCounted)
signal boss_defeated(boss_id: StringName)
# status (stats-status)
signal status_applied(target: Node, status: int, stacks: int, source: Node)
signal combo_triggered(target: Node, combo: int, source: Node)
# abilities (abilities)
signal ability_cast(player: Player, ability: Resource, rank: int)
signal ultimate_used(player: Player, ultimate: Resource)
signal class_skill_used(player: Player)
# rooms and run (floor-generation, run-economy)
signal room_entered(room: Node, player: Player)
signal room_cleared(room: Node)
signal floor_entered(floor_index: int)
signal floor_cleared(floor_index: int)
signal run_started(run_seed: int)
signal run_ended(result: RefCounted)
signal rope_vote_updated(votes: Dictionary)
# loot (run-economy, relics, weapons, abilities)
signal currency_gained(player: Player, currency: StringName, amount: int)
signal pickup_collected(player: Player, pickup: Node)
signal relic_picked(player: Player, relic: Resource)
signal relic_removed(player: Player, relic: Resource)
signal synergy_activated(player: Player, synergy: Resource)
signal mutation_applied(player: Player, weapon: Resource, mutation: Resource)
signal ascension_chosen(player: Player, ascension: Resource, tier: int)
# story (story-dialogue)
signal story_flag_set(flag: StringName)
signal lore_unlocked(page_id: StringName)
signal miner_rescued(miner_id: StringName)
