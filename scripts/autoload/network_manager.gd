extends Node
## Hosting, joining, player spawning, peer tracking. Owned by networking.
## Week 1 stub in W1-B3; the real implementation lands in W1-B7 to W1-B9.
## Sync: this module defines the rule. Host decides, clients present.

signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal connection_failed(reason: String)
signal host_disconnected()

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const ENEMY_HP_PER_EXTRA_PLAYER: float = 0.5

## True when multiplayer.is_server(); also true in solo.
var is_host: bool = false
var local_peer_id: int = 0
## Includes the host.
var peer_ids: Array[int] = []
## peer_id -> Player node, filled as spawns complete.
var players: Dictionary[int, Player] = {}


func host(_port: int = DEFAULT_PORT) -> Error:
	return ERR_UNAVAILABLE


func join(_ip: String, _port: int = DEFAULT_PORT) -> Error:
	return ERR_UNAVAILABLE


## Offline server, same code path as host.
func start_solo() -> void:
	pass


func disconnect_all() -> void:
	pass


func get_player(peer_id: int) -> Player:
	return players.get(peer_id)


func player_count() -> int:
	return peer_ids.size()


## 1.0 + 0.5 per player beyond the first.
func enemy_hp_multiplier() -> float:
	return 1.0 + ENEMY_HP_PER_EXTRA_PLAYER * maxi(player_count() - 1, 0)
