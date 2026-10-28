class_name ReviveHold
extends RefCounted
## The local hold-F revive (SPEC-player-controller "Downed and revive", W3-A5):
## a standing reviver holding `interact` beside a downed teammate banks the
## hold on the teammate's `DownedClock` (`scripts/player/downed_clock.gd`,
## G13a1) through the Interactable the downed player carries while down
## (G13b1, `scripts/components/interactable.gd`). Owned by player-controller.
## Sync: none in here. The hold runs on the reviver's machine and the clock on
## the host's (a downed player's bleed-out and hold are host decisions); a
## completed hold emits `completed`, which the revive path (W3-B4) connects —
## this driver stands nobody up itself and applies no HP.
##
## The clock is ticked by the host's `Player.tick_downed`, one tick per frame;
## this driver never ticks it, so a hold banks exactly once per frame. Every
## rule takes `held` as a plain bool — the input half (G13b2b) routes the live
## `interact` action into it, so the whole driver is testable with no input
## event.
##
## Known limit, deliberate until W3-B4: the driver runs on every peer's local
## player, but only the host's `tick_downed` ticks a clock. A client's hold
## banks onto the client's own copy of the teammate's clock, which nothing
## ticks there — a client-side hold looks live and can never reach
## `hold_complete`, so it emits no `completed` and stands nobody up. The
## client route (the local hold feeding a revive request) is W3-B4's.

## Emitted once per completed hold: the teammate the hold stood up and the
## reviver that held it. The revive itself (the 40% restore, the broadcast to
## the other peers) is the revive path's, not this driver's.
signal completed(revived: Player, by: Player)

## World px the reviver may stand from the downed teammate (SPEC: "within
## 48 px"). NetworkManager.REVIVE_RANGE holds the same number for the host's
## revive rule; the copies cannot drift while the tests compare them.
const REVIVE_RANGE: float = 48.0

## The prompt the downed player's Interactable shows ("[F] Revive").
const PROMPT_TEXT: String = "Revive"

## Radius of the shape on the downed player's Interactable, in world px. The
## nearest query filters on the centre distance (REVIVE_RANGE), so the shape
## only has to reach the reviver's query circle to be seen at all.
const INTERACTABLE_SHAPE_RADIUS: float = 16.0

## The player holding `interact`. Null while no pair is bound.
var reviver: Player = null
## The downed teammate the hold banks onto. Null while no pair is bound.
var target: Player = null


## The downed teammate a reviver standing at their own position would hold, or
## null: the closest usable Interactable within REVIVE_RANGE (the G13b1 query
## with the revive reach passed in) whose area hangs on a revivable Player.
## The downed player's own component is the offer; a duck-typed interactable
## (Rope, Chest, ...) resolves to no Player and is skipped.
static func find_target(reviver: Player) -> Player:
	if reviver == null or not reviver.is_inside_tree():
		return null
	var area := Interactable.nearest(reviver, reviver.global_position, REVIVE_RANGE)
	if area == null:
		return null
	var holder := area.get_parent() as Player
	return holder if is_revivable(holder) else null


## True when `player` can be revived right now: downed and not dead for the
## floor (SPEC: a teammate that bled out "is Dead for the rest of the floor").
static func is_revivable(player: Player) -> bool:
	return player != null and is_instance_valid(player) \
			and player.is_downed and not player.is_dead


## Binds the pair a hold runs between. Refused — and the old binding dropped —
## unless the target is revivable and the reviver is a different, standing
## player. The host's revive rule (NetworkManager.revive_refusal_reason)
## re-checks everything at apply time; this only gates which attempt a hold
## can even begin on. Returns false when refused.
func bind(from: Player, to: Player) -> bool:
	if from == null or not is_instance_valid(from) or from.is_downed or from.is_dead:
		unbind()
		return false
	if not is_revivable(to) or to == from:
		unbind()
		return false
	reviver = from
	target = to
	return true


## Drops the pair. Any running hold was broken by the caller first.
func unbind() -> void:
	reviver = null
	target = null


## True while a reviver and a downed target are bound.
func is_bound() -> bool:
	return reviver != null and target != null


## True while the reviver stands within REVIVE_RANGE of the target. Global
## positions, the same measure `find_target`'s query filters on — plain
## `position` agrees only while both players' parent sits at the origin.
func in_range() -> bool:
	if not is_bound():
		return false
	return reviver.global_position.distance_to(target.global_position) <= REVIVE_RANGE


## The reviver starts holding: the target's clock banks against the reviver's
## own scaled hold. False when there is no bound pair, the reviver is out of
## range, or a hold is already running.
func start_hold() -> bool:
	if not is_bound() or not in_range() or target.downed_clock.holding():
		return false
	target.downed_clock.begin_hold(reviver.revive_speed_mult)
	return true


## The reviver let go or walked out of range. A hold is a continuous hold:
## the clock banks nothing, and the next attempt starts from zero.
func release_hold() -> void:
	if is_bound():
		target.downed_clock.break_hold()


## The reviver can no longer hold — downed or dead mid-hold. Breaks the hold
## and drops the pair, exactly as a released hold does. The Player calls this
## when its own `step` stops running (a downed reviver's `_tick_combat_timers`
## no longer reaches it): the host keeps ticking a downed teammate's clock, so
## a hold left running there would bank time nobody held and complete the
## revive the moment the reviver stood back up.
func abandon() -> void:
	release_hold()
	unbind()


## One frame of the hold. With `held`, keeps a bound, in-range hold running
## (starting one if none is) and reports a completion; without it, or when the
## reviver left the range or the target is no longer revivable, breaks the
## hold — banks nothing. Returns true exactly once per completed hold. Never
## ticks the clock: the host's `Player.tick_downed` does, one tick per frame.
func step(from: Player, held: bool) -> bool:
	if not held:
		if is_bound():
			release_hold()
			unbind()
		return false
	if not is_bound() and not bind(from, find_target(from)):
		return false
	if not is_revivable(target):
		release_hold()
		unbind()
		return false
	if not in_range():
		# Walked out mid-hold: the hold breaks, the pair stays bound so
		# stepping back in resumes the attempt from zero.
		release_hold()
		return false
	if not target.downed_clock.holding():
		start_hold()
	return poll()


## True when the running hold has banked its full duration: emits `completed`
## once, drops the hold and the binding, and returns true. Every later poll is
## false until a new hold completes.
func poll() -> bool:
	if not is_bound() or not target.downed_clock.hold_complete():
		return false
	var stood_up: Player = target
	var by: Player = reviver
	release_hold()
	unbind()
	completed.emit(stood_up, by)
	return true
