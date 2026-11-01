class_name SpawnWaves
extends RefCounted
## The wave plan for one combat room (SPEC-enemies-ai "Spawn director": waves of
## 1 to 3 per room, the next wave at 40 % remaining). The budget is cut into waves
## by `plan`; the first spawns on activation, and each later one spawns once the
## living count falls to NEXT_WAVE_SHARE of the enemies spawned so far. Owned by
## enemies-ai. Sync: host only. The state lives on the host's Room; each spawn
## replicates through the EnemySpawner. Pure: the rng goes in, numbers come out.

const MIN_WAVE: int = 1
const MAX_WAVE: int = 3
## The next wave spawns when this share of the spawned enemies is still alive.
const NEXT_WAVE_SHARE: float = 0.4

## The wave sizes that add up to `budget`, each 1 to MAX_WAVE, drawn from `rng`.
## The last wave takes whatever is left, so the sizes always total the budget.
static func plan(budget: int, rng: RandomNumberGenerator) -> Array[int]:
	var waves: Array[int] = []
	var left: int = maxi(budget, 0)
	while left > 0:
		var size: int = mini(rng.randi_range(MIN_WAVE, MAX_WAVE), left)
		waves.append(size)
		left -= size
	return waves


## Whether the next wave is due: the living count has fallen to NEXT_WAVE_SHARE of
## the enemies spawned so far (or below it).
static func next_wave_due(alive: int, spawned: int) -> bool:
	return float(alive) <= float(spawned) * NEXT_WAVE_SHARE
