class_name RelicMarkerEffect
extends Effect
## A do-nothing attached relic: an `Effect` that exists only so its **id** is
## present on a player's `EffectHost`. Owned by effect-system (tests).
##
## `EffectHost.add()` refuses a source whose `effect_script` is missing or does
## not extend `Effect`, so a test that wants "this player holds `lightning_rod`"
## has to attach a real script — and the real relic scripts are W4-B6 content
## (G32…G35) that does not exist yet. This double is what those cases attach
## under the real relic's id; when the `.tres` files land, each case loads its
## own file instead and this helper is deleted.
##
## Sync: none — a test double, attached to a test fixture's player; never a game
## scene.

## Nothing to attach: the marker carries no behaviour, only its id.
func _on_attach() -> void:
	pass
