class_name ReboundSpringEffect
extends Effect
## Rebound Spring — design doc 9.1 no. 6: "dodge distance doubled, dodging into
## walls bounces you off them". Owned by relics (W4-B6, goal G5).
##
## Two halves, and only one of them is a relic's to write:
##
## **The doubling** goes through the field SPEC-player-controller names for it —
## "Fixed distance (~96 px, Rebound Spring doubles via a stat-like multiplier
## exposed as `dodge_distance_mult`)" — so this effect does not edit a base stat
## (SPEC-project's hard rule) and does not reach into the Dodge state: it sets
## one multiplier the spec published for exactly this relic, and puts the
## previous value back when it detaches, so a relic dropped at a Shrine leaves
## the dodge the length it was.
##
## **The wall bounce** is the Dodge state's movement, which is player-controller's
## (Dev A). A relic cannot move the player, so on a dodge this effect asks a seam
## instead: a child of the player named `DodgeSeam` implementing
## `request_wall_bounce()`. **`blocked on Dev A (W2-A8, the Dodge state)`** — the
## node does not exist yet, so the ask is a guarded no-op and the bounce does not
## happen; when the Dodge state lands, the seam node comes with it and this
## effect needs no change. The look-up is by name and the call is guarded by
## `has_method()`, so a player without the seam is skipped rather than erroring,
## which is the same shape every other unlanded provider in this lane uses.
##
## `max_stacks = 1` in the data file, so there is no stacked multiplier to
## compose: the relic is either held ("doubled") or not.
##
## Sync: host-only. SPEC-relics — "Rolls, picks, attaches, actives, synergy
## evaluation: host." The dodge itself is replicated movement; this effect only
## decides how far it goes on the host that owns it.

## What "doubled" means: the dodge's distance multiplier while the relic is held.
## The design doc's word for it, and the data file's description uses the same
## word.
const DODGE_DISTANCE_MULTIPLIER: float = 2.0
## The name of the node this effect asks for the reflection. Named for the
## Dodge state it belongs to, so the look-up cannot collide with another seam.
const DODGE_SEAM_NAME: StringName = &"DodgeSeam"
## The method the seam node is asked through.
const WALL_BOUNCE_METHOD: StringName = &"request_wall_bounce"

## The multiplier the player had before this effect wrote its own, so detaching
## restores the dodge rather than assuming 1.0 — another relic or a mutation may
## hold a multiplier of its own.
var _multiplier_before: float = 1.0
## Whether this effect is the one currently holding the multiplier, so the
## restore happens exactly once.
var _multiplier_written: bool = false


func _on_attach() -> void:
	_double_the_dodge()
	listen(Events.player_dodged, _on_player_dodged)


## The doubling is not a trigger — it is the relic being held at all.
func _double_the_dodge() -> void:
	if player == null:
		return
	_multiplier_before = player.dodge_distance_mult
	player.dodge_distance_mult = DODGE_DISTANCE_MULTIPLIER
	_multiplier_written = true


## A dodge asks the Dodge state to bounce off whatever wall it hit.
func _on_player_dodged(_player: Player, _perfect: bool) -> void:
	var seam: Node = _dodge_seam()
	if seam == null:
		return
	seam.call(WALL_BOUNCE_METHOD)


## Hands the dodge back its own distance. Runs after the base teardown, which is
## why nothing here registers a modifier or a timer of its own.
func _on_detach() -> void:
	if _multiplier_written and player != null:
		player.dodge_distance_mult = _multiplier_before
	_multiplier_written = false


## The Dodge state's seam on this effect's player, or null when there is none
## yet (**blocked on Dev A, W2-A8**) or when the node there does not implement
## the ask.
func _dodge_seam() -> Node:
	if player == null:
		return null
	var seam: Node = player.get_node_or_null(NodePath(DODGE_SEAM_NAME))
	if seam == null or not seam.has_method(WALL_BOUNCE_METHOD):
		return null
	return seam