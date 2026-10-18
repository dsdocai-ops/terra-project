# Content lists

Canonical lists for content that the design doc names in aggregate but does not enumerate. Each file is created in the week its module spec says and becomes the source of truth for the matching `data/` files and data-driven tests.

| File | Owner | Week | What |
|---|---|---|---|
| `mutations.md` | Dev A | 7, 9, 11 | 120 mutations: weapon, name, effect text. The 6 design doc examples are fixed. Includes Leviathan's Tooth design and its 6 |
| `abilities.md` | Dev A | 5, 9 | rank 2 and 3 scaling per ability, VFX ids |
| `class-trees.md` | Dev A | 7, 11 | 6 to 8 nodes per class from the design doc highlights |
| `dialogue-schema.md` | Dev B | 6 | JSON schema for dialogue and lore files, condition operators, flag namespace list |
| `enemies.md` | Dev A | 6 to 10 | per-enemy attack patterns and numbers as authored |
| `economy.md` | Dev B | 5, 12 | prices, ore costs per building level, Echo Shard curve, tree cost bases |

Design doc content that is already enumerated (relics, abilities, weapons, enemies, bosses, skill nodes, NPCs, buildings) is not duplicated here; the `.tres` and `.json` files copy from [SINKHOLE_SPEC.md](../../SINKHOLE_SPEC.md) directly.
