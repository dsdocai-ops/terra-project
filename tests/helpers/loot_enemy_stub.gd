class_name LootEnemyStub
extends Node2D
## Test double for the enemy node `Events.enemy_killed` / `elite_killed` carry.
## Owned by run-economy (tests).
##
## SPEC-enemies-ai, "Interfaces provided": "`Enemy` base: `data: EnemyData`,
## `owner_player` (for friendlies), `is_elite`, `affix`, ...". The drop path
## needs one of those fields — `data` — and reads it by name, the guarded
## duck-typed read this lane already uses for every unlanded provider
## (`Shrine`'s registry, `Pickup`'s Ore Magnet). `EnemyBaseStub` is
## networking's double and carries no `data`, so this is the smallest node that
## answers the read. **Blocked on Dev A (W2-A9)** for the real `enemy_base.tscn`;
## the swap-in is the event carrying a real enemy and this helper disappearing.
##
## Sync: none — a test double. It is never spawned, replicated or hit.

## The `EnemyData` this enemy is configured from, or null.
var data: Resource = null
## True for an elite, matching SPEC-enemies-ai's `is_elite` role. Recorded so a
## case can hand one node to both death signals, as the game does.
var is_elite: bool = false
