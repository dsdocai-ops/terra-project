# Spec: floor-generation

| | |
|---|---|
| Module id | `floor-generation` |
| Owner | Dev A |
| Weeks | 3 (generator, 6 room types, door locks, seed sync), 6 (Shop, Rest, Shrine, Rune, Anvil, Lore placement), 11 (Challenge, Secret, Cursed Altar, all modifiers) |
| Design doc | section 10 "Floor Generation", section 3 (rope points), section 23 (500 seeds) |
| Depends on | `foundation`, `networking` |
| Depended on by | `run-economy`, `biomes`, `enemies-ai`, `relics`, `weapons`, `abilities`, `story-dialogue`, `ui-hud` (minimap) |

## Objective

Deterministic, seeded floors painted onto `TileMapLayer`s: 8 to 14 rooms joined by corridors with extra loops, 15 room types placed by rules, locking combat rooms, floor modifiers, and biome hazards hooks. The same seed yields the same floor on every peer, and 500 seeds in a row produce no unreachable room.

## Scope

### Algorithm

1. `RandomNumberGenerator` seeded with `hash(run_seed, floor_index)`. All randomness in generation uses this RNG and nothing else (no `randi()`, no `shuffle()` without the RNG).
2. Grid of 96x96 tiles. Place `room_count = rng.randi_range(8, 14)` rectangular rooms (sizes from `BiomeData.room_size_range`, default 9x7 to 17x13 tiles) by rejection sampling with a 2-tile gap; retry whole floor up to 20 times if placement fails.
3. Connect rooms with a minimum spanning tree on room centers, then add `loops = rng.randi_range(1, 3)` extra edges between non-adjacent rooms. Corridors are L-shaped, 3 tiles wide, carved on the grid.
4. Assign room types by rules (below). Start and Exit are the two most distant rooms by graph distance.
5. Paint: floor tiles, wall tiles around every walkable cell, pit tiles elsewhere; set the `walkable` custom data; build `AStarGrid2D`.
6. Place doors on corridor mouths of combat rooms; place room interactables by calling registered populators; place hazards from `BiomeData.hazards` on allowed tiles; place spawn points.
7. Compute `layout_hash` (hash of room rects, types, corridor cells) for the co-op assertion.

Floor 1 of each biome and floor 5 (boss) use a fixed arena room appended after the Exit instead of a random boss room; the boss arena scene itself belongs to `bosses`.

### Room types and placement rules

| Type | Rule |
|---|---|
| `START` | Graph-farthest pair end A. Player spawn, no enemies |
| `EXIT` | Pair end B. Opens when `required_rooms_cleared` (all combat rooms on the path) |
| `COMBAT` | Default for unassigned rooms, doors lock on enter until clear |
| `ELITE_COMBAT` | 1 per floor from floor 3, 2 from floor 11 |
| `TREASURE` | 1 per floor, chests, dead end preferred |
| `SHRINE` | 1 per floor; relic choice 1 of 3; also ability swap station |
| `RUNE` | Rune Stone (ability) room, chance from `Scaling.rune_room_chance` (Rune Finder node raises) |
| `ANVIL` | Weapon mutation 1 of 3, 1 per 2 floors, guaranteed on floors 4, 9, 14, 19, 24, 29 |
| `SHOP` | 1 per floor on floors 2 to 4 of each biome |
| `CURSED_ALTAR` | 25% chance per floor, never on floor 1 of a biome |
| `CHALLENGE` | 20% chance from floor 6, timed or no-hit |
| `LORE` | 1 per biome at a fixed floor from `BiomeData.lore_floor`, holds one unread page |
| `REST` | 1 per floor on floors 3 to 4 of each biome (heal or upgrade) |
| `SECRET` | 1 per floor behind a breakable wall from a dead-end room; Wren passive and Treasure Map reveal; Rat King wall is a flagged special in Biome 1 |
| `ROPE` | Only on floor 2 of each biome. Boss floors have the rope in the arena after the kill |
| `MINI_BOSS` / `BOSS` | Floor 3 and 5 arena rooms |

Populators: each owning module registers `FloorGenerator.register_populator(RoomType, Callable(room: Room) -> void)` at startup. The generator places the room and calls the populator on the host after painting; the populator spawns its interactable via spawners. Combat room populators are `SpawnDirector.fill_room`.

### Doors and clearing

`Room` node tracks `enemies_alive`. On player enter (any player crosses the room's trigger), host locks doors (`Door` nodes with collision + closed sprite) and spawns waves. On last enemy death, `Events.room_cleared(room)` and doors open. Treasure and Shrine rooms never lock. Exit requires all `COMBAT`/`ELITE_COMBAT` rooms on at least one Start-Exit path to be cleared (design doc: "doors lock" rooms; the exit rule prevents skipping everything).

### Floor modifiers

Rolled per floor from `floor_index`, deeper floors more likely (`Scaling.modifier_chance`), at most 2 per floor:

| Modifier | Effect | Owner of effect |
|---|---|---|
| `DARKNESS` | `CanvasModulate` to 25%, only lights show | `biomes` lighting |
| `DOUBLE_ELITES` | elite chance x2 | `enemies-ai` |
| `FAST_ENEMIES` | +25% enemy move and attack speed | `enemies-ai` |
| `LOW_GRAVITY` | dodge distance x1.5 | `player-controller` |
| `GOLD_RUSH` | +100% gold drops | `run-economy` |
| `EXPLOSIVE_ENEMIES` | every enemy explodes on death | `enemies-ai` |

Map Room shows next floor's modifiers before diving (`town`). Modifiers are part of `floor_ready` broadcast.

### Hazards hooks

`BiomeData.hazards: Array[HazardPlacement]` (scene, density, allowed room types, allowed tile rule). Generator places them; hazard behavior scenes belong to `biomes`.

### Minimap data

`FloorLayout` exposes rooms, types, visited flags, and corridor cells for `ui-hud`'s minimap. Treasure Sense and Pit Sight nodes reveal type icons.

## Interfaces provided

```gdscript
class_name FloorGenerator
static func generate(run_seed: int, floor_index: int, biome: BiomeData, modifiers: Array[FloorModifier]) -> FloorLayout
static func register_populator(type: RoomType, populator: Callable) -> void
static func roll_modifiers(run_seed: int, floor_index: int) -> Array[FloorModifier]

class_name FloorLayout extends RefCounted
var rooms: Array[RoomSpec]        # rect, type, neighbors, spawn points, interactable anchor
var corridors: Array[Vector2i]
var start_room, exit_room: RoomSpec
var layout_hash: int
var modifiers: Array[FloorModifier]

class_name Floor extends Node2D   # the live scene: paints a FloorLayout, holds Room nodes, Doors, astar
var layout: FloorLayout
var astar: AStarGrid2D
var rooms: Array[Room]
func paint(layout: FloorLayout, biome: BiomeData) -> void
func room_at(world_pos: Vector2) -> Room
```

`Room` node: `spec`, `type`, `cleared`, `players_inside`, signals `entered(player)`, `cleared`.

Events emitted: `room_entered`, `room_cleared`, `floor_entered` (definitions in `SPEC-effect-system.md`).

## Interfaces consumed

- `foundation`: TileSet, `Iso`, world scene.
- `networking`: `floor_ready` broadcast and hash assertion.
- `biomes`: `BiomeData` (tiles, room size range, hazards, lore floor, enemy pool).
- `enemies-ai`: `SpawnDirector` as the combat populator.

## Data model

`RoomType` enum, `FloorModifier` enum, `RoomSpec` RefCounted, `HazardPlacement` Resource (defined here, authored in `BiomeData`).

## Multiplayer ownership

Every peer generates the floor locally from the same seed and inputs; the host is the source of truth and the `layout_hash` assertion catches divergence. Populators and door locking run on the host; door state and `cleared` sync via the `Room` node's synchronizer. Enemies, chests, and interactables are spawned by the host.

Sync: deterministic local generation + host-authoritative room state.

## Testing

- `tests/integration/test_floor_generation_seeds.gd`: for 500 seeds across all 6 biomes (uses placeholder `BiomeData` until biomes exist): every room reachable from Start via walkable tiles (flood fill), Exit reachable, Start and Exit distinct, room count in range, required types present per rules, floor 2 has exactly one `ROPE`, no two rooms overlap, corridors 3 wide, same seed twice gives identical `layout_hash`. Runs in CI; must finish under 60 s headless.
- Unit: `test_room_rules.gd` (type assignment per floor index), `test_modifiers.gd` (roll determinism and max 2), `test_exit_rule.gd` (exit opens only when the path is cleared).
- Two-instance: hash match on 20 floors.

## Success criteria

- [ ] Week 3: floors with Start, Combat, Elite Combat, Treasure, Rope, Exit; doors lock and unlock; seed-synced in co-op; 500-seed test green.
- [ ] Week 6: Shop, Rest, Shrine, Rune, Anvil, Lore placed by rules with working populators from their modules.
- [ ] Week 11: Challenge, Secret, Cursed Altar rooms and all 6 modifiers.
- [ ] 500-seed test still green with real `BiomeData` for all 6 biomes at week 10.
- [ ] Generation time under 50 ms per floor on the host.

## Open questions

- Room shapes beyond rectangles (L-shapes, caves via cellular automata inside the rect) are a week 11 polish item if time allows; not required by the design doc.
