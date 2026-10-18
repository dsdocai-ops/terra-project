# Spec: ui-hud

| | |
|---|---|
| Module id | `ui-hud` |
| Owner | Dev B |
| Weeks | 2 (HUD v0: HP, weapon, damage numbers hook), 4 (relic choice popup, relic icons, synergy panel, currencies, minimap), 5 (main menu, host/join, run setup, town menus, rope vote, death and victory screens, pause, inventory), 12 (settings with rebinding, achievements UI, polish) |
| Design doc | section 16, section 5 (rebinding), section 12 (ping, lobby), section 9.4 (synergy HUD) |
| Depends on | `foundation`, `run-economy`, `relics`, `abilities` |
| Depended on by | every player-facing module |

## Objective

Every screen in design doc section 16, readable at 960x540 with integer scaling, driven by replicated state so it works identically on host and clients.

## Scope

### Screens and panels

| Screen | Contents | Week |
|---|---|---|
| Main menu | Play Solo, Host Co-op, Join Co-op (IP + port field, tunneling hint), Settings, Codex, Quit | 5 |
| HUD | own HP bar, teammate HP bars with names and downed state, potions with count, ability slots Q/R/V with cooldown sweeps and charges, ultimate meter, active relic slots C/B with cooldown, class resource bar (Rage/Scrap/Souls), weapon slots with active highlight and skill cooldown, floor and biome label, gold, ore, Echo Shards this run, relic icon strip with stacks, synergy panel (progress pips, active glow), minimap, boss bar with phase markers, interact prompt, ping markers, status icons on self | 2, 4 |
| Pause | Resume, Settings, Codex, Quit to Town (counts as death, confirm), Leave Co-op | 5 |
| Run / inventory (Tab) | relics with descriptions and tags, stats (11 values), synergy progress, floor map (rooms visited, types if revealed), abilities with ranks, weapons with mutations, class and Ascension | 5 |
| Choice popups | relic 1-of-3, ability 1-of-3, mutation 1-of-3 (+1 Armory), Ascension 1-of-2, cursed altar take/leave, shop buy, rest heal-or-upgrade; each shows name, description with filled values, tags, rarity color | 4 |
| Rope vote | who voted, timer, Yes/No, cancel on any No | 5 |
| Death screen | kept vs lost table from `RunResult`, run stats, Echo Shards and Class XP earned, Return to Town | 5 |
| Victory screen | same plus ending title, Deep Mode unlocked notice | 10 |
| Town menus | per building menu scenes (`town` provides data; this module provides the widgets): Blacksmith buy/upgrade, Alchemist, Map Room floor picker with modifier preview, Relic Vault and Rune Library pickers, Training Grounds DPS readout, Rescue Camp, Bounty Board, Wardrobe grid | 5, 6, 11 |
| Run setup | character, class, weapons (2), class skill variant, start floor, vault/library picks, heat levels, ready state per player | 5 |
| Skill tree and class tree | widget owned by `progression-trees`; this module provides base theme and tooltip | 7 |
| Dialogue box | owned by `story-dialogue`; this module provides theme | 6 |
| Codex | relics, abilities, enemies, bosses, lore pages; seen/unseen; from profile | 10 |
| Settings | audio (master, music, sfx), video (window mode, scale, vsync), screen shake 0 to 100%, damage numbers on/off, key rebinding for every Input Map action (listens for next input, conflicts warned), controller deadzone | 12 |
| Lobby (Tavern) | widget for `town` | 5 |
| Debug console | owned by `debug-tools` | 2 |

### Theme

One `Theme` resource (`assets/ui/theme.tres`): pixel font (CC0, e.g. m5x7 or similar) at 8 px and 16 px, 9-slice panels in a stone and lantern-light palette, rarity colors (common grey, rare blue, epic purple, legendary gold, cursed red), element colors (fire orange, frost cyan, storm yellow, shadow violet, poison green, earth brown, blood crimson, void magenta). All UI is `Control` under a `CanvasLayer`, anchored for 16:9, tested at 960x540 and 1920x1080.

### Data flow

The HUD never queries gameplay nodes directly. It binds to `RunPlayerState` (replicated), `Player` signals for the local player, and `Events` (client-emitted copies). A `HudModel` adapter exposes typed properties the widgets bind to, so the same HUD works on host and client.

### Minimap

Draws `FloorLayout` rooms as diamonds with corridors; visited rooms lit; current room highlighted; players as dots; room type icons when Treasure Sense / Pit Sight / Treasure Map reveal them; Exit icon once discovered.

### Ping

`ping` action on middle click: `request_ping(world_pos, kind)`; a world-space marker with the pinger's color for 4 s plus an edge-of-screen arrow if offscreen; `kind` cycles enemy / loot / go-here by what is under the cursor.

### Damage numbers and floating text

Pool owned by `combat-core`; styles (crit size, element colors) come from the theme here.

## Interfaces provided

`HudModel`, `ChoicePopup.show(options: Array[ChoiceOption], on_pick)`, `Toast.show(text)`, `Prompt.show(text)`, `BossBar.bind(data)`, `Minimap.bind(layout)`, `Theme`, `RebindRow`, `Codex`. `ChoiceOption {id, title, description, tags, rarity_color, icon}`.

## Interfaces consumed

- `run-economy`: `RunPlayerState`, `RunResult`, vote state, currencies.
- `relics`, `abilities`, `weapons`, `classes-characters`: choice data, cooldown fractions, descriptions.
- `floor-generation`: `FloorLayout` for minimap.
- `bosses`: `BossHealthBarData`.
- `networking`: join/host calls, ping RPCs, lobby state.
- `save-system`: settings persistence, codex.
- `foundation`: input action names for rebinding.

## Data model

`assets/ui/theme.tres`, `scenes/ui/**`. Settings schema in `PlayerProfile.settings`.

## Multiplayer ownership

Pure presentation. Every interactive choice sends a `request_*` RPC and waits for the host's confirmation before updating (optimistic highlight allowed). Pause does not pause the game in co-op; it overlays.

Sync: none owned; reads replicated state.

## Testing

- Integration `test_ui_scenes.gd`: every UI scene instantiates with a fake `HudModel`.
- Unit `test_hud_model.gd`: bindings update from fake `RunPlayerState` changes; cooldown fraction math.
- Unit `test_rebinding.gd`: rebinding writes the Input Map and settings, detects conflicts, restores defaults.
- Manual: readability pass at 960x540 and 1920x1080 each UI week; controller sanity for gameplay HUD (menus controller nav is stretch).
- Two-instance: client HUD matches host truth after relic pick, currency change, vote, downed teammate.

## Success criteria

- [ ] Week 2: HP, weapon, damage numbers visible in play.
- [ ] Week 4: relic popup, icons, synergies, currencies, minimap.
- [ ] Week 5: menu, host/join, run setup, pause, inventory, vote, death screen, town menus v1.
- [ ] Week 12: settings with full rebinding, achievements list, codex complete, polish.
- [ ] Every string the player sees comes from a `ContentData` or a UI constant file, not a hardcoded literal inside logic scripts.

## Open questions

- Pixel font choice (CC0) decided week 2.
