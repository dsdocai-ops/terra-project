# Spec: run-economy

| | |
|---|---|
| Module id | `run-economy` |
| Owner | Dev B |
| Weeks | 3 (run state, rope rooms, run end on all-downed), 4 (currencies, drops, pickups, chests, elite payouts), 5 (rope votes, death and extract rules, banking, Map Room shortcuts, shops, potions) |
| Design doc | sections 3, 9.5, 12 (co-op rules), 4.2 (Ascension timing), 13 (Map Room, Alchemist potions), 11 (Vesper) |
| Depends on | `floor-generation`, `networking`, `stats-status`, `save-system` |
| Depended on by | `relics`, `story-dialogue`, `town`, `ui-hud`, `progression-trees`, `endgame` |

## Objective

The extraction loop and everything with a number attached to it: run state in `GameState`, rope points and votes, what you keep on death versus extraction, six currencies and their drops, chests and breakables, shops, and potions.

## Scope

### GameState

```gdscript
# GameState autoload
signal run_started(seed: int)
signal floor_changed(floor_index: int, biome: BiomeData)
signal run_ended(result: RunResult)

var world: Node2D                 # set by main.gd
var run: RunState                 # null in town
var profile: PlayerProfile        # alias of SaveManager.profile

func start_run(seed: int, start_floor: int, party: Array[PlayerSpawnInfo]) -> void   # host
func next_floor() -> void                                                            # host
func request_extract_vote(peer_id: int, yes: bool) -> void
func end_run(reason: RunEndReason) -> void                                          # host
```

`RunState`: `seed`, `floor_index` (1 to 30), `biome_index` (1 to 6), `players: Dictionary` peer_id -> `RunPlayerState` (relics, abilities, weapons with mutations, ascension, potions, echo_shards_earned, class_xp_earned, gold_held share), `shared_gold: int`, `shared_ore: Dictionary`, `elites_killed`, `bosses_killed`, `floors_cleared`, `rooms_cleared_no_hit` (Crown of the Deep), `time_started`.

### Rope points

Rope on floor 2 of each biome (`ROPE` room) and in the boss arena after the biome boss (floors 5, 10, 15, 20, 25). Floor 30 kill is the ending, not a rope. Interacting with the rope opens the vote prompt (`ui-hud`). **All living players must vote yes**; downed players don't vote; a `no` cancels and the rope stays usable. Vote state is host-owned and broadcast. Solo: immediate.

Mini-bosses give no rope (design doc). Floors 3 to 5 of a biome are a commitment.

### Death and extraction rules

| Thing | Extract | Death |
|---|---|---|
| Gold held | keep 100% | keep 25% + Deep Pockets (10% per rank) |
| Ore carried | keep 100% | lose all; Ore Heart capstone keeps 50% |
| Relics | lost (run only); Safe Line node keeps 1 random | lost |
| Run abilities, weapon mutations, Ascension | lost | lost |
| Echo Shards earned | kept | kept |
| Class XP earned | kept | kept |
| Story progress, codex, achievements | kept | kept |

Quit mid-run counts as death. In co-op, shared gold and ore split evenly among the party at extraction; on death the party's shared pools suffer the death rule once, then split. Golden Idol: "lose it all on death" refers to the relic bonus, gold still follows the table.

Run ends when: every player is downed or dead (`DEFEAT`), rope vote passes (`EXTRACT`), final boss dies (`VICTORY`, then ending sequence from `story-dialogue`), host quits (`ABORT` counts as death for everyone).

### Currencies

| Currency | Drop sources (host rolls) | Per-player or shared |
|---|---|---|
| Gold | enemies (by `EnemyData.loot_table`), chests, breakables; Miner's Luck, Gold Rush, Jackpot, Ember Heart multiply | shared |
| Ore | mining nodes (interactable, 3 hits with any attack, Wren +25%), elites 1, mini-boss 3, biome boss 6, always the biome's ore: copper, iron, crystal, pearl, ember_ore, heartstone | shared |
| Echo Shards | 1 per floor cleared (2 in biomes 4 to 6), 1 to 2 per elite, 10 per mini-boss, 20 per biome boss, bounties; Echo Collector +50%, Echo Resonance +10%/rank, Heat multipliers | per player |
| Class XP | kills 1, floor clear 10, mini-boss 30, boss 75, scaled by biome | per player, for the class played |
| Scrap | Engineer only; owned by `classes-characters` | per player |
| Souls | Necromancer only; owned by `classes-characters` | per player |

Pickups are physical: `Pickup` scene (gold coin, ore chunk, echo shard, rune stone, relic, potion) spawned by host, magnetized to the nearest player within `pickup_radius` (Ore Magnet makes it room-wide). Shared currencies are collected by whoever touches them. Per-player pickups (relics, runes) are per-player drops: each player sees only their own (design doc), implemented as pickups with `visible_to_peer`.

### Chests, breakables, mining nodes

`LootTable` Resource: weighted entries `{kind, id or rarity, weight, min, max}`. Chest rarity tiers common/rare/legendary; Treasure room has 2 to 3 chests; Crystal Mimic is an enemy disguised as a chest (`enemies-ai`). Breakables (crates, barrels, bones) drop small gold with 30% chance. Luck stat raises rarity rolls: `rarity_roll += LUCK * 0.01`.

### Shops

`SHOP` room populator: `Shopkeeper` interactable with 4 items (5 with Merchant's Badge): 1 relic, 1 ability rune, 1 potion, 1 random (weapon rare drop, ore). Prices by rarity; Haggler -10%/rank; Merchant's Badge -15%; Greed Chain x3. Vesper (mysterious merchant) has a 10% chance per floor to replace the shopkeeper, sells 2 cursed relics and 1 legendary.

### Potions

`potion` action: heal 35% max HP (+15%/rank Potion Mastery). Slots from Alchemist level (1/2/3). Types from Alchemist: heal, cleanse (clears statuses), haste (10 s +30% speed), shield (absorb next 3 hits). Starting potions set at Alchemist. Refill at Rest rooms and shops.

### Map Room shortcuts

`start_run(start_floor)` for a rope the player has reached (`map_room_deepest_rope`). Starting past Biome 1: Ascension picked at run start; past Biome 4: start at Tier 2 (`classes-characters` reads `RunState.start_floor`). Starting deeper gives no catch-up loot; the design doc accepts this (risk vs reward).

### Banking

On `run_ended`, the host computes per-peer gains and sends `run_summary(peer_id, gains)`; each machine calls `SaveManager.profile.merge_run_gains()` and saves. `ui-hud` shows the death or victory screen from the same `RunResult`.

## Interfaces provided

`GameState` (above), `RunState`, `RunPlayerState`, `RunResult` (`reason`, `floors_cleared`, per-player `kept`/`lost` tables for the UI), `LootTable`, `Pickup`, `Shopkeeper`, `MiningNode`, `PotionController`. Events emitted: `currency_gained`, `pickup_collected`, `run_started`, `run_ended`, `rope_vote_updated`, `floor_cleared` (definitions in `SPEC-effect-system.md`).

## Interfaces consumed

- `floor-generation`: populator registration for `ROPE`, `SHOP`, `REST`, `TREASURE`; `Room`, `Floor`.
- `networking`: `request_vote_rope`, `rope_vote_updated`, `run_summary`, spawners for pickups.
- `stats-status`: `Stat.LUCK`.
- `save-system`: `PlayerProfile`, `merge_run_gains`.
- `enemies-ai`: `elite_killed`, `enemy_killed` with `EnemyData.loot_table`.
- `player-controller`: `player_downed` for the all-downed rule.

## Data model

`LootTable extends Resource` under `data/loot/`. `PotionData extends ContentData` under `data/potions/` (4 types). `OreData extends ContentData` under `data/ore/` (6). `RunState` and friends are RefCounted.

## Multiplayer ownership

Run state, votes, loot rolls, currency totals, shop stock and purchases: host. `request_buy(item_index)`, `request_vote_rope(yes)`, `request_use_potion()` from clients. Shared totals broadcast on change; per-player totals sent to the owning peer.

Sync: host-authoritative, request RPCs, broadcast past-tense RPCs.

## Testing

- Unit `test_death_rules.gd`: every row of the table with and without Deep Pockets, Ore Heart, Safe Line; co-op split math.
- Unit `test_vote.gd`: unanimous living players, downed excluded, `no` cancels, solo immediate.
- Unit `test_loot_table.gd`: weights, Luck effect, determinism with seed.
- Unit `test_echo_shards.gd`: payouts per floor/elite/boss by biome with multipliers.
- Integration: scripted run start to extraction end in headless, `RunResult` and profile deltas match expectations.
- Two-instance: vote prompt appears on both, client `no` cancels, both `yes` extracts, both save their own gains.

## Success criteria

- [ ] Week 3: rope room on floor 2, run ends when all players down.
- [ ] Week 4: gold, ore, Echo Shard pickups, chests, breakables, mining nodes, elite payouts.
- [ ] Week 5: votes, death/extract table, banking, Map Room start floors, shops, potions, save on return to town.
- [ ] All table rows covered by unit tests; co-op split verified in two-instance smoke.

## Open questions

- Base gold prices per rarity and ore amounts per building level are set in week 5 and recorded in `data/` constants.
