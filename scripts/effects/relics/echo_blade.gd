class_name EchoBladeEffect
extends Effect
## Echo Blade — design doc 9.1 no. 7: "every 4th hit strikes twice". Owned by
## relics (W4-B6, goal G6).
##
## It counts the hits its own player lands and, on every `HITS_PER_ECHO`-th of
## them, strikes the same enemy a second time: one `deal_damage()` onto the hit's
## own `target` carrying the hit's own damage shape. The design doc's word is
## "strikes twice", not "strikes for a fraction", so the echo is a whole hit and
## the case asserts exactly that. The counter is the relic's and is per effect —
## `hits_counted()` reads it — not per enemy: the design doc counts hits,
## whatever they land on.
##
## **Which hits count.** A hit is *this player's* when its `owner_player` is this
## effect's player, and it is a *hit* rather than a proc one of this player's
## effects caused when its `proc_depth` is 0. The first half is a field read
## because `hit_landed` carries no `Player` argument for `Effect.listen()`'s
## filter to match (SPEC-effect-system's signal table: "hit_landed(hit: HitInfo)");
## the second is the same rule `Effect._forward()` applies to a chain as a whole,
## read one link earlier, so two On Hit relics on one player cannot feed each
## other's counters with their own procs.
##
## **The echo is tagged and one link deeper.** Its payload carries this effect's
## own id, so the echo's own `hit_landed` — the real hurtbox announces every hit
## it delivers — is dropped by `Effect._forward()`'s no-self-retrigger rule
## (SPEC-effect-system, "Proc chain limits", rule 2) and cannot echo again; and
## `deal_damage()` stamps it `proc_depth = 1`, one link past the hit that caused
## it, plus the `proc` tag.
##
## `max_stacks = 1` in the data file: the design doc gives the relic no stack
## rule, and one effect holds the counter.
##
## Sync: host-only. SPEC-relics — "Rolls, picks, attaches, actives, synergy
## evaluation: host." The echo is a host-dealt hit, which reaches clients exactly
## the way a weapon's own hit does.

## How many of this player's hits it takes to earn the second strike. Design doc
## 9.1 no. 7: "every 4th hit", and the data file's description states the same
## 4th.
const HITS_PER_ECHO: int = 4

## The hits this effect has counted since it attached. Per effect, so a Mimic
## Crown copy counts its own rather than sharing the original's.
var _hits_counted: int = 0


func _on_attach() -> void:
	listen(Events.hit_landed, _on_hit_landed)


## The hits counted so far — the reading the batch's combined case takes.
func hits_counted() -> int:
	return _hits_counted


## One of this player's own hits: count it, and answer every fourth one with a
## second strike on the same enemy.
func _on_hit_landed(hit: HitInfo) -> void:
	if not _is_my_hit(hit):
		return
	_hits_counted += 1
	if _hits_counted % HITS_PER_ECHO != 0:
		return
	deal_damage(hit.target, _echo_of(hit))


## True when `hit` is a hit this effect's own player landed, and not one of the
## procs this player's own effects produced. The three-line filter every On Hit
## relic of the batch writes, because the base class's player filter has no
## `Player` argument to read on this signal.
func _is_my_hit(hit: HitInfo) -> bool:
	if player == null or hit == null or hit.owner_player != player:
		return false
	return hit.proc_depth == 0


## The blow this effect deals in answer: the triggering hit's damage shape,
## re-delivered, aimed at the enemy that took the first one. Built new rather
## than passed along — the triggering hit has already been computed and applied,
## and `deal_damage` stamps the depth and the `proc` tag on what it is handed. A
## forced crit, a mark's consumption and the computed `is_crit`/`final_damage`
## belong to the hit that already landed, so they are not copied.
func _echo_of(hit: HitInfo) -> HitInfo:
	var echo := HitInfo.new()
	echo.base_damage = hit.base_damage
	echo.multiplier = hit.multiplier
	echo.bonus_crit_chance = hit.bonus_crit_chance
	echo.element = hit.element
	echo.is_heavy = hit.is_heavy
	echo.from_behind = hit.from_behind
	echo.scales_with_ability_power = hit.scales_with_ability_power
	echo.owner_player = player
	echo.target = hit.target
	var own_tag: Array[StringName] = [source_id()]
	echo.tags = own_tag
	return echo