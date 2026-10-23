class_name TownMenus
extends CanvasLayer
## The town's menus (SPEC-ui-hud "Town menus", "Run setup"): Blacksmith buy list,
## the build prompt, and the pre-run screen. Owned by ui-hud (Dev B); the town
## module provides the rules (Blacksmith, BuildingPurchase, RunSetup) and this
## draws them. Sync: menus are local to each player. Purchases and the run start
## are the host's: here they run on the host, and a client's choice forwards
## through the Town/Building signals until the request RPCs exist.

enum Screen { NONE, BLACKSMITH, BUILD, SETUP }

signal closed()

const PANEL_WIDTH: float = 340.0

var town: Town = null
var screen: Screen = Screen.NONE
var panel: ScreenPanel = null
var local_peer: int = 1

var _weapon_ids: Array[StringName] = []
var _build_id: StringName = &""
var _message: String = ""


func _init() -> void:
	layer = 11
	visible = false
	panel = ScreenPanel.new()
	panel.name = "Panel"
	panel.chosen.connect(_on_chosen)
	add_child(panel)


## Wires the menus to a town's signals. Idempotent per town.
func attach(target: Town) -> void:
	town = target
	if not town.blacksmith_opened.is_connected(_on_blacksmith_opened):
		town.blacksmith_opened.connect(_on_blacksmith_opened)
		town.build_prompt_requested.connect(_on_build_prompt_requested)
		town.run_setup_requested.connect(_on_run_setup_requested)


func is_open() -> bool:
	return screen != Screen.NONE


func close() -> void:
	screen = Screen.NONE
	visible = false
	_message = ""
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- opening ----------------------------------------------------------------


func _on_blacksmith_opened(peer_id: int) -> void:
	local_peer = peer_id
	open_blacksmith()


func _on_build_prompt_requested(peer_id: int, building_id: StringName, _cost: BuildingLevel) -> void:
	local_peer = peer_id
	open_build_prompt(building_id)


func _on_run_setup_requested(peer_id: int) -> void:
	local_peer = peer_id
	open_setup()


func open_blacksmith() -> void:
	screen = Screen.BLACKSMITH
	_refresh()


func open_build_prompt(building_id: StringName) -> void:
	_build_id = building_id
	screen = Screen.BUILD
	_refresh()


func open_setup() -> void:
	screen = Screen.SETUP
	if not town.run_setup.selections.has(local_peer):
		town.run_setup.submit(SelectionState.new(local_peer), town.profile)
	_refresh()


# --- drawing -----------------------------------------------------------------


func _refresh() -> void:
	if town == null or town.profile == null:
		return
	match screen:
		Screen.BLACKSMITH:
			panel.title = "Blacksmith"
			_weapon_ids = ScreenModels.blacksmith_order()
			panel.subtitle = ScreenModels.blacksmith_subtitle(town.profile) if _message == "" else "%s   -   %s" % [ScreenModels.blacksmith_subtitle(town.profile), _message]
			panel.sections = []
			panel.buttons = ScreenModels.blacksmith_buttons(_weapon_ids, town.profile)
		Screen.BUILD:
			panel.title = ScreenModels.build_title(_build_id)
			panel.subtitle = _message
			panel.sections = ScreenModels.build_sections(town.profile, _build_id)
			panel.buttons = ["Build", "Cancel"]
		Screen.SETUP:
			panel.title = "Dive"
			panel.subtitle = _message
			panel.sections = ScreenModels.setup_sections(town.run_setup, local_peer, _peers())
			panel.buttons = setup_buttons()
		_:
			return
	panel.size = Vector2(PANEL_WIDTH, panel.custom_minimum_size.y)
	panel.position = ((get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(960, 540)) - panel.size) * 0.5
	visible = true
	panel.grab_menu_focus()


func _peers() -> Array[int]:
	if NetworkManager.peer_ids.is_empty():
		return [local_peer]
	return NetworkManager.peer_ids.duplicate()


# --- choosing ----------------------------------------------------------------


func _on_chosen(index: int) -> void:
	match screen:
		Screen.BLACKSMITH:
			_choose_blacksmith(index)
		Screen.BUILD:
			_choose_build(index)
		Screen.SETUP:
			_choose_setup(index)


func _choose_blacksmith(index: int) -> void:
	if index >= _weapon_ids.size():
		close()
		return
	if not NetworkManager.is_host:
		# Purchases are the host's until the request RPC exists.
		_message = "Only the host can buy for now"
		_refresh()
		return
	var reason: StringName = Blacksmith.buy_weapon(town.profile, _weapon_ids[index])
	_message = "Bought %s" % ScreenModels.pretty(_weapon_ids[index]) if reason == Blacksmith.REFUSAL_NONE else reason_text(reason)
	_refresh()


func _choose_build(index: int) -> void:
	if index != 0:
		close()
		return
	var reason: StringName = town.buy(_build_id)
	if reason == BuildingPurchase.REFUSAL_NONE:
		close()
		return
	_message = reason_text(reason)
	_refresh()


## The setup list: cycle class / weapons / start floor, ready, start, close.
static func setup_buttons_for(setup: RunSetup, local: int, is_host: bool) -> Array[String]:
	var mine: SelectionState = setup.selections.get(local)
	var items: Array[String] = []
	if mine != null:
		items.append("Class: %s" % ScreenModels.pretty(mine.class_id))
		items.append("Weapon 1: %s" % ScreenModels.pretty(mine.weapon_ids[0]))
		items.append("Weapon 2: %s" % ScreenModels.pretty(mine.weapon_ids[1]))
		items.append("Start floor: %d" % setup.start_floor)
		items.append("Not ready" if mine.ready else "Ready")
	if is_host:
		items.append("Start dive")
	items.append("Close")
	return items


func setup_buttons() -> Array[String]:
	return setup_buttons_for(town.run_setup, local_peer, NetworkManager.is_host)


func _choose_setup(index: int) -> void:
	var items: Array[String] = setup_buttons()
	if index < 0 or index >= items.size():
		return
	var setup: RunSetup = town.run_setup
	var mine: SelectionState = setup.selections.get(local_peer)
	var label: String = items[index]
	if label == "Close":
		close()
		return
	if label == "Start dive":
		var reason: StringName = setup.start(_peers())
		if reason == RunSetup.REFUSAL_NONE:
			close()
			return
		_message = reason_text(reason)
	elif mine != null:
		var edited: SelectionState = mine.copy()
		if label.begins_with("Class"):
			edited.class_id = cycle(unlocked_classes(), edited.class_id)
		elif label.begins_with("Weapon 1"):
			edited.weapon_ids[0] = cycle_weapon(edited.weapon_ids[0], edited.weapon_ids[1])
		elif label.begins_with("Weapon 2"):
			edited.weapon_ids[1] = cycle_weapon(edited.weapon_ids[1], edited.weapon_ids[0])
		elif label.begins_with("Start floor"):
			cycle_start_floor()
		elif label == "Ready" or label == "Not ready":
			setup.set_ready(local_peer, not mine.ready)
			_refresh()
			return
		var reason: StringName = setup.submit(edited, town.profile)
		_message = "" if reason == RunSetup.REFUSAL_NONE else reason_text(reason)
	_refresh()


func unlocked_classes() -> Array[StringName]:
	var ids: Array[StringName] = []
	for class_key: Variant in town.profile.classes:
		var entry: Variant = town.profile.classes[class_key]
		if entry is Dictionary and bool((entry as Dictionary).get("unlocked", false)):
			ids.append(StringName(str(class_key)))
	ids.sort()
	return ids


## The next unlocked weapon after `current`, skipping the other slot's weapon.
func cycle_weapon(current: StringName, other: StringName) -> StringName:
	var pool: Array[StringName] = []
	for weapon_id: String in town.profile.weapons_unlocked:
		if StringName(weapon_id) != other:
			pool.append(StringName(weapon_id))
	return cycle(pool, current)


static func cycle(pool: Array[StringName], current: StringName) -> StringName:
	if pool.is_empty():
		return current
	var at: int = pool.find(current)
	return pool[(at + 1) % pool.size()]


func cycle_start_floor() -> void:
	var floors: Array[int] = MapRoom.available_start_floors(town.profile.map_room_deepest_rope)
	var at: int = floors.find(town.run_setup.start_floor)
	town.run_setup.set_start_floor(floors[(at + 1) % floors.size()], town.profile.map_room_deepest_rope)


static func reason_text(reason: StringName) -> String:
	match reason:
		Blacksmith.REFUSAL_POOR:
			return "Not enough gold"
		Blacksmith.REFUSAL_OWNED:
			return "Already yours"
		Blacksmith.REFUSAL_NOT_BUILT:
			return "Build the Blacksmith first"
		BuildingPurchase.REFUSAL_NOT_ENOUGH_ORE:
			return "Not enough ore"
		BuildingPurchase.REFUSAL_MAX_LEVEL:
			return "Fully upgraded"
		RunSetup.REFUSAL_NOT_READY:
			return "Everyone has to be ready"
		RunSetup.REFUSAL_NOT_HOST:
			return "Only the host starts the dive"
		SelectionState.REFUSAL_WEAPON_LOCKED:
			return "That weapon is locked"
		SelectionState.REFUSAL_CLASS_LOCKED:
			return "That class is locked"
	return String(reason).replace("_", " ").capitalize()
