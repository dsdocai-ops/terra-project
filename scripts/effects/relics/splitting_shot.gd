class_name SplittingShotEffect
extends Effect
## Splitting Shot — design doc 9.1 no. 11: "projectiles split into 3 on hit".
## Owned by relics (W4-B6, goal G6).
##
## Every hit this player lands asks the projectile seam for `SPLIT_COUNT` — 3 —
## projectiles, fanned `SPLIT_SPREAD_DEGREES` wide around the direction the hit
## travelled (from the player to the enemy it landed on), each carrying
## `SPLIT_DAMAGE_FRACTION` of the hit's own damage and the element it carried.
## The split is asked for through `Effect.fire_projectile()`, the one seam an
## effect fires through, so the relic never instantiates a projectile itself and
## never names a scene by path.
##
## **What the split's body is not owed by this lane.** `blocked on Dev A
## (W2-A6, combat-core's `Projectile`)`: the thing that flies, its collision and
## its bounce are combat-core's, so each spec this effect hands over carries
## `scene = null` — the legal "numbers, no body" form `ProjectileSpec` documents
## — and the projectile scene is filled in by that module when it lands, not by a
## relic reaching for a scene it does not own. The case asserts exactly that: the
## ask, and that the spec is scene-less.
##
## Each shot is stamped by `fire_projectile()` with this effect's id and
## `proc_depth = 1` — one link past the hit that caused it — so a split's own hit
## is tagged with this relic and rule 2 stops it splitting again: the three of
## one hit are all fired from the *triggering* hit, never from each other, which
## is what keeps "split into 3" a burst rather than a tree.
##
## `max_stacks = 1` in the data file: the design doc gives the relic no stack
## rule, and a second copy would be three more projectiles rather than a deeper
## single split.
##
## Sync: host-only. SPEC-relics — "Rolls, picks, attaches, actives, synergy
## evaluation: host." The specs are built on the host; each shot reaches clients
## through the projectile spawner's own replication (networking, W2-B3).

## How many projectiles one hit splits into. Design doc 9.1 no. 11: "split into
## 3", and the data file's description states the same 3.
const SPLIT_COUNT: int = 3
## What fraction of the triggering hit's damage each split carries. The design
## doc gives no number for it: 0.5 each is this batch's choice — the burst is
## worth 1.5 hits on one target and less than that spread over three, which is
## the trade the description's "split" implies — and it is recorded as a decision
## in HANDOFF.md for the week-12 balance pass to own.
const SPLIT_DAMAGE_FRACTION: float = 0.5
## How wide the fan is, in degrees, centred on the hit's own direction. The
## design doc gives no number; 30 degrees is this batch's choice, recorded as a
## decision in HANDOFF.md.
const SPLIT_SPREAD_DEGREES: float = 30.0
## How fast a split flies, in pixels per second. `ProjectileSpec` needs a speed
## and the design doc gives none, so this is a placeholder standing in for
## combat-core's own number (**blocked on Dev A, W2-A6**): the spec still travels
## whole, and that module's figure replaces this one when it lands.
const SPLIT_SPEED: float = 320.0
## How many targets a split passes through before it stops. A split is a fresh
## shot, not a piercing one, so it stops on the first thing it touches; the
## number lives here so the spec is written from a named value rather than a
## bare `0` at the call site.
const SPLIT_PIERCE: int = 0
## The axis a split sprays along when it has nothing to aim at: the hit's enemy
## carries no position (a payload built by something that is not a `Node2D`, or
## one whose target is already gone), so the spray goes along the player's own
## facing rather than nowhere. `Player.facing` is the facing Player's
## controller publishes; the relic reads it and never writes it.
const FALLBACK_FORWARD: Vector2 = Vector2.DOWN


func _on_attach() -> void:
	listen(Events.hit_landed, _on_hit_landed)


## One of this player's own hits: split it, three ways, along the line it
## travelled.
func _on_hit_landed(hit: HitData) -> void:
	if not _is_my_hit(hit):
		return
	var origin: Vector2 = _impact_of(hit)
	var axis: Vector2 = _axis_of(hit, origin)
	for i: int in SPLIT_COUNT:
		fire_projectile(_spec_for(hit), origin, axis.rotated(deg_to_rad(_offset_degrees(i))))


## Where the hit landed: the enemy's own position when the payload names one
## that has one, otherwise this player's — a split sprays from the player when
## the payload cannot say where it struck, rather than inventing a point.
func _impact_of(hit: HitData) -> Vector2:
	if hit.target is Node2D:
		return (hit.target as Node2D).global_position
	if player != null:
		return player.global_position
	return Vector2.ZERO


## Which way the hit was travelling: from this player toward the point it landed
## on, so the burst goes on past the enemy rather than back through the shooter.
## Falls back to the player's facing when the two points coincide (a melee hit
## landed on top of the attacker, a payload with no positioned target), and to
## `FALLBACK_FORWARD` when even that has no length.
func _axis_of(hit: HitData, origin: Vector2) -> Vector2:
	if player == null:
		return FALLBACK_FORWARD
	var along: Vector2 = origin - player.global_position
	if along.length() > 0.0:
		return along.normalized()
	if player.facing.length() > 0.0:
		return player.facing.normalized()
	return FALLBACK_FORWARD


## How far the `i`-th split is turned from the axis: the fan is centred on it, so
## the three go out at -half, 0 and +half the spread. A single split (a data file
## that changed `SPLIT_COUNT`) sits on the axis rather than dividing by zero.
func _offset_degrees(index: int) -> float:
	if SPLIT_COUNT <= 1:
		return 0.0
	var step: float = SPLIT_SPREAD_DEGREES / float(SPLIT_COUNT - 1)
	return -SPLIT_SPREAD_DEGREES * 0.5 + step * float(index)


## The spec one split flies with: the triggering hit's element and a fraction of
## its damage, and no scene — the projectile's body is combat-core's (W2-A6).
func _spec_for(hit: HitData) -> ProjectileSpec:
	var spec := ProjectileSpec.new()
	spec.speed = SPLIT_SPEED
	spec.damage = hit.base_damage * SPLIT_DAMAGE_FRACTION
	spec.element = hit.element
	spec.pierce = SPLIT_PIERCE
	spec.scene = null
	return spec


## True when `hit` is a hit this effect's own player landed, and not one of the
## procs this player's own effects produced — which is what keeps a split from
## splitting itself.
func _is_my_hit(hit: HitData) -> bool:
	if player == null or hit == null or hit.owner_player != player:
		return false
	return hit.proc_depth == 0