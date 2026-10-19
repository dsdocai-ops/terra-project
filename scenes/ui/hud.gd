class_name Hud
extends CanvasLayer
## HUD v0: own HP bar, teammate HP bars with names, two weapon slots, and a
## floor-label placeholder — every widget driven by HudModel, which reads
## replicated state (NetworkManager.players + Events + GameState). Owned by
## ui-hud (Dev B). Sync: pure presentation. The HUD never queries gameplay
## nodes directly, never resolves gameplay, and never sends RPCs; host and
## client render the same replicated truth.

const POLL_INTERVAL := 0.25
const TEAMMATE_NAME_WIDTH := 70.0
const TEAMMATE_BAR_WIDTH := 140.0
const WEAPON_SLOT_WIDTH := 72.0
const WEAPON_SLOT_HEIGHT := 52.0

## Set by the scene owner before adding to the tree (tests inject a fake);
## otherwise created and bound to NetworkManager.players on ready.
var hud_model: HudModel

@onready var own_hp_bar: HpBar = $Root/TopLeft/OwnHpBar
@onready var teammate_bars: VBoxContainer = $Root/TopLeft/TeammateBars
@onready var weapon_slots_box: HBoxContainer = $Root/WeaponSlots
@onready var floor_label: Label = $Root/TopCenter/FloorLabel

var _poll: Timer


func _ready() -> void:
	layer = 10
	if hud_model == null:
		hud_model = HudModel.new()
		hud_model.bind(func() -> Dictionary[int, Player]: return NetworkManager.players)
	hud_model.changed.connect(_apply_all)
	_build_weapon_slots()
	_wire_events()
	hud_model.refresh(NetworkManager.local_peer_id)


func _wire_events() -> void:
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_healed.connect(_on_player_healed)
	Events.player_downed.connect(_on_player_downed)
	Events.player_revived.connect(_on_player_revived)
	Events.weapon_swapped.connect(_on_weapon_swapped)
	GameState.floor_changed.connect(_on_floor_changed)
	# A slow poll catches HP ticks and cooldown sweeps between event batches;
	# cheap reads only, no gameplay.
	_poll = Timer.new()
	_poll.wait_time = POLL_INTERVAL
	_poll.autostart = true
	_poll.timeout.connect(_on_players_changed)
	add_child(_poll)


## Every member of the player set changed (join/leave/HP tick), so recompute the
## whole HUD from replicated state. Param counts below match each signal
## exactly; Godot errors when a signal is emitted with more arguments than the
## connected method accepts.
func _on_player_joined(_peer_id: int) -> void:
	_on_players_changed()


func _on_player_left(_peer_id: int) -> void:
	_on_players_changed()


func _on_players_changed() -> void:
	hud_model.refresh(NetworkManager.local_peer_id)


func _on_player_damaged(_player: Player, _hit: RefCounted) -> void:
	_on_players_changed()


func _on_player_healed(_player: Player, _amount: int, _source: Node) -> void:
	_on_players_changed()


func _on_player_downed(_player: Player) -> void:
	_on_players_changed()


func _on_player_revived(_player: Player, _by: Player) -> void:
	_on_players_changed()


func _on_weapon_swapped(_player: Player, slot: int) -> void:
	hud_model.set_weapon_active(slot)


func _on_floor_changed(floor_index: int, _biome: Resource) -> void:
	hud_model.set_floor_label("FLOOR %d" % floor_index)


func _apply_all() -> void:
	own_hp_bar.ratio = hud_model.local_hp_ratio
	own_hp_bar.is_downed = hud_model.local_is_downed
	_rebuild_teammate_bars()
	_apply_weapon_slots()
	floor_label.text = hud_model.floor_label


func _build_weapon_slots() -> void:
	for slot: HudModel.HudWeaponSlot in hud_model.weapon_slots:
		var widget := WeaponSlot.new()
		widget.slot_number = str(slot.slot_index + 1)
		widget.custom_minimum_size = Vector2(WEAPON_SLOT_WIDTH, WEAPON_SLOT_HEIGHT)
		weapon_slots_box.add_child(widget)


func _apply_weapon_slots() -> void:
	for index: int in weapon_slots_box.get_child_count():
		var widget := weapon_slots_box.get_child(index) as WeaponSlot
		widget.display_name = hud_model.weapon_slots[index].display_name
		widget.active = hud_model.weapon_slots[index].active
		widget.cooldown_fraction = hud_model.weapon_slots[index].cooldown_fraction


func _rebuild_teammate_bars() -> void:
	for child in teammate_bars.get_children():
		teammate_bars.remove_child(child)
		child.free()
	for teammate: HudModel.HudTeammate in hud_model.teammates:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = teammate.display_name
		name_label.custom_minimum_size = Vector2(TEAMMATE_NAME_WIDTH, 0)
		name_label.add_theme_color_override("font_color", Color(0.910, 0.847, 0.690))
		var bar := HpBar.new()
		bar.name = "Bar"
		bar.fill_color = Color(0.373, 0.749, 0.416) # UI palette teammate_green
		bar.ratio = teammate.hp_ratio
		bar.is_downed = teammate.is_downed
		bar.custom_minimum_size = Vector2(TEAMMATE_BAR_WIDTH, 10)
		row.add_child(name_label)
		row.add_child(bar)
		teammate_bars.add_child(row)