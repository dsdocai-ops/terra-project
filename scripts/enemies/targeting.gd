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
## 2. Otherwise the nearest live candidate. Untargetable candidates (Smoke
##    Step / Smoke Bomb / Vanish / Ghost Wrap set the `untargetable` property)
##    are not candidates at all, and when nothing live remains `pick` returns
##    null — that is "drop aggro".
## 3. Spread (co-op): an enemy keeps its current target while that target
##    stays within SPREAD_FACTOR of the nearest live distance, so a pack that
##    picked different players holds them instead of collapsing onto one. A
##    fresh enemy, or one whose target left the window, picks the nearest.

## How much farther than the nearest a kept target may sit and still be kept
## (the spread hysteresis, rule 3 above).
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
## `current` is this enemy's target from the last pick (the spread keeps it);
## ties break by input order, deterministically.
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
	if current != null:
		for c: Candidate in live:
			if c.node == current:
				if _dist(from, c) <= _dist(from, nearest) * SPREAD_FACTOR:
					return c
				break
	return nearest


static func _dist(from: Vector2, c: Candidate) -> float:
	return from.distance_to(c.position)
