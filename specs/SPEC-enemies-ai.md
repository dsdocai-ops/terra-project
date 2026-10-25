# Spec: enemies-ai

| | |
|---|---|
| Module id | `enemies-ai` |
| Owner | Dev A |
| Weeks | 2 (base enemy, 3 enemies), 4 (elites, affixes, spawn director, pooling) |
| Design doc | sections 6, 9.5 (elites, depth scaling), 10 (enemy lists, owned by `biomes`), 11 (escort follower), 23 (60 units) |
| Depends on | `combat-core`, `networking` |
| Depended on by | `biomes`, `bosses`, `story-dialogue` (escort), `floor-generation` (spawn hooks), `endgame` |

## Objective

A single enemy framework that 32 enemy types, their corrupted variants, elites, minions, turrets, companions, and escort NPCs are all built on as data plus small state scripts, and that holds 60 units at 60 FPS on the Compatibility renderer.

## Scope

### Enemy base

`scenes/enemies/enemy_base.tscn`: `CharacterBody2D` with `StatBlock`, `Health`, `Hurtbox`, `StatusEffects`, `StateMachine`, `AnimatedSprite2D`, `NavigationAgent2D` or grid path follower, `Telegraph`, `StateSync`. Configured entirely from `EnemyData`.

Standard states: `Spawn`, `Idle`, `Chase`, `Attack(pattern)`, `HitStun`, `Flee`, `Dead`. Per-enemy behaviors are small `State` subclasses in `scenes/enemies/<biome>/<enemy>_states.gd` (Rock Tick rush, Shroomling split, Geode Turtle shell, Siren pull, Veinling latch). The design doc enemy list and biome assignment live in `SPEC-biomes.md`; this module ships the framework and the week 2 trio: Hollow Miner (melee), Rock Tick (rush), Lantern Wisp (ranged fireball).

### Movement and pathfinding

- `AStarGrid2D` built per floor from the walkable custom data layer by `floor-generation` and exposed as `Floor.astar`. Enemies request a path on target change and every 0.5 s, follow waypoints, and use simple separation steering so groups do not stack. `NavigationAgent2D` is the fallback if grid paths look bad in corridors; decide in week 2 and record.
- Flyers (Cave Bat Swarm, Glow Moth, Prism Bat) ignore the walkable layer and use direct steering with wall avoidance.
- All movement multiplies by `TimeManager.scale_for(self)`.

### Targeting

`Targeting.pick(enemy, players, minions, decoys)`: nearest by default; taunt (Battle Cry, Frozen Clone, Decoy Lantern, minion taunt node) overrides for its duration; Smoke Step / Smoke Bomb / Vanish / Ghost Wrap make a player untargetable and drop aggro. Multi-player aware: spread aggro so one player is not focused unless taunting.

### Elites

Any `EnemyData` with `can_be_elite` can spawn as elite. Elite gets a glowing outline shader, +100% HP, and one affix:

| Affix | Effect |
|---|---|
| `SHIELDED` | Periodic shield absorbing N hits, breaks on heavy |
| `HASTED` | +40% move and attack speed |
| `SPLITTING` | On death spawns 2 non-elite copies at 30% HP |
| `VAMPIRIC` | Heals 20% of damage dealt |
| `EXPLOSIVE` | Death explosion with telegraph 0.6 s |
| `TELEPORTING` | Blinks behind its target every 6 s with a telegraph |

Elite death emits `Events.elite_killed` for `run-economy` (loot, Echo Shards) and Trophy Belt.

### Spawn director

`SpawnDirector` (host only) fills combat rooms: given `BiomeData.enemy_pool`, floor index, and room size, picks a budget `Scaling.enemies_per_room(floor)` and spawns waves (1 to 3 per room, next wave at 40% remaining). Elite chance from `Scaling.elite_chance(floor)`, floor modifier `Double Elites` doubles it, Pit Pact forces one elite per room. Spawn uses the enemy `MultiplayerSpawner`. Spawn positions avoid 160 px around players.

### Pooling and performance

- Enemies are pooled per scene type (`EnemyPool`), reset via `reset_from_data(data)`.
- Shared `AnimatedSprite2D` frames per type; no per-instance material unless flashing (material swap on flash, restore after).
- Sprite `visible = false` and processing paused for enemies outside the active room.
- Budget: 60 units (enemies + minions + turrets + companions) at 60 FPS with VFX in `debug-tools` perf scene. Separation steering is O(n) per unit via a spatial hash grid, not O(n^2).

### Friendly units

Same base with `Team.PLAYER`: Necromancer skeletons and raised enemies, Engineer turrets (static, `Deploy`), Ranger wolf and hawk, Pocket Golem, Shadow Clones, Frozen Clone, Soul Jar ghost army, Reaper's Harvest ghost, Mirror Step clone. `FriendlyUnit` adds `owner_player`, `inherit_stats_fraction` (Necromancer node 25%), `lifetime`, and `follow_owner` behavior. Minion count caps are enforced by the owning class script.

### Escort follower

`EscortNpc`: `Team.NEUTRAL`, follows the rescuing player at 64 px, has `Health`, can be hit by enemies, flees from enemies when low, teleports to the player if more than one room behind. Death fails the rescue for this run (design doc: "they follow you and can be hurt"). Owned here; mission logic in `story-dialogue`.

### Corruption variants

Biome 6 "corrupted versions of all previous enemies": `EnemyData.corrupted_of` points at the base; corrupted gets +1 random affix-like trait, darker palette via shader, and Unravel on hit. No new scenes.

## Interfaces provided

- `Enemy` base: `data: EnemyData`, `owner_player` (for friendlies), `is_elite`, `affix`, `target: Node`, `setup(data, is_elite, affix)`, signals `spawned`, `died(hit)`.
- `SpawnDirector.fill_room(room, biome, floor_index)` and `spawn_one(data, pos, is_elite := false) -> Enemy` (used by bosses, Necromancer, debug console).
- `FriendlyUnit`, `EscortNpc`.
- `Targeting` static.
- Events emitted: `enemy_killed`, `elite_killed`, `enemy_spawned` (definitions in `SPEC-effect-system.md`).

## Interfaces consumed

- `combat-core`: components, `AttackPattern`, `Telegraph`, `Projectile`.
- `stats-status`: `Scaling`, `StatBlock`, statuses.
- `time-manager`: `scale_for`, `timer`.
- `networking`: spawners, `enemy_hp_multiplier()`.
- `floor-generation`: `Floor.astar`, room bounds and spawn points (week 3).

## Data model

`EnemyData extends ContentData` (`scripts/data/enemy_data.gd`):

```
scene: PackedScene              enemy_base or a subclass scene
sprite_frames: SpriteFrames
base_stats: Dictionary          Stat -> float
attacks: Array[AttackPattern]
move_type: enum GROUND, FLYING, STATIC
aggro_range, attack_range: float
stagger_resist, knockback_resist: float   stagger_resist scales poise damage taken
poise: float                    poise pool; 0 = fodder that staggers on every hit, ~40 mid, 300+ bosses
stagger_seconds: float          how long a poise break staggers (default 0.8)
can_be_elite: bool
tags: Array[StringName]         "drowned" (wet), "undead", "mechanical", "fungal"
loot_table: LootTable           defined in run-economy
echo_shards_on_death: int
corrupted_of: EnemyData
biome: StringName
```

`.tres` files under `data/enemies/<biome>/<enemy>.tres`, authored by `biomes`.

## Multiplayer ownership

Enemy AI, targeting, attacks, HP, death, and spawning run on the host only. `StateSync` replicates position, animation, HP, status stacks, elite flag, and affix. Clients render telegraphs from the synced attack state.

Sync: host-authoritative, spawner-replicated, `StateSync` per enemy.

## Testing

- Unit: `test_targeting.gd` (nearest, taunt override, untargetable), `test_spawn_director.gd` (budget per floor, elite chance, no spawn near players, deterministic given seed), `test_affixes.gd` (each affix behavior with a stub).
- Integration: `test_enemy_data.gd` loads every `EnemyData`, asserts stats present, every attack has windup >= 0.2, scene instantiates. `test_pooling.gd` spawns and despawns 200 enemies, node count returns to baseline.
- Perf: perf scene 60 units with 4 players' worth of minions; FPS logged in weekly notes.
- Two-instance smoke: enemies visible and animated on client; elite outline and affix VFX visible.

## Success criteria

- [ ] Week 2: Hollow Miner, Rock Tick, Lantern Wisp chase, telegraph, attack, die, synced.
- [ ] Week 4: elites with all 6 affixes; spawn director fills rooms by budget; waves.
- [ ] 60 units at 60 FPS in the perf scene on both developers' machines, measured weekly from week 4.
- [ ] Friendly unit base supports Necromancer skeletons and Engineer turrets by week 9 with no changes to the enemy framework.
- [ ] Escort follower survives a floor walk with a player in the two-instance smoke by week 7.

## Open questions

- `AStarGrid2D` vs `NavigationAgent2D`: decide week 2.
