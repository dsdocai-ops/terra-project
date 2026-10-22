class_name EnemyDataStub
extends Resource
## Test double for Dev A's `EnemyData` (SPEC-enemies-ai, "Data model":
## `EnemyData extends ContentData`, with `loot_table: LootTable` and
## `echo_shards_on_death: int`). Owned by run-economy (tests).
##
## `scripts/data/enemy_data.gd` is `enemies-ai`'s file and is not in the tree
## (`data/enemies/` holds only `.gdkeep`), so the drop path reads the two fields
## it needs off whatever the enemy carries and these cases supply them here —
## **blocked on Dev A (W2-A9)** for the real Resource. The swap-in is mechanical:
## the real `EnemyData` carries the same two field names, so `LootDrops` reads it
## unchanged and this helper is deleted.
##
## Sync: none — a test double, never a game resource.

## The weighted drop table an enemy death rolls. `null` means "nothing drops".
var loot_table: LootTable = null
## Shards the enemy itself is worth, on top of the elite payout. 0 for most
## enemies; SPEC-enemies-ai's field, read here so the drop path never has to
## guess whether an enemy carries one.
var echo_shards_on_death: int = 0
