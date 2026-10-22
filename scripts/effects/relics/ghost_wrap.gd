class_name GhostWrapEffect
extends Effect
## Ghost Wrap — design doc 9.1 no. 5: "perfect dodges make you invisible for
## 2s". Owned by relics (W4-B6, goal G5).
##
## Only the *perfect* dodge counts: `player_dodged` carries that as its second
## argument ("`player_dodged(player: Player, perfect: bool)`"), and a plain dodge
## leaves the player exactly as it was. A perfect dodge takes the player's alpha
## to `INVISIBLE_ALPHA` — `modulate` on the player node multiplies into every
## child, so the player and everything on it stop rendering — and a one-shot
## clock puts it back after `INVISIBLE_SECONDS = 2.0`, the "2s" the description
## states.
##
## The clock is `Effect._start_timer()`, the base class's tracked one-shot: it is
## parented to this effect and freed by `detach()`, so a relic dropped mid-
## invisibility cannot leave a timer behind, and the alpha is put back in
## `_on_detach()` for the same reason — a player who sells the relic while
## invisible does not stay invisible.
##
## **What is not this relic's to finish.** The point of being invisible is that
## enemies lose track of you: SPEC-enemies-ai — "Smoke Step / Smoke Bomb /
## Vanish / Ghost Wrap make a player untargetable and drop aggro" — puts that in
## `Targeting.pick()`, which is enemies-ai's, and no interface for "this player
## is untargetable" exists yet, so this relic cannot ask for it (**blocked on Dev
## A, enemies-ai**). What this lane ships is the half it owns: the invisible
## state itself, and a clock that ends it. When the targeting seam lands, the
## call joins `_hide()` / `_fade_back()` here and nothing else moves.
##
## Sync: host-only. SPEC-relics — "Rolls, picks, attaches, actives, synergy
## evaluation: host." The modulations this effect makes are host-local
## presentation; the synchronised form of "this player is hidden" belongs to the
## player's own replicated state (Dev A), not to a relic writing a local alpha.

## How long the player stays invisible, in seconds. Design doc 9.1 no. 5: "for
## 2s" — and the data file's description says the same 2s.
const INVISIBLE_SECONDS: float = 2.0
## The alpha the player is taken to while invisible. Zero: fully invisible.
const INVISIBLE_ALPHA: float = 0.0

## The player's alpha before this effect hid them, so the way back is the exact
## way in rather than an assumed 1.0 — something else (a hit flash, another
## relic) may have changed it since.
var _alpha_before: float = 1.0
## Whether this effect is the one currently hiding the player, so `_on_detach()`
## and a second perfect dodge restore exactly once.
var _hidden: bool = false


func _on_attach() -> void:
	listen(Events.player_dodged, _on_player_dodged)


## A perfect dodge hides the player; a plain one does nothing at all.
func _on_player_dodged(_player: Player, perfect: bool) -> void:
	if not perfect:
		return
	_hide()


## Puts the player's alpha back when the relic is dropped mid-invisibility: the
## clock above is already gone by the time this runs (the base frees its timers
## before calling a subclass), so a relic sold while the player is hidden cannot
## leave them hidden.
func _on_detach() -> void:
	if _hidden:
		_fade_back()


## Hides the player and arms the clock that brings them back. A second perfect
## dodge while already hidden re-arms the clock rather than stacking a second
## timer: the description is "invisible for 2s", not "for 2s per perfect dodge".
func _hide() -> void:
	if player == null:
		return
	if not _hidden:
		_alpha_before = player.modulate.a
		_hidden = true
	player.modulate.a = INVISIBLE_ALPHA
	_start_timer(INVISIBLE_SECONDS, Callable(self, &"_fade_back"))


## Puts the player's alpha back. Also the clock's own handler, so the timer
## expiring and the relic being dropped take the same path.
func _fade_back() -> void:
	if player == null:
		return
	player.modulate.a = _alpha_before
	_hidden = false