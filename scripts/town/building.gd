class_name Building
extends Area2D
## One of Hollowmere's 11 buildings (SPEC-town "Town scene", W5-B4). Owned by town.
## An interactable in SPEC-player-controller's sense (`prompt_text`, `hold_seconds`,
## `interact(player)`). At level 0 it shows a sign and interacting asks to build it;
## from level 1 a functional building opens its service. Week 5 makes three work
## (Blacksmith, Shrine of Echoes, Tavern); the other eight show their level.
##
## Sync: the host's profile decides the level and replicates it for display;
## `interact()` on a client forwards as `interaction_forwarded`, and every purchase
## is the host's (Town does it). Menus are local: this node only announces.

## Host: a player touched an unbuilt building; `cost` is the next level's BuildingLevel.
signal build_prompted(peer_id: int, building_id: StringName, cost: BuildingLevel)
## Host: a player opened a built, functional building.
signal service_opened(peer_id: int, building_id: StringName, level: int)
signal interaction_forwarded(peer_id: int, building_id: StringName)

const HOLD_SECONDS: float = 0.0
const INTERACTABLE_LAYER: int = 32

@export var building_id: StringName = &""

var prompt_text: String = ""
var hold_seconds: float = HOLD_SECONDS
var level: int = 0

@onready var _sign: Label = get_node_or_null(^"Sign") as Label


func _ready() -> void:
	refresh_view()


## Sets the shown level (from the host's profile) and redraws.
func set_level(new_level: int) -> void:
	level = clampi(new_level, 0, BuildingData.MAX_LEVEL)
	refresh_view()


func data() -> BuildingData:
	return BuildingPurchase.data_for(building_id)


func is_functional() -> bool:
	var building: BuildingData = data()
	return building != null and building.functional_in_v1


func refresh_view() -> void:
	var building: BuildingData = data()
	var title: String = String(building_id) if building == null else building.display_name
	if level == 0:
		prompt_text = "Build %s" % title
		if _sign != null:
			_sign.text = "%s\n(not built)" % title
	else:
		prompt_text = title
		if _sign != null:
			_sign.text = "%s  L%d" % [title, level]


func interact(player: Player) -> void:
	var peer: int = NetworkManager.local_peer_id if player == null else player.peer_id
	if not NetworkManager.is_host:
		if NetworkManager.is_active:
			interaction_forwarded.emit(peer, building_id)
		return
	if level == 0:
		build_prompted.emit(peer, building_id, _next_cost())
	elif is_functional():
		service_opened.emit(peer, building_id, level)


func _next_cost() -> BuildingLevel:
	var building: BuildingData = data()
	if building == null or building.levels.is_empty():
		return null
	return building.levels[clampi(level, 0, building.levels.size() - 1)]
