extends CharacterBody2D
## Temporary stand-in for Dev A's enemy_base (W2-A9): a CharacterBody2D with
## Health-shaped HP and a host-owned StateSync, so enemy spawning, sync, and
## host-only hit resolution work end to end before real enemies land. Not a
## real enemy — no AI, no telegraph, no loot.
## Owned by networking (W2-B3). Sync: StateSync (authority 1) replicates
## position, animation, and HP from the host to every peer. Clients never
## write gameplay state; apply_hit() is refused unless multiplayer.is_server().

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
		push_warning("[enemy] hit refused: only the host resolves hits")
		return false
	if current_hp <= 0:
		return false
	current_hp = maxi(current_hp - amount, 0)
	return true


func _process(_delta: float) -> void:
	# Clients present the host's replicated pose; the host writes the same
	# fields, so this is a no-op there (see the "Sync:" note above).
	global_position = synced_position