# Spec: town

| | |
|---|---|
| Module id | `town` |
| Owner | Dev B |
| Weeks | 5 (town scene v1, Blacksmith, Shrine of Echoes entry, Tavern dive/lobby, select flow), 6 (NPC placement, Alchemist, Map Room, Shop/Rest hooks), 11 (all 11 buildings at 3 levels, Relic Vault, Rune Library, Training Grounds, Rescue Camp, Bounty Board, Wardrobe, pit edge shrink) |
| Design doc | section 13, section 11 (NPC roles), section 3 (core loop step 1 and 6), section 9.5 (ore per building level) |
| Depends on | `run-economy`, `save-system`, `story-dialogue` |
| Depended on by | `ui-hud` (town menus), `progression-trees` (Shrine of Echoes opens the tree), `endgame` (Bounty Board, Wardrobe cosmetics) |

## Objective

Hollowmere: the hub where the loop closes. 11 buildings with 3 visible upgrade levels bought with ore, NPCs whose dialogue changes, the pit's edge that physically shrinks back as the story advances, and the pre-run flow (character, class, weapon, start floor).

## Scope

### Town scene

`scenes/town/town.tscn`: isometric town on the same TileSet family, `World`-style Y-sort, the pit edge as a `TileMapLayer` with 4 states (act 0 to 3, shrinking back). Buildings are `Building` nodes with 3 sprite states (ruined, rebuilt, upgraded) plus level 0 (not built, shows a sign). Players walk (same `Player` controller, no combat) and interact with buildings and NPCs. In co-op everyone is in the host's town; each player's menus are local.

### Buildings (locked, design doc section 13)

| Building | Level 1 | Level 2 | Level 3 | Ore |
|---|---|---|---|---|
| Blacksmith (Gruff) | buy weapons (gold) | weapon damage tier +10% | tier +20%, rare weapon stock | Copper, Iron, Crystal |
| Alchemist (Moss) | 1 potion slot, heal potion | 2 slots, cleanse + haste types | 3 slots, shield type, choose starting potions | Copper, Iron, Pearl |
| Map Room (Pip) | start at Biome 1 rope (floor 2) | start at any reached rope, see next floor's modifiers | see 2 floors of modifiers | Iron, Crystal, Pearl |
| Shrine of Echoes (Sister Ash) | skill tree (4 branches) | class trees, respec | Abyss tree access (also needs Foreman flag) | Copper, Crystal, Heartstone |
| Tavern (Old Tom) | dive, rumors | co-op lobby board, bounty board visible | daily dive board | Copper, Iron, Ember Ore |
| Relic Vault | codex | start with 1 chosen common relic | pick from rares too | Crystal, Pearl, Heartstone |
| Rune Library | codex | start with 1 chosen ability | start at rank 2 | Crystal, Pearl, Ember Ore |
| Training Grounds | dummies with DPS readout | elite dummy with affixes | boss dummy with phases | Iron, Ember Ore |
| Rescue Camp | rescued miners live here, 1 passive | 2 passives active | all passives active | Copper, Pearl |
| Bounty Board | daily challenge | weekly challenge | 2 dailies | Iron, Crystal |
| Wardrobe | skins from bosses | hats from achievements | Rat companion etc. | Pearl, Ember Ore |

Costs: level N requires ore from biome N-ish per the design doc ("deeper building levels need deeper ores"); table above lists which ore each level consumes in order. Exact amounts in `data/town/<building>.tres` set in week 5 and tuned.

`BuildingData extends ContentData`: `levels: Array[BuildingLevel]` (cost ore id + amount, description, unlock effects), `npc_id`, `sprites[4]`, `menu_scene`.

### Pre-run flow

Tavern "Dive" or Map Room: opens `RunSetup` (UI in `ui-hud`): character (unlocked), class (unlocked), 2 starting weapons from unlocked set (Pickaxe always), class skill variant if mastery 5, start floor (Map Room level), Relic Vault pick, Rune Library pick, heat levels (`endgame`). Host confirms party readiness (each client submits `SelectionState`), then `GameState.start_run`.

### Co-op lobby board (Tavern level 2)

Shows host IP/port, connected players and their selections, ready state, text pointing at playit.gg/Tailscale. Join screen on the main menu is `ui-hud`; this is the in-town view.

### Rescue Camp

Non-class rescued miners give passives as `Effect`s attached at run start: e.g. +1 potion, +10% ore, shops cheaper, reveal one secret room, start with 50 gold. At least 4 defined in `data/town/camp_bonuses/`.

### Bounty Board

Daily and weekly challenges generated from a seeded template list (`data/town/bounties.json`): "kill 50 Shroomlings", "beat Boomer Jack without healing", "extract from floor 10 with 3 cursed relics". Tracked by listening to `Events` during runs; reward Echo Shards. Date-seeded so both devs see the same daily.

### Wardrobe

Cosmetics: skins (palette swaps) and hats per boss kill and achievement (`endgame` writes `cosmetics_unlocked`). Equip writes `equipped_cosmetics`; `Player` applies at spawn (visible in co-op via `PlayerSpawnInfo`).

### Training Grounds

Dummies are `Enemy` instances with infinite HP flag and a DPS meter (damage in last 10 s / 10) shown above them. Level 2 elite dummy cycles affixes; level 3 boss dummy has phases from `BossData` (no attacks).

### Pit edge and visuals

`pit_stage` = `StoryManager.act()` plus ending: the pit `TileMapLayer` swaps to the matching layout, buildings show their level sprites, NPCs appear as rescued. Saved town state drives everything on load.

## Interfaces provided

`Town` scene, `Building`, `BuildingData`, `RunSetup` flow (`SelectionState` validation calls into `classes-characters`), `CampBonus` effects, `BountyTracker`, `Wardrobe` data, `TrainingDummy`.

## Interfaces consumed

- `run-economy`: `GameState.start_run`, ore and gold spending (`profile.ore`, `gold_banked`), potions config.
- `save-system`: `town`, `relic_vault_pick`, `rune_library_pick`, `potions`, `cosmetics`, `weapons_unlocked`.
- `story-dialogue`: `StoryManager.act()`, `start_dialogue`, rescued list.
- `progression-trees`: open skill tree screen.
- `weapons`: unlock list and costs.
- `relics`, `abilities`: codex data and start picks.
- `endgame`: heat level selection in `RunSetup`, achievements for Wardrobe.

## Data model

`data/town/<building>.tres`, `data/town/camp_bonuses/<id>.tres` + effects, `data/town/bounties.json`, `data/cosmetics/<id>.tres`.

## Multiplayer ownership

Town is the host's; building levels and pit stage come from the host's profile and are replicated to clients for display. Purchases are host-only (host's resources). Clients can open codices and the skill tree (their own profile) and set their own `SelectionState`. Run start requires all ready.

Sync: host town state replicated; selections per client.

## Testing

- Data-driven `test_town_data.gd`: 11 buildings x 3 levels, each level has a cost with a valid ore id and non-empty description; 4+ camp bonuses; bounties JSON valid.
- Unit `test_building_purchase.gd`: cost check, ore deduction, level cap, save called.
- Unit `test_bounties.gd`: date seeding deterministic, progress tracking from fake events, reward.
- Integration: town loads with every profile fixture (fresh, mid, complete) and shows the right sprites and pit stage.
- Two-instance: client sees host's building levels; client's own skill tree opens; both ready triggers run start.

## Success criteria

- [ ] Week 5: town v1 with Blacksmith, Shrine entry, Tavern dive; run setup selects character/class/weapons.
- [ ] Week 6: NPCs with dialogue, Alchemist potions, Map Room start floors and modifier preview.
- [ ] Week 11: all 11 buildings at 3 levels with visible rebuild, Relic Vault and Rune Library picks, Training Grounds DPS, Rescue Camp bonuses, Bounty Board, Wardrobe, pit edge shrinking.
- [ ] Design pillar 4 "visible progress": a fresh profile and a complete profile look clearly different in a side-by-side screenshot (week 12 notes).

## Open questions

- Ore amounts per level: set week 5, tuned week 12 so a full town takes roughly as long as a full skill tree (25 to 40 runs).
