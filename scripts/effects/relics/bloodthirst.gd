class_name BloodthirstEffect
extends Effect
## Bloodthirst — design doc 9.1 no. 17: "kills give +10% attack speed for 3s
## (stacks 5x)". Owned by relics (W4-B6, goal G8a).
##
## Each of this player's kills adds a stack of the buff and puts
## `PER_KILL_BONUS` (the description's "10%") per stack onto the player's
## `ATTACK_SPEED`, through a `StatBlock` modifier. The whole buff lapses three
## seconds after the last kill: `BLOODTHIRST_SECONDS` is the description's "3s"
## and `MAX_STACKS` its "(stacks 5x)".
##
## **One buff, restarted, rather than one per kill.** A kill while the buff is
## up deepens the stacks and restarts the clock from that kill, so five kills in
## a row read as five stacks for three seconds and then leave together — the
## description's "for 3s (stacks 5x)" read as one buff that the kills keep
## feeding, not five overlapping timers whose earliest expiry would drop the
## player back to a lower bonus mid-fight. `_clock` is the one timer the base
## parented, restarted rather than re-created, so `detach()` frees exactly one.
##
## **The cap is the doc's number, and so is the relic's stack rule.** Reading
## "(stacks 5x)" twice — as the buff's own cap and as the relic's `max_stacks` —
## is deliberate: the number has one home in the doc, and a second copy of the
## relic is then worth holding, because `stacks_per_kill()` adds one stack per
## copy (the reading Soul Jar's `charge_per_kill()` established). A five-copy
## Bloodthirst fills the five-stack cap in one kill. It is a balance call this
## lane made and the design doc does not state; the week-12 pass owns it.
##
## **`StatBlock` modifier, never a base stat.** `Effect.modify()` records its
## handle for `detach()` but does not hand it back, and this buff has to come off
## when its three seconds lapse — long before the relic is ever detached — so the
## modifier is added through `StatBlock.add_modifier()` here and removed by the
## handle it returns, in `_expire()` and again in `_on_detach()`. Nothing here
## writes a base value, and the engine's own time scale is never reached for — the
## buff's three seconds run on the plain one-shot timer `_start_timer()` parented.
##
## **Which kills count.** This player's, read off `hit.owner_player`, for the
## reason the rest of the On Kill batch reads it: `enemy_killed` is emitted by the
## dying enemy (Dev A, W4-A4) and carries no `Player` argument for
## `Effect.listen()`'s filter, so a teammate's kill and an unattributed one must
## be told apart here.
##
## **The batch note: `elite_killed` is not a second death.** This relic listens on
## `enemy_killed` and knows nothing about elites — an elite's death is a death,
## and it counts once. SPEC-enemies-ai is why: "Elite death emits
## `Events.elite_killed` for `run-economy` (loot, Echo Shards) and Trophy Belt",
## and its "Events emitted" list carries `enemy_killed` beside `elite_killed`,
## so the bus announces every death on the kill signal and names the
## elite-specific consumers on the other. Every relic in this batch but Trophy
## Belt listens on `enemy_killed`, and Trophy Belt alone on `elite_killed`; none
## listens on both, so no elite death is counted twice. **If W4-A4 lands and an
## elite's death is announced on `elite_killed` *instead of* `enemy_killed`**, the
## fix is one line in each of the three (`listen(Events.elite_killed, …)` beside
## the existing `listen()`), and the batch's shared case fires both signals for one
## corpse and asserts one stack, one flower and one spread — so the swap breaks a
## test loudly rather than double-counting a year of elites silently.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). The stacks are host
## state and are not replicated; `buff_stacks()` is the read the HUD strip
## (goal G19) draws and the batch's cases assert.

## The attack speed one stack grants. Design doc 9.1 no. 17: "+10% attack speed"
## — and the data file's description states the same 10%.
const PER_KILL_BONUS: float = 0.10
## How long the buff stands after the last kill that fed it, in seconds. The same
## line's "for 3s".
const BLOODTHIRST_SECONDS: float = 3.0
## How deep the buff stacks. The same line's "(stacks 5x)", and the number the
## data file's `max_stacks` also carries.
const MAX_STACKS: int = 5

## The stacks the buff is currently holding, 0 when it is not up.
var _stacks: int = 0
## The `StatBlock` handle of the buff's modifier, or -1 when none is on the
## player. Kept here rather than in the base's `_handles` so `_expire()` can take
## the one modifier back without waiting for `detach()`.
var _handle: int = -1
## The one-shot clock the buff runs on, parented to this effect by
## `Effect._start_timer()`. Restarted on every kill, freed by `detach()`.
var _clock: Timer = null


func _on_attach() -> void:
	listen(Events.enemy_killed, _on_enemy_killed)


## Takes the buff back when the relic is dropped mid-fight: the base has already
## freed the clock by the time this runs, so nothing re-arms it, and a player who
## sells Bloodthirst does not keep its attack speed.
func _on_detach() -> void:
	_stacks = 0
	_release_bonus()


## The stacks the buff is holding right now — the read the HUD strip (G19) draws
## and the batch's cases assert 1 and 5 against.
func buff_stacks() -> int:
	return _stacks


## How many stacks one kill grants. One per copy of the relic: `max_stacks = 5`,
## so five copies fill the buff's own five-stack cap at once.
func stacks_per_kill() -> int:
	return maxi(stacks, 1)


## The attack-speed percentage the buff is currently granting, as a fraction.
func bonus() -> float:
	return PER_KILL_BONUS * float(_stacks)


## One of this player's kills: deepen the buff, and restart its clock.
func _on_enemy_killed(enemy: Node, hit: HitData) -> void:
	if not _is_my_kill(enemy, hit):
		return
	_stacks = mini(_stacks + stacks_per_kill(), MAX_STACKS)
	_apply_bonus()
	_arm_clock()


## True when `enemy` is a valid node and `hit` is this player's own kill. The
## `owner_player` read is the payload's, not a signal argument: `enemy_killed`
## carries no `Player` for `Effect.listen()` to filter on.
func _is_my_kill(enemy: Node, hit: HitData) -> bool:
	if player == null or enemy == null or not is_instance_valid(enemy):
		return false
	if hit == null:
		return false
	return hit.owner_player == player


## Puts the current stack count on the player's attack speed: the old modifier
## comes off first, so the buff is always exactly one modifier carrying the whole
## bonus rather than a fresh row per kill.
func _apply_bonus() -> void:
	if stat_block == null:
		push_warning("[effect] %s: no StatBlock on the player, buff not applied" % source_id())
		return
	_release_bonus()
	_handle = stat_block.add_modifier(StatBlock.Stat.ATTACK_SPEED, 0.0, bonus(), source_id())


## Removes the buff's modifier, if one is on the player. Unknown handles are
## `StatBlock`'s own no-op, so this is safe after `remove_source()` or a detach.
func _release_bonus() -> void:
	if _handle >= 0 and stat_block != null:
		stat_block.remove_modifier(_handle)
	_handle = -1


## Arms the three seconds, on the clock the last kill already started when there
## is one: restarting keeps a single timer per effect — the base frees one node
## at detach — and makes the window three seconds from the *latest* kill.
func _arm_clock() -> void:
	if _clock != null and is_instance_valid(_clock):
		_clock.start(BLOODTHIRST_SECONDS)
		return
	_clock = _start_timer(BLOODTHIRST_SECONDS, Callable(self, &"_expire"))


## The window of three seconds closed: the stacks leave together with the
## modifier. The clock stays parented and stopped, ready for the next kill.
func _expire() -> void:
	_stacks = 0
	_release_bonus()
