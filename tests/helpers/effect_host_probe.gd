class_name EffectHostProbe
extends Effect
## Test double for the effects an `EffectHost` carries: records its own
## attach/detach calls and every `player_dodged` event that reaches it, so the
## host's lifecycle and its event dispatch can be asserted without any relic
## content existing. Used by `tests/unit/test_effect_host.gd`; never used in a
## game scene.
##
## The listener goes through `Effect.listen()`, which is the real dispatch path:
## a `Player`-bearing signal is filtered to this effect's own player, so two
## hosts in the same process prove that an event reaches only the effects on the
## player it names.
##
## Sync: none — a test double. The real effects it stands in for are host-only.

## How many times `_on_attach()` / `_on_detach()` ran.
var attach_calls: int = 0
var detach_calls: int = 0
## How many `player_dodged` events reached this effect, and whose they were.
var dodge_calls: int = 0
var last_dodge_player: Player = null


func _on_attach() -> void:
	attach_calls += 1
	listen(Events.player_dodged, _on_player_dodged)


func _on_detach() -> void:
	detach_calls += 1


func _on_player_dodged(event_player: Player, _perfect: bool) -> void:
	dodge_calls += 1
	last_dodge_player = event_player
