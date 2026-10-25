class_name SparkPlugEffect
extends Effect
## Spark Plug — design doc 9.1 no. 8: "10% chance on hit to fire chain
## lightning". Owned by relics (W4-B6, goal G6).
##
## On one of its own player's hits it rolls `CHAIN_CHANCE` — the 10 % the data
## file's description states — and when the roll comes good it applies
## `CHAIN_STATUS` to the enemy the hit landed on. The lightning is that status:
## the arc from enemy to enemy and the damage the arc does are `SHOCK`'s own
## behaviour, which stats-status owns (SPEC-stats-status: a chained application),
## so the relic's whole job is to light it and the status carries it from there.
##
## **Where the roll comes from.** `Effect.chance()`, the host-side helper: the
## two extremes short-circuit without drawing, so a case forcing the roll to 0 or
## 1 consumes nothing and one relic's certainty cannot shift another's stream,
## and everything between them draws from the run's generator, so one seed
## replays a run. `chain_chance` is the injection point a case forces; the
## relic's own value is the constant.
##
## **What this effect does not do.** It deals no damage of its own and spawns
## nothing: the design doc's "fire chain lightning" is a status application in
## this system — statuses are what arc, tick and combo — and a second lightning
## system beside them would be the "new system for one item" SPEC-project
## forbids. The data file's `relic_proc_storm` names the VFX the proc plays
## (SPEC-art-audio's `relic_proc_<tag>` rule, its first tag being `storm`); the
## scene itself belongs to art-audio's library.
##
## **Which hits count.** This player's `proc_depth == 0` hits — the weapon-class
## ones — for the reason Echo Blade documents: `hit_landed` carries no `Player`
## argument for `Effect.listen()` to filter on, and a relic's own proc must not
## roll another relic's chance.
##
## `max_stacks = 1` in the data file: the design doc gives no stack rule, and a
## second copy of a chance relic is a second roll rather than a deeper one.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). The status reaches
## clients through the entity's replicated `StatusEffects` stacks.

## The chance one of this player's hits chains. Design doc 9.1 no. 8: "10%
## chance", and the data file's description states the same 10%.
const CHAIN_CHANCE: float = 0.10
## The status a chained hit applies. The design doc's "chain lightning" is this
## system's `SHOCK` — the status `Effect`'s own docs name as the one stats-status
## chains on application.
const CHAIN_STATUS: StatusEffects.Status = StatusEffects.Status.SHOCK
## How many stacks one chain applies. A hit chains or it does not; how far the
## arc travels belongs to `SHOCK`.
const CHAIN_STACKS: int = 1

## The chance this instance rolls, so a case can force the roll good or bad. The
## relic's own value is `CHAIN_CHANCE`, which is what an untouched relic reads.
var chain_chance: float = CHAIN_CHANCE


func _on_attach() -> void:
	listen(Events.hit_landed, _on_hit_landed)


## One of this player's own hits: roll, and light the chain when it comes good.
func _on_hit_landed(hit: HitInfo) -> void:
	if not _is_my_hit(hit):
		return
	if not chance(chain_chance):
		return
	apply_status(hit.target, CHAIN_STATUS, CHAIN_STACKS)


## True when `hit` is a hit this effect's own player landed, and not one of the
## procs this player's own effects produced.
func _is_my_hit(hit: HitInfo) -> bool:
	if player == null or hit == null or hit.owner_player != player:
		return false
	return hit.proc_depth == 0