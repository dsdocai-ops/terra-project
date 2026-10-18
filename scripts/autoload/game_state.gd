extends Node
## Run data and persistent data. Owned by run-economy (week 3 fills it in).
## Week 1 stub: API shape from SPEC-run-economy plus `world`, set by main.gd,
## and `forced_seed` from the --seed launch arg.
## Sync: run state, votes, and loot rolls are host-authoritative; per-player
## totals are sent to their owning peer. See SPEC-run-economy.

signal run_started(run_seed: int)
signal floor_changed(floor_index: int, biome: Resource)
signal run_ended(result: RefCounted)

## The live World scene. Modules reach World/Players etc. through this,
## never by absolute path.
var world: World = null
## TODO(run-economy): RunState. Null while in town.
var run: RefCounted = null
## TODO(save-system): PlayerProfile, alias of SaveManager.profile.
var profile: RefCounted = null
## Seed forced from the command line (--seed=<int>); 0 means roll one.
var forced_seed: int = 0


## Host only. `party` is an Array of PlayerSpawnInfo dictionaries.
func start_run(_run_seed: int, _start_floor: int, _party: Array) -> void:
	pass


## Host only.
func next_floor() -> void:
	pass


func request_extract_vote(_peer_id: int, _yes: bool) -> void:
	pass


## Host only. `reason` is RunEndReason once run-economy defines it.
func end_run(_reason: int) -> void:
	pass
