class_name Town
extends Node2D
## Hollowmere v1 (SPEC-town "Town scene", W5-B4): a walkable hub with the pit edge
## at stage 0, 11 buildings and three working services. Owned by town.
##
## Sync: the town is the host's. Building levels and the pit stage come from the
## host's profile; clients only display them. Purchases are host-only. Menus
## (Blacksmith list, tree screen, setup screen) are ui-hud's (W5-B6): the town
## announces what was opened through signals and owns the RunSetup the Tavern's
## Dive fills.
##
## blocked on Dev A (W5-A1): spawning the walkable Player in the town and the
## co-op camera follow the same `PlayerSpawner` path as a run; this scene is the
## ground, the pit and the buildings.

## The Tavern Dive (or Map Room) opened the pre-run flow.
signal run_setup_requested(peer_id: int)
## The Shrine of Echoes opened; the skill tree screen is progression-trees'.
signal shrine_entered(peer_id: int)
## The Blacksmith opened its weapon list.
signal blacksmith_opened(peer_id: int)
## An unbuilt building was touched; the menu asks before any ore is spent.
signal build_prompt_requested(peer_id: int, building_id: StringName, cost: BuildingLevel)
signal building_bought(building_id: StringName, new_level: int)
signal building_refused(building_id: StringName, reason: StringName)

## Half-size of the painted ground square, in tiles.
const GROUND_HALF_SIZE: int = 12
## Pit radius in tiles for each story stage; the pit shrinks back as the story
## advances (SPEC-town "Pit edge and visuals"). Stage 0 is the largest.
const PIT_RADIUS_BY_STAGE: Array[int] = [4, 3, 2, 1]

var profile: PlayerProfile = null
var pit_stage: int = 0
var run_setup: RunSetup = RunSetup.new()
var menus: TownMenus = null

@onready var floor_layer: TileMapLayer = $Floor
@onready var pit_layer: TileMapLayer = $PitEdge


func _ready() -> void:
	_paint_ground()
	for candidate: Building in buildings():
		candidate.build_prompted.connect(_on_build_prompted)
		candidate.service_opened.connect(_on_service_opened)
	set_pit_stage(0)
	menus = TownMenus.new()
	menus.name = "TownMenus"
	add_child(menus)
	menus.attach(self)
	load_profile(SaveManager.profile if SaveManager.profile != null else PlayerProfile.defaults())


func buildings() -> Array[Building]:
	var found: Array[Building] = []
	for child: Node in $Buildings.get_children():
		if child is Building:
			found.append(child as Building)
	return found


func building(building_id: StringName) -> Building:
	for candidate: Building in buildings():
		if candidate.building_id == building_id:
			return candidate
	return null


## Shows `new_profile`'s town: every building at its saved level.
func load_profile(new_profile: PlayerProfile) -> void:
	profile = new_profile
	for candidate: Building in buildings():
		candidate.set_level(profile.building_level(candidate.building_id))


## Repaints the pit at `stage` (0 to 3), clamped.
func set_pit_stage(stage: int) -> void:
	pit_stage = clampi(stage, 0, PIT_RADIUS_BY_STAGE.size() - 1)
	pit_layer.clear()
	var radius: int = PIT_RADIUS_BY_STAGE[pit_stage]
	for x: int in range(-radius, radius + 1):
		for y: int in range(-radius, radius + 1):
			pit_layer.set_cell(Vector2i(x, y), Tiles.SOURCE, Tiles.PIT)


func pit_cell_count() -> int:
	return pit_layer.get_used_cells().size()


## Host only. Buys the next level of `building_id` with the host's ore.
func buy(building_id: StringName) -> StringName:
	if not NetworkManager.is_host or profile == null:
		return &"not_host"
	var reason: StringName = BuildingPurchase.purchase(profile, building_id)
	if reason != BuildingPurchase.REFUSAL_NONE:
		building_refused.emit(building_id, reason)
		return reason
	var shown: Building = building(building_id)
	if shown != null:
		shown.set_level(profile.building_level(building_id))
	building_bought.emit(building_id, profile.building_level(building_id))
	return BuildingPurchase.REFUSAL_NONE


func _paint_ground() -> void:
	floor_layer.clear()
	for x: int in range(-GROUND_HALF_SIZE, GROUND_HALF_SIZE + 1):
		for y: int in range(-GROUND_HALF_SIZE, GROUND_HALF_SIZE + 1):
			floor_layer.set_cell(Vector2i(x, y), Tiles.SOURCE, Tiles.FLOOR)


func _on_build_prompted(peer_id: int, building_id: StringName, cost: BuildingLevel) -> void:
	build_prompt_requested.emit(peer_id, building_id, cost)


func _on_service_opened(peer_id: int, building_id: StringName, _level: int) -> void:
	match building_id:
		&"tavern":
			run_setup_requested.emit(peer_id)
		&"shrine_of_echoes":
			shrine_entered.emit(peer_id)
		&"blacksmith":
			blacksmith_opened.emit(peer_id)
