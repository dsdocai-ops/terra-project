class_name LobbyDiscovery
extends Node
## LAN server list: a host announces itself over UDP broadcast once a second and
## a browsing client collects the announcements into a list. Owned by
## networking. Sync: none (UDP, fire and forget). Announcements say who the
## host is; the real join still goes through ENet and the password handshake.
## The list is local network only: reaching a host across the internet means
## typing its address.

const ANNOUNCE_PORT: int = 7778
const ANNOUNCE_SECONDS: float = 1.0
const ENTRY_TTL_SECONDS: float = 4.0
const GAME_ID: String = "sinkhole"
const PROTOCOL: int = 1
const MAX_NAME_LENGTH: int = 24

enum Mode { OFF, ANNOUNCING, BROWSING }

## Emitted when the list gains, loses or updates a server.
signal servers_changed()

var mode: Mode = Mode.OFF
## address:port -> LobbyServerInfo, in first-seen order.
var servers: Dictionary[String, LobbyServerInfo] = {}

var _udp: PacketPeerUDP = null
var _announce_timer: float = 0.0
var _name: String = ""
var _locked: bool = false
var _port: int = NetworkManager.DEFAULT_PORT


## Host: begins announcing this server. `port` is its ENet port.
func start_announcing(server_name: String, locked: bool, port: int = NetworkManager.DEFAULT_PORT) -> void:
	stop()
	_name = server_name.left(MAX_NAME_LENGTH)
	_locked = locked
	_port = port
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", ANNOUNCE_PORT)
	mode = Mode.ANNOUNCING
	_announce_timer = 0.0


## Client: starts listening for announcements. Returns false when the port is
## taken (another browser on this machine), in which case the list stays empty.
func start_browsing() -> bool:
	stop()
	_udp = PacketPeerUDP.new()
	var err: Error = _udp.bind(ANNOUNCE_PORT)
	if err != OK:
		push_warning("[lobby] cannot listen on UDP %d: %s" % [ANNOUNCE_PORT, error_string(err)])
		_udp = null
		return false
	mode = Mode.BROWSING
	servers.clear()
	servers_changed.emit()
	return true


func stop() -> void:
	if _udp != null:
		_udp.close()
		_udp = null
	mode = Mode.OFF


func _process(delta: float) -> void:
	match mode:
		Mode.ANNOUNCING:
			_announce_timer -= delta
			if _announce_timer <= 0.0:
				_announce_timer = ANNOUNCE_SECONDS
				_udp.put_packet(encode(_name, NetworkManager.player_count(), NetworkManager.MAX_PLAYERS, _locked, _port))
		Mode.BROWSING:
			_receive()
			_expire()


func _receive() -> void:
	var changed: bool = false
	while _udp.get_available_packet_count() > 0:
		var bytes: PackedByteArray = _udp.get_packet()
		var info: LobbyServerInfo = decode(bytes, _udp.get_packet_ip())
		if info == null:
			continue
		var key: String = info.key()
		var existing: LobbyServerInfo = servers.get(key)
		if existing == null or not existing.same_as(info):
			changed = true
		info.last_seen = Time.get_ticks_msec()
		servers[key] = info
	if changed:
		servers_changed.emit()


func _expire() -> void:
	var now: int = Time.get_ticks_msec()
	var stale: Array[String] = []
	for key: String in servers:
		if float(now - servers[key].last_seen) / 1000.0 > ENTRY_TTL_SECONDS:
			stale.append(key)
	for key: String in stale:
		servers.erase(key)
	if not stale.is_empty():
		servers_changed.emit()


## The announcement packet for a server.
static func encode(server_name: String, players: int, max_players: int, locked: bool, port: int) -> PackedByteArray:
	var payload: Dictionary = {
		"g": GAME_ID,
		"v": PROTOCOL,
		"n": server_name.left(MAX_NAME_LENGTH),
		"p": players,
		"m": max_players,
		"l": locked,
		"port": port,
	}
	return JSON.stringify(payload).to_utf8_buffer()


## The server an announcement describes, or null for anything that is not a
## well-formed Sinkhole announcement (other games on the port, junk, bad types).
static func decode(bytes: PackedByteArray, sender_ip: String) -> LobbyServerInfo:
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return null
	var data: Dictionary = json.data
	if data.get("g") != GAME_ID or int(data.get("v", 0)) != PROTOCOL:
		return null
	if not (data.get("n") is String) or not (data.get("l") is bool):
		return null
	var info := LobbyServerInfo.new()
	info.server_name = String(data["n"]).strip_edges().left(MAX_NAME_LENGTH)
	if info.server_name.is_empty():
		return null
	info.players = clampi(int(data.get("p", 0)), 0, NetworkManager.MAX_PLAYERS)
	info.max_players = clampi(int(data.get("m", NetworkManager.MAX_PLAYERS)), 1, NetworkManager.MAX_PLAYERS)
	info.locked = bool(data["l"])
	info.port = clampi(int(data.get("port", NetworkManager.DEFAULT_PORT)), 1, 65535)
	info.address = sender_ip
	return info
