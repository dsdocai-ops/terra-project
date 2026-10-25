class_name VenomGlandEffect
extends Effect
## Venom Gland — design doc 9.1 no. 10: "hits apply Toxin". Owned by relics
## (W4-B6, goal G6).
##
## Every hit this player lands applies `HIT_STATUS` — `TOXIN` — to the enemy it
## landed on, through `Effect.apply_status()`, the one path a status is applied
## by in this system. What the venom then does — its tick, its healing penalty,
## its combo — is the status's own (SPEC-stats-status, W4-B4), so the relic owns
## the application and nothing else: it deals no damage of its own and spawns
## nothing, which is exactly what the case asserts.
##
## The data file carries `poison` as its first tag, so SPEC-art-audio's
## `relic_proc_<tag>` rule names its proc `relic_proc_poison` — the venom it
## applies rather than the trigger it hangs off.
##
## **Which hits count.** This player's `proc_depth == 0` hits — the weapon-class
## ones — for the reason Echo Blade documents: `hit_landed` carries no `Player`
## argument for `Effect.listen()` to filter on, and a relic's own proc must not
## poison through another relic's application.
##
## `max_stacks = 1` in the data file: "hits apply Toxin" is a statement about
## what a hit does, not about a count, so a second copy has nothing to deepen;
## the number of stacks the venom holds belongs to `TOXIN`.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). Stacks reach clients
## through the entity's replicated `StatusEffects`.

## The status a hit applies. Design doc 9.1 no. 10: "hits apply Toxin", and the
## data file's description names the same Toxin.
const HIT_STATUS: StatusEffects.Status = StatusEffects.Status.TOXIN
## How many stacks one hit applies. One hit, one application; the venom's own
## tick is what the count belongs to.
const TOXIN_STACKS: int = 1


func _on_attach() -> void:
	listen(Events.hit_landed, _on_hit_landed)


## One of this player's own hits: leave the venom on the enemy it landed on.
func _on_hit_landed(hit: HitInfo) -> void:
	if not _is_my_hit(hit):
		return
	apply_status(hit.target, HIT_STATUS, TOXIN_STACKS)


## True when `hit` is a hit this effect's own player landed, and not one of the
## procs this player's own effects produced.
func _is_my_hit(hit: HitInfo) -> bool:
	if player == null or hit == null or hit.owner_player != player:
		return false
	return hit.proc_depth == 0