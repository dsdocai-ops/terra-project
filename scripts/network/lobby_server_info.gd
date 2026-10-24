class_name LobbyServerInfo
extends RefCounted
## One server in the lobby list: what its announcement said. Owned by
## networking. Sync: none (a value read off the network).

var server_name: String = ""
var players: int = 0
var max_players: int = NetworkManager.MAX_PLAYERS
var locked: bool = false
var address: String = ""
var port: int = NetworkManager.DEFAULT_PORT
## Engine ticks (ms) of the last announcement; set by the browser.
var last_seen: int = 0


func is_full() -> bool:
	return players >= max_players


## Unique per host process: two servers on one machine differ by port.
func key() -> String:
	return "%s:%d" % [address, port]


## Same displayed content, so a refresh of an unchanged entry stays quiet.
func same_as(other: LobbyServerInfo) -> bool:
	return server_name == other.server_name and players == other.players \
		and max_players == other.max_players and locked == other.locked
