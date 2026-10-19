class_name FakeHealth
extends Node
## Test double for Dev A's Health component (W2-A1): exposes `current_hp` and
## `max_hp` exactly as combat-core's Health will, so HudModel's duck-typed HP
## reads can be exercised before it lands. Attached to the player scene's
## Health node by the ui-hud tests; never used in game scenes.
## Owned by ui-hud (tests). Sync: presentation read-only; the real Health is
## host-authoritative via the player's StateSync once Dev A wires it.

var current_hp: int = 100
var max_hp: int = 100