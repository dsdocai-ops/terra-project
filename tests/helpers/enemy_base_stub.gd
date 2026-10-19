class_name EnemyBaseStub
extends CharacterBody2D
## Test double for Dev A's enemy_base (W2-A9), matching the spec's node-tree
## shape: a CharacterBody2D with Health-style HP and a host-owned StateSync
## replicating position, animation, and HP. Used by W2-B3's spawner tests and
## the week-2 smoke — it is a test helper, never a game scene.
## Owned by networking (tests). Sync: host-authoritative. The host (authority
## 1, multiplayer.is_server()) writes the synced pose and current_hp; clients
## only present the replicated StateSync fields and never resolve gameplay
## (see apply_hit).

var synced_position: Vector2 = Vector2.ZERO
var current_anim: StringName = &"idle"
var current_hp: int = 10
var max_hp: int = 10
var fight_id: int = 0
var elite: bool = false


func _ready() -> void:
	synced_position = global_position


## Host-only resolve: hits land only when running as the server. Split out
## so unit tests can drive the client side without a second instance.
func _resolves_hits() -> bool:
	return multiplayer.is_server()


## Host only. Applies `amount` damage and returns true when the hit lands
## (a dead target takes nothing). A client calling this gets a refusal — hit
## resolution is host-only.
func apply_hit(amount: int) -> bool:
	if not _resolves_hits():
		push_warning("[enemy-stub] hit refused: only the host resolves hits")
		return false
	if current_hp <= 0:
		return false
	current_hp = maxi(current_hp - amount, 0)
	return true


func _process(_delta: float) -> void:
	# Clients present the host's replicated pose; the host writes the same
	# fields, so this is a no-op there (see the "Sync:" note above).
	global_position = synced_position