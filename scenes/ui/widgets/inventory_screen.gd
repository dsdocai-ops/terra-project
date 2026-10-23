class_name InventoryScreen
extends Control
## The run / inventory screen (Tab): relics with stacks, the eleven stats and the
## loadout. Owned by ui-hud (Dev B). Sync: presentation only; it reads the local
## player's RunPlayerState and StatBlock and never writes either.
## The synergy progress, floor map and ability ranks join as their owners land.

const PANEL_WIDTH: float = 340.0

var panel: ScreenPanel = null


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.02, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = ScreenPanel.new()
	panel.name = "Panel"
	panel.title = "Your dive"
	panel.chosen.connect(_on_chosen)
	add_child(panel)


func _on_chosen(_index: int) -> void:
	close()


func toggle(local_peer: int) -> void:
	if visible:
		close()
	else:
		open(local_peer)


func open(local_peer: int) -> void:
	refresh(local_peer)
	visible = true
	panel.grab_menu_focus()


func close() -> void:
	visible = false


## Rebuilds the rows from the live run, so it can also run while open.
func refresh(local_peer: int) -> void:
	var run: RunState = GameState.run
	var slice: RunPlayerState = run.get_player(local_peer) if run != null else null
	panel.sections = ScreenModels.inventory_sections(slice, run, stat_values(local_peer))
	panel.buttons = ["Close"]
	panel.size = Vector2(PANEL_WIDTH, panel.custom_minimum_size.y)
	panel.position = ((get_viewport_rect().size if is_inside_tree() else Vector2(960, 540)) - panel.size) * 0.5


## Stat index -> value for the local player; empty without a StatBlock.
static func stat_values(peer_id: int) -> Dictionary[int, float]:
	var values: Dictionary[int, float] = {}
	var player: Player = NetworkManager.get_player(peer_id)
	if player == null:
		return values
	var block: StatBlock = player.get_node_or_null(StatusEffects.STAT_BLOCK_NODE) as StatBlock
	if block == null:
		return values
	for index: int in StatBlock.STAT_COUNT:
		values[index] = block.get_value(index as StatBlock.Stat)
	return values
