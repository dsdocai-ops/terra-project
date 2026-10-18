# Spec: progression-trees

| | |
|---|---|
| Module id | `progression-trees` |
| Owner | Dev B |
| Weeks | 7 (SkillNodeData, all 5 branches data, node graph UI, purchase, respec, node effects for the 3 classes' trees), 11 (all class trees UI and mastery screen, Abyss capstone) |
| Design doc | section 14, section 4.2 (class tree, mastery), section 9.5 (Echo Shards, Class XP) |
| Depends on | `save-system`, `effect-system`, `classes-characters` |
| Depended on by | `town` (Shrine of Echoes opens it), `abilities` (Third Rune, Alt Ultimates flags), `relics` (Abyssal Attunement, Lucky Find, Safe Line, Curse Breaker), `run-economy` (Deep Pockets, Ore Heart, Haggler, Prospector), `endgame` |

## Objective

The permanent power curve: a 38-node skill tree in 5 branches bought with Echo Shards and seven class trees bought with Class XP, shown as a node graph with connecting lines, with every node an `Effect` so it stacks with relics.

## Scope

### Skill tree (locked, design doc section 14)

| Branch | Nodes (ranks) |
|---|---|
| Steel | Sharpened Edge (5), Heavy Hands (3), Critical Eye (5), Brutal Strikes (3), Combo Master (1), Dual Wielder (1), Armory (2), Weapon Master (3), **Executioner** (1) |
| Grit | Thick Skin (5), Iron Hide (3), Quick Feet (3), Perfect Dodge (1), Potion Mastery (2), Last Stand (1), Field Medic (2), **Undying** (1) |
| Arcane | Rune Affinity (5), Quick Cast (3), Elemental Study (3), Reactive (1), Ult Charge (3), Rune Finder (2), Third Rune (1), **Archmage** (1) |
| Delver | Deep Pockets (3), Prospector (5), Treasure Sense (1), Lucky Find (3), Haggler (2), Safe Line (1), Curse Breaker (1), **Ore Heart** (1) |
| Abyss | Abyssal Attunement (1), Echo Resonance (3), Pit Sight (1), Alt Ultimates (3), **Heart of the Pit** (1, requires all 4 branch capstones) |

38 nodes, 9 + 8 + 8 + 8 + 5. Effects exactly as the design doc tables. Abyss unlocks on `story.foreman_defeated`.

Graph layout: each branch is a column of nodes with `requires` edges (a node needs its parent at rank >= 1); capstone requires every node in the branch at rank >= 1. Abyss is a center ring. Layout positions are stored in `SkillNodeData.ui_position` so the UI is data-driven.

Costs: `cost(rank) = base_cost * (1 + 0.5 * rank)` with branch `base_cost` tuned so the full tree (sum of all ranks) costs what a player earns in 25 to 40 runs at average Echo Shard income (computed by `tests/unit/test_tree_economy.gd` from `run-economy` payout constants and an assumed average run of 12 floors with 3 elites per biome; the test asserts the total falls in that window).

Respec: free once per day (`respec_used_date`), otherwise gold cost `200 * nodes_bought`. Refunds all Echo Shards.

### Class trees and mastery

Per class 6 to 8 `ClassTreeNodeData` from `classes-characters`, bought with that class's Class XP. Mastery 1 to 10 from Class XP thresholds; nodes have `mastery_required`. Mastery screen shows level, XP bar, unlocked alt skill (5) and cosmetics (10). Same node graph widget with a different data source.

### Node effects

Every node has `effect: GDScript` (`Effect`) attached at run start with `stacks = ranks`. Stat nodes call `modify()`; behavior nodes (Perfect Dodge time slow, Dual Wielder free heavy, Undying, Safe Line, Curse Breaker, Third Rune, Pit Sight, Alt Ultimates) listen to events or set flags on the relevant controller. Nodes that other modules read as flags expose them through `profile.skill_tree` lookups via `Progression.rank(node_id) -> int`, so e.g. `AbilityController` checks `Progression.rank("third_rune") > 0`.

### UI

`SkillTreeScreen` (`scenes/ui/skill_tree/`): pan and zoom canvas, nodes as buttons with rank pips, lines drawn with `Line2D` between parent and child, states: locked (grey), purchasable (glow), bought (lit). Tooltip with description and next-rank cost. Branch tabs plus center. Keyboard/controller navigation is stretch. Class tree tab per unlocked class. Opened from Shrine of Echoes or pause menu in town.

## Interfaces provided

`SkillNodeData` (`branch`, `max_ranks`, `cost_base`, `requires: Array[StringName]`, `effect`, `ui_position`, `description`, `is_capstone`), `Progression` static (`rank(node_id)`, `class_rank(class_id, node_id)`, `can_buy(node_id)`, `buy(node_id)`, `respec()`, `mastery(class_id)`), `SkillTreeScreen`, `MasteryScreen`, node effects.

## Interfaces consumed

- `save-system`: `skill_tree`, `classes[*].tree`, `respec_used_date`, `echo_shards`.
- `effect-system`: `Effect`, `EffectHost` attach at run start.
- `classes-characters`: `ClassTreeNodeData`, mastery thresholds.
- `story-dialogue`: Abyss unlock flag.
- `run-economy`: Echo Shard balance.

## Data model

`data/skills/<branch>/<node_id>.tres` + `scripts/effects/skills/<node_id>.gd`. Class trees under `data/class_trees/` (owned by `classes-characters`).

## Multiplayer ownership

Per player, local profile. Purchases happen in town on the local machine. Node effects attach on the host for each player from the `SelectionState` payload, which includes the player's `skill_tree` and class tree ranks (host trusts the client's own progression; acceptable for co-op with friends).

Sync: client sends its ranks at run start.

## Testing

- Data-driven `test_skill_data.gd`: 38 nodes, branches and counts, capstones flagged, requires graph acyclic and every node reachable, Heart of the Pit requires the 4 capstones.
- Unit `test_progression.gd`: can_buy rules (parent rank, shards, max ranks, Abyss flag), buy deducts and saves, respec refund and daily rule.
- Unit `test_tree_economy.gd`: total cost within 25 to 40 average runs.
- Harness: one case per node effect (38 + class tree nodes).
- Manual: UI usability pass week 7; 1080p and 1440p integer scaling check.

## Success criteria

- [ ] Week 7: all 38 nodes buyable with working effects, graph UI, respec; Abyss locked until Foreman.
- [ ] Week 11: all 7 class trees and mastery screens.
- [ ] Nodes stack with relics with no special cases (harness case: Lucky Coin + Critical Eye sum correctly).
- [ ] Full tree cost in the 25 to 40 run window per the economy test.

## Open questions

- Pan/zoom canvas vs paged branches on controller: stretch, not in 12 weeks.
