class_name DodgePing
extends Node2D
## The ring that pulses out from a player who just dodged a hit perfectly, so
## players learn the timing (combat v2 C4). Placeholder art drawn with _draw()
## until AR-3. Owned by combat-core. Sync: none, local only; spawned on every
## peer by `CombatFeedback` from its unreliable ping RPC.

const START_RADIUS_PX: float = 6.0
const END_RADIUS_PX: float = 34.0
const LIFETIME_SECONDS: float = 0.25
const SQUASH_Y: float = 0.55
const COLOR: Color = Color(0.55, 0.9, 1.0, 1.0)

var progress: float = 0.0


## Spawns a ping at world position `at` under `parent`.
static func spawn(parent: Node, at: Vector2) -> DodgePing:
	var ping := DodgePing.new()
	ping.z_index = 90
	parent.add_child(ping)
	ping.global_position = at
	return ping


func _ready() -> void:
	scale = Vector2(1.0, SQUASH_Y)
	var tween: Tween = create_tween()
	tween.tween_property(self, "progress", 1.0, LIFETIME_SECONDS)
	tween.tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


## Current ring radius, for tests and the draw call.
func radius() -> float:
	return lerpf(START_RADIUS_PX, END_RADIUS_PX, progress)


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius(), 0.0, TAU, 32, Color(COLOR.r, COLOR.g, COLOR.b, 1.0 - progress), 2.0)
