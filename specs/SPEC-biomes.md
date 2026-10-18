# Spec: biomes

| | |
|---|---|
| Module id | `biomes` |
| Owner | Dev A |
| Weeks | 6 (Biome 1 complete), 8 (Biomes 2 and 3), 9 (Biomes 4 and 5), 10 (Biome 6) |
| Design doc | section 10 (biomes, enemies, hazards), section 17 (palette, lighting), section 9.5 (ore per biome), section 4.1 (Lost Lanterns), section 6 (Conduct on water) |
| Depends on | `enemies-ai`, `floor-generation` |
| Depended on by | `bosses` (arenas, biome context), `run-economy` (ore ids), `story-dialogue` (lore floors), `art-audio` (palettes, tracks), `endgame` (Deep Mode variants) |

## Objective

Six biomes, five floors each, with their own tiles, palette, lighting, hazards, enemy roster, and ore. Content on top of the enemy and floor frameworks, delivered two biomes per content week.

## Scope

### Biomes (locked, design doc section 10)

| # | Biome | Floors | Ore | Hazards | Enemies | Lore floor |
|---|---|---|---|---|---|---|
| 1 | Collapsed Mines | 1 to 5 | Copper | falling rocks, runaway mine carts, gas pockets (ignite with Fire) | Hollow Miner, Rock Tick, Lantern Wisp, Dynamite Goblin, Cave Bat Swarm | 4 |
| 2 | Fungal Caverns | 6 to 10 | Iron | spore vents (poison), bouncy mushrooms (launch), darkness zones | Shroomling (splits), Spore Spitter, Mycel Brute, Glow Moth (blinds), Root Strangler | 9 |
| 3 | Crystal Hollows | 11 to 15 | Crystal | reflecting crystals (reflect projectiles incl. yours), laser beams between pillars | Shard Golem (splits into shards), Prism Bat, Geode Turtle (hit from behind), Crystal Mimic | 14 |
| 4 | Drowned City | 16 to 20 | Pearl | deep water slows, currents push, rising water tiles | Deepkin, Eel Lurker (ambush), Drowned Priest (heals, shields), Barnacle Crab (armored), Siren (pulls) | 19 |
| 5 | Ember Forge | 21 to 25 | Ember Ore | lava rivers, conveyor belts, molten pours, steam vents | Forge Imp, Slag Golem (leaves lava), Bellows Drone (pushes), Clockwork Sentry (turret), Ashen Smith (buffs weapons) | 24 |
| 6 | The Heart | 26 to 30 | Heartstone | pulsing spike walls, breathing floor tiles, shrinking rooms | corrupted versions of all previous + Veinling (drains until dodged off), Heart Guard (behind only), Echo (copies last ability) | 29 |

Enemy count: 5 + 5 + 4 + 5 + 5 = 24 base enemies in Biomes 1 to 5, plus 3 Heart-only enemies = 27 distinct, plus corrupted variants of the 24 as data-only variants in Biome 6. The design doc's lists are the content; no enemy is dropped.

### BiomeData

```gdscript
class_name BiomeData extends ContentData
@export var index: int                       # 1 to 6
@export var floor_range: Vector2i
@export var tileset: TileSet
@export var tile_ids: Dictionary             # floor, wall, pit, water, lava, conveyor atlases
@export var room_size_range: Rect2i
@export var palette: Gradient                # for VFX tinting and UI accents
@export var ambient_light: Color             # CanvasModulate
@export var light_falloff: float             # deeper = darker
@export var hazards: Array[HazardPlacement]
@export var enemy_pool: Array[EnemyData]     # weights in HazardPlacement-like WeightedEntry
@export var elite_pool: Array[EnemyData]
@export var ore: OreData
@export var lore_floor: int
@export var mini_boss: BossData              # floor 3
@export var boss: BossData                   # floor 5
@export var music_track: AudioStream
@export var corrupted_pool: Array[EnemyData] # Biome 6 only
```

### Hazards

Each hazard is a scene under `scenes/dungeon/hazards/<biome>/` with its own `Hitbox` (team ENEMY, telegraphed where it damages) and behaviors:

- Falling rocks: telegraph shadow 0.8 s, then rock, damage + brief stun.
- Mine cart: rails tile path, cart runs on a timer, knockback and damage, can hit enemies too.
- Gas pocket: area with `gas` flag; any Fire element inside ignites: explosion hits both teams, then clears.
- Spore vent: periodic Toxin cloud.
- Bouncy mushroom: launches the entity standing on it in its facing direction (dodge-like move, i-frames).
- Darkness zone: `CanvasModulate` region to 15%, Ivy's light and Lantern Staff reveal; enemies in darkness are untargetable by auto-aim.
- Reflecting crystal: `Projectile.reflectable` bounces with team kept, so your bolts can hit you.
- Laser beams: between two pillars, on/off cycle with 0.5 s charge glow.
- Deep water: tiles set `wet` on entities and slow 40%; currents add velocity; rising water tiles toggle walkability on a timer (telegraphed by bubbles).
- Lava: damage per second, Slag Golem leaves temporary lava; Demolitionist immune to own explosions only, not lava.
- Conveyor: adds velocity along the belt.
- Molten pour: telegraphed column drop.
- Steam vent: periodic knockback blast.
- Pulsing spike wall: wall segment spikes out on a rhythm with glow.
- Breathing floor: tiles rise and fall; raised tiles block projectiles.
- Shrinking room: walls close in over 60 s to a minimum; enemies pushed too.

### Enemy behaviors per biome

Each enemy is an `EnemyData` plus a `State` script where the design doc describes a special behavior. Notable implementations: Shroomling split (2 small on death, not elite); Shard Golem split (3 shards); Geode Turtle (`Hurtbox` immune unless `from_behind`); Crystal Mimic (spawns as a chest pickup, becomes enemy on approach); Drowned Priest (heals and shields allies in range); Siren (pull toward her, interrupted by damage); Eel Lurker (hidden in water, ambush when a player is within 64 px); Bellows Drone (gust pushes toward lava); Ashen Smith (buffs allies' damage +30% while alive, priority target); Veinling (latches on, drains HP until the player dodges); Heart Guard (front immune); Echo (casts the nearest player's `AbilityController.last_cast` as an enemy version every 8 s).

### Lighting and palette

Per-biome `CanvasModulate` color and `PointLight2D` on players (Ivy's bigger, Lantern Staff cone), torches in rooms, glowing enemies and crystals. Deeper biomes darker (`light_falloff`). Darkness floor modifier multiplies ambient down. Compatibility renderer: lights are limited; cap 16 visible lights per room, pool them.

### Lost Lanterns

5 `LostLantern` pickups across Fungal Caverns floors (one per floor, hidden in Secret or dead-end rooms); collecting all five sets `char.ivy_lanterns_5` (Ivy unlock). Progress persists across runs in `profile.story_flags` (`lantern.1` to `lantern.5`).

### Depth scaling

Applied from `Scaling` by biome index; more enemies per room and higher elite chance on deeper floors (`enemies-ai` spawn director).

## Interfaces provided

`BiomeData`, hazard scenes, `wet`/`gas`/`lit` tile and entity flags convention, `LostLantern`, enemy `.tres` and state scripts under `data/enemies/<biome>/` and `scenes/enemies/<biome>/`.

## Interfaces consumed

- `enemies-ai`: `Enemy` base, `EnemyData`, `SpawnDirector`.
- `floor-generation`: `HazardPlacement`, populators, `BiomeData` consumption.
- `combat-core`: `Hitbox`, `Projectile.reflectable`, `Telegraph`.
- `stats-status`: statuses, `wet` for Conduct.
- `abilities`: `AbilityController.last_cast` for Echo.
- `art-audio`: tiles, palettes, tracks, VFX.

## Data model

`data/biomes/<index>_<id>.tres`, `data/enemies/<biome>/<enemy>.tres` (+ `_corrupted.tres` variants for Biome 6), `data/enemies/attacks/<biome>/*.tres`, `assets/tilesets/<biome>.tres`.

## Multiplayer ownership

Hazards run on the host (timers, hitboxes) and replicate state (cart position, water level, wall positions) through synchronizers; visuals like glow cycles are local from synced phase. Enemies per `enemies-ai`.

Sync: host-authoritative hazards.

## Testing

- Data-driven `test_biome_data.gd`: 6 biomes, floor ranges cover 1 to 30 without gaps, each has ore, lore floor, mini-boss, boss, enemy pool >= 3 (Biome 6 >= 3 + corrupted pool = all prior), every listed enemy name exists as a `.tres` (the 27 names above are asserted literally), hazards >= 3 per biome.
- Harness-like `test_hazards.gd`: each hazard scene instantiates and its damage hitbox has a telegraph or a constant visual.
- Integration: 500-seed floor test runs against every real `BiomeData`.
- Manual: each biome playable end to end solo and co-op in its content week; lighting check on Compatibility renderer at 60 FPS.

## Success criteria

- [ ] Week 6: Collapsed Mines floors 1 to 5 with all 5 enemies, 3 hazards, palette and lighting, Copper ore.
- [ ] Week 8: Fungal Caverns and Crystal Hollows complete, Lost Lanterns placed.
- [ ] Week 9: Drowned City (water + Conduct) and Ember Forge complete.
- [ ] Week 10: The Heart with corrupted pool and 3 new enemies.
- [ ] Every biome visually distinct in palette and lighting (week 12 screenshots).

## Open questions

- Whether Biome 6 corrupted variants need distinct sprite sheets or a shader tint only. Shader tint by default; sheets if art time allows in week 12.
