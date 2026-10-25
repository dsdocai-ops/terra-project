class_name TrophyBeltEffect
extends Effect
## Trophy Belt — design doc 9.1 no. 20: "every elite killed gives +3% damage for
## the rest of the run". Owned by relics (W4-B6, goal G8a).
##
## Each elite this player kills adds `PER_ELITE_BONUS` to the player's `ATTACK`,
## through one `StatBlock` modifier that is re-set to the new total on every
## kill. The accumulation is the relic's own per-run state: nothing resets it
## while the relic is held — not a room, not a floor — which is the doc's "for
## the rest of the run", and the batch's case walks it across a `room_entered`
## and a `floor_entered` to prove it.
##
## **The signal is `elite_killed`, and SPEC-enemies-ai names this relic for it.**
## "Elite death emits `Events.elite_killed` for `run-economy` (loot, Echo Shards)
## and Trophy Belt" — the relic is one of the two consumers that sentence
## exists for, so this is the one relic in the batch that does not hang off
## `enemy_killed`. A plain kill does not count: the batch's case fires an ordinary
## kill at an elite-flagged enemy and asserts the count does not move. The
## `elite_killed` payload has the same shape `enemy_killed` does —
## `(enemy: Node, hit: HitInfo)` and no `Player` argument — so "which kills count"
## is the killing hit's `owner_player` here too: **blocked on Dev A (W4-A1)** for
## the emitter and the elite it comes from.
##
## **One modifier, re-set, rather than one row per elite.** `Effect.modify()`
## records a handle for `detach()` but does not hand it back, and this relic's
## total has to change on every kill — a fresh `modify()` per elite would leave
## one modifier row per elite in the player's `StatBlock` for the rest of the run
## (hundreds over a deep run, each walked by every stat read). So the row is added
## through `StatBlock.add_modifier()` and re-added by handle, exactly as
## Bloodthirst does with its timed buff: `_handle` is the one row carrying
## `PER_ELITE_BONUS * elites_killed`, and `_release_bonus()` takes it off in
## `_on_detach()`. Nothing here writes a base stat, and the engine's own time scale
## is never reached for: no clock of any kind is involved.
##
## **`max_stacks = 1` in the data file, and the run is where the stacking is.**
## No. 20's sentence has no per-copy term — the thing that accumulates is the
## elite count, not the copy count — so a second Trophy Belt is not allowed to
## hold a second accumulation. `damage_bonus()` and `elites_killed()` are the
## published reads the HUD strip (goal G19) draws.
##
## **Reset on detach.** Per PLAN G8a: the accumulation is per-run state *on the
## effect*, so it dies with the relic — a player who sells the belt at a Shrine
## keeps neither the damage nor the count, and the next belt starts at nothing.
## The base frees the effect, so `_on_detach()` only has to take its own one
## modifier back and zero its own two fields.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). The count is host
## state and is not replicated; the damage itself reaches clients the way every
## other `StatBlock` modifier does, through the player's own replication.

## The damage one elite kill grants, as a fraction of the holder's attack. Design
## doc 9.1 no. 20: "+3% damage for the rest of the run" — and the data file's
## description states the same 3%.
const PER_ELITE_BONUS: float = 0.03

## How many elites this effect's holder has killed, ever.
var _elites_killed: int = 0
## The `StatBlock` handle of the relic's one modifier, or -1 when none is on the
## player. Kept here rather than in the base's `_handles` so the total can be
## replaced on every kill without growing the base's list.
var _handle: int = -1


func _on_attach() -> void:
	listen(Events.elite_killed, _on_elite_killed)


## Takes the run's accumulation back when the relic is dropped: the count and the
## damage both go, so the belt is worth nothing once it is gone.
func _on_detach() -> void:
	_elites_killed = 0
	_release_bonus()


## The elites this effect's holder has killed — the read the HUD strip (G19)
## draws and the batch's cases assert 0, 1, 2 and 3 against.
func elites_killed() -> int:
	return _elites_killed


## The damage bonus the run has accumulated, as a fraction of the holder's
## attack: `PER_ELITE_BONUS` per elite, with no cap.
func damage_bonus() -> float:
	return PER_ELITE_BONUS * float(_elites_killed)


## One of this player's elite kills: count it, and put the new total on the
## player's attack.
func _on_elite_killed(enemy: Node, hit: HitInfo) -> void:
	if not _is_my_kill(enemy, hit):
		return
	_elites_killed += 1
	_apply_bonus()


## True when `enemy` is a valid node and `hit` is this player's own kill. The
## `owner_player` read is the payload's, not a signal argument: `elite_killed`
## carries no `Player` for `Effect.listen()` to filter on, exactly as
## `enemy_killed` does not.
func _is_my_kill(enemy: Node, hit: HitInfo) -> bool:
	if player == null or enemy == null or not is_instance_valid(enemy):
		return false
	if hit == null:
		return false
	return hit.owner_player == player


## Puts the run's accumulated bonus on the player's attack as one modifier: the
## old row comes off first, so the belt is always exactly one row carrying the
## whole total.
func _apply_bonus() -> void:
	if stat_block == null:
		push_warning("[effect] %s: no StatBlock on the player, bonus not applied" % source_id())
		return
	_release_bonus()
	_handle = stat_block.add_modifier(StatBlock.Stat.ATTACK, 0.0, damage_bonus(), source_id())


## Removes the relic's modifier, if one is on the player. Unknown handles are
## `StatBlock`'s own no-op, so this is safe after a detach.
func _release_bonus() -> void:
	if _handle >= 0 and stat_block != null:
		stat_block.remove_modifier(_handle)
	_handle = -1
