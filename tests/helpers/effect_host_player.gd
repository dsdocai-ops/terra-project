class_name EffectHostPlayer
extends RefCounted
## Test helper that gives a player an `EffectHost`, the way `FakeHealth` gives
## one a `Health`: the real player scene with the lane-B component installed on
## it. `EffectHost` is a Node and belongs under the player, but `player.tscn` is
## Dev A's scene and this lane does not edit it, so the installation lives in a
## helper the tests (and later the harness in W4-B3) share instead.
##
## `install()` is idempotent: a player that already carries the node is handed
## back, so a test can call it twice without stacking two hosts.
##
## blocked on Dev A (W2-A1, player.tscn): when the player scene's composition
## gains its components, the `EffectHost` child moves into `player.tscn` and
## this helper keeps working unchanged — it returns the existing host.
##
## Sync: none — a test helper. The real host is host-only (SPEC-effect-system:
## clients hold no `Effect` instances).

## The node name the spec and the game look the host up by: `player.EffectHost`.
## Taken from the host itself so the helper and the lookup cannot drift apart.
const HOST_NAME: StringName = EffectHost.NODE_NAME
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"


## Instantiates the real player scene under `parent` (which must be in the
## tree) and installs an `EffectHost` on it. The caller owns the player.
static func spawn(parent: Node) -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	parent.add_child(player)
	install(player)
	return player


## Adds an `EffectHost` named `HOST_NAME` under `player`, or returns the one
## already there. A non-`EffectHost` node of that name is replaced, so a stale
## stub cannot silently win the lookup.
static func install(player: Player) -> EffectHost:
	var existing: Node = player.get_node_or_null(NodePath(HOST_NAME))
	if existing is EffectHost:
		return existing as EffectHost
	if existing != null:
		player.remove_child(existing)
		existing.queue_free()
	var host := EffectHost.new()
	host.name = HOST_NAME
	player.add_child(host)
	return host
