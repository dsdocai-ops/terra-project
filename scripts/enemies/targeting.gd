class_name Targeting
extends RefCounted
## Pure target choice for the enemy base (SPEC-enemies-ai "Targeting"). Owned
## by enemies-ai. Sync: host-only — every caller runs on the host.
##
## Pure on purpose: `pick` sees plain values, never the tree, so the whole
## choice is testable without a floor or a session. A `Candidate` describes one
## possible target; `candidate(node)` builds one duck-typed from any Node2D —
## a Player (reads `is_dead` / `is_downed`), a FriendlyUnit minion or a decoy
## once those exist — so the spec's `pick(enemy, players, minions, decoys)` is
## one call with the lists merged.
##
## The choice, in order:
## 1. A taunting candidate always wins (Battle Cry, Frozen Clone, Decoy
##    Lantern, minion taunt node): the nearest among the taunting ones. How
##    long a taunt lasts is the taunt source's clock — the candidate only
##    reports that it is taunting now.
## 2. Otherwise the spread (co-op, SPEC "spread aggro so one player is not
##    focused unless taunting"): among the live candidates inside
##    SPREAD_FACTOR of the nearest distance, the one carried by the fewest
##    `targeters` wins — distance breaks the tie, then input order. The
##    caller fills `targeters` from the pack's current targets, not counting
##    this enemy's own hold, so a fresh enemy joins the player the pack is
##    not focused on instead of piling onto the nearest one, and a pack that
##    picked different players holds them instead of collapsing onto one.
## 3. Hysteresis: the current target is kept while it sits inside the same
##    spread window and no candidate inside it is carried by fewer enemies.
##    Untargetable candidates (Smoke Step / Smoke Bomb / Vanish / Ghost Wrap
##    set the `untargetable` property) are not candidates at all, and when
##    nothing live remains `pick` returns null — that is "drop aggro".

## How much farther than the nearest a candidate may sit and still compete in
## the spread (rules 2 and 3 above).
const SPREAD_FACTOR: float = 1.25

class Candidate:
	## The node behind the candidate, so the pick can name a target and the
	## spread can recognise the current one. Null is allowed for hand-built
	## candidates (a pick that never sees `current` cannot spread anyway).
	var node: Node2D = null
	var position: Vector2 = Vector2.ZERO
	## Dead anything and downed players are not targeted.
	var alive: bool = true
	## Smoke Step / Smoke Bomb / Vanish / Ghost Wrap set this on the player
	## node — the interface those effects were waiting for. A set flag is
	## invisible to `pick`, which is how aggro drops.
	var untargetable: bool = false
	## A taunt in force right now; its duration is the taunt source's clock.
	var taunting: bool = false
	## How many enemies of the pack currently hold this candidate, not
	## counting the picking enemy's own hold (the caller's job — see rule 2).
	## 0 is the unloaded, joinable target.
	var targeters: int = 0


## Builds a candidate duck-typed from any target node: `is_dead` and
## `is_downed` mark it dead, `untargetable` and `taunting` carry the status
## flags. A node without a property reads as false.
static func candidate(node: Node2D) -> Candidate:
	var c := Candidate.new()
	c.node = node
	c.position = node.global_position
	c.alive = not (node.get("is_dead") == true or node.get("is_downed") == true)
	c.untargetable = node.get("untargetable") == true
	c.taunting = node.get("taunting") == true
	return c


## The chosen candidate, or null when nothing live and targetable remains.
## `current` is this enemy's target from the last pick (the hysteresis keeps
## it); ties break by input order, deterministically.
static func pick(from: Vector2, current: Node2D, candidates: Array[Candidate]) -> Candidate:
	var live: Array[Candidate] = []
	for c: Candidate in candidates:
		if c.alive and not c.untargetable:
			live.append(c)
	if live.is_empty():
		return null
	var taunt: Candidate = null
	for c: Candidate in live:
		if c.taunting and (taunt == null or _dist(from, c) < _dist(from, taunt)):
			taunt = c
	if taunt != null:
		return taunt
	var nearest: Candidate = live[0]
	for c: Candidate in live:
		if _dist(from, c) < _dist(from, nearest):
			nearest = c
	var window_range: float = _dist(from, nearest) * SPREAD_FACTOR
	var best: Candidate = null
	for c: Candidate in live:
		if _dist(from, c) > window_range:
			continue
		if best == null or c.targeters < best.targeters \
				or (c.targeters == best.targeters and _dist(from, c) < _dist(from, best)):
			best = c
	var held := _held(live, current)
	if held != null and _dist(from, held) <= window_range and held.targeters <= best.targeters:
		return held
	return best


static func _held(live: Array[Candidate], current: Node2D) -> Candidate:
	if current == null:
		return null
	for c: Candidate in live:
		if c.node == current:
			return c
	return null


static func _dist(from: Vector2, c: Candidate) -> float:
	return from.distance_to(c.position)
