extends Node
## Dev tool: runs the real main scene in a window and saves screenshots of the
## menu, the lobby, the first floor and a combat room to .goals/shots/.
## Run: godot --path . res://tools/capture_ui.tscn   (not headless: it needs a renderer)

const OUT_DIR: String = "res://.goals/shots"
const MAIN_SCENE: String = "res://scenes/main/main.tscn"

var _main: Node = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_start.call_deferred()


func _run() -> void:
	await _frames(30)
	_shot("1_menu")
	var lobby: Node = _main.get("lobby")
	lobby.call("open")
	lobby.discovery.servers["a:7777"] = _server("Wren's mine crew", 2, true)
	lobby.discovery.servers["b:7777"] = _server("Friday dive", 1, false)
	lobby.discovery.servers["c:7777"] = _server("Deep shift", 4, true)
	lobby.call("_refresh_rows")
	await _frames(10)
	_shot("2_lobby")
	lobby.call("ask_password", "192.168.1.20", 7777, "Wrong password. Try again.")
	await _frames(5)
	_shot("3_prompt")
	lobby.call("close")
	_main.call("_on_solo")
	await _frames(40)
	_shot("4_floor_start")
	var world: World = _main.get("world")
	var player: Player = NetworkManager.players.get(NetworkManager.local_peer_id)
	for room: Room in world.floor_node.rooms:
		if room.type == FloorGenerator.RoomType.COMBAT:
			player.position = room.position
			player.synced_position = room.position
			break
	await _frames(90)
	_shot("5_combat_room")
	player.get_node("AttackController").call("apply", 0, Vector2.RIGHT, 0.0)
	await _frames(6)
	_shot("6_swing")
	get_tree().quit()


func _server(server_name: String, players: int, locked: bool) -> LobbyServerInfo:
	var info := LobbyServerInfo.new()
	info.server_name = server_name
	info.players = players
	info.locked = locked
	info.address = "192.168.1.%d" % (20 + players)
	return info


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name])
	image.save_png(path)
	print("[capture] ", path)


func _start() -> void:
	await get_tree().process_frame
	_run()
