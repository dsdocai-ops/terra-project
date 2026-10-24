class_name Hud
extends CanvasLayer
## The HUD: a lantern orb for health, round teammate badges, a hanging floor
## sign, a lamp minimap, currency nuggets, weapon diamonds, ability dials and a
## rope of relic charms, plus the modal screens (relic choice, rope vote, pause).
## Every widget is driven by HudModel, which reads replicated state
## (NetworkManager.players + GameState.run + Events). Owned by ui-hud (Dev B).
## Sync: pure presentation. The HUD never queries gameplay nodes directly and
## never resolves gameplay; the two things it sends are requests the host
## validates (a relic pick, a rope vote).

## The player chose to leave the run for the town (Quit to Town confirmed, or the
## death screen's Return to Town). main.gd owns the scene change.
signal return_to_town_requested()
## The player chose Leave Co-op from the pause screen.
signal leave_coop_requested()

const POLL_INTERVAL: float = 0.25
const WEAPON_DIAMOND_SIZE := Vector2(66, 74)
const BADGE_SIZE := Vector2(44, 58)
const ROPE_VOTE_SIZE := Vector2(360, 190)
const RUN_SUMMARY_SIZE := Vector2(210, 150)

## Set by the scene owner before adding to the tree (tests inject a fake);
## otherwise created and bound to NetworkManager.players on ready.
var hud_model: HudModel

@onready var teammate_badges: HBoxContainer = $Root/Teammates
@onready var floor_sign: FloorSign = $Root/FloorSign
@onready var lamp_map: LampMap = $Root/LampMap
@onready var currencies: CurrencyReadout = $Root/Currencies
@onready var lantern_orb: LanternOrb = $Root/LanternOrb
@onready var status_row: StatusRow = $Root/StatusRow
@onready var weapons_box: HBoxContainer = $Root/Weapons
@onready var ability_row: AbilityRow = $Root/AbilityRow
@onready var relic_rope: RelicRope = $Root/RelicRope

var choice_popup: ChoicePopup
var rope_vote_prompt: RopeVotePrompt
var pause_layer: Control
var pause_menu: CarvedMenu
var run_summary: RunSummary
var inventory_screen: InventoryScreen
var death_screen: DeathScreen
var pause_items: Array[String] = []
var _confirming_quit: bool = false

var _poll: Timer


func _ready() -> void:
	layer = 10
	if hud_model == null:
		hud_model = HudModel.new()
		hud_model.bind(func() -> Dictionary[int, Player]: return NetworkManager.players)
		hud_model.bind_run(func() -> RunState: return GameState.run)
	hud_model.changed.connect(_apply_all)
	_build_weapon_slots()
	_build_modals()
	_wire_events()
	hud_model.refresh(NetworkManager.local_peer_id)
	_apply_layout()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"inventory") and not choice_popup.visible and not pause_layer.visible and not death_screen.visible:
		inventory_screen.toggle(NetworkManager.local_peer_id)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause") and not choice_popup.visible and not death_screen.visible:
		set_paused_view(not pause_layer.visible)
		get_viewport().set_input_as_handled()


## Shows or hides the pause screen. The game does not pause (it is co-op, the
## host keeps simulating), so this is only the overlay.
func set_paused_view(open: bool) -> void:
	pause_layer.visible = open
	if open:
		_confirming_quit = false
		_fill_pause_items()
		inventory_screen.close()
		_fill_run_summary()
		pause_menu.grab_focus()


func _wire_events() -> void:
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.relic_offer_received.connect(_on_relic_offer_received)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_healed.connect(_on_player_healed)
	Events.player_downed.connect(_on_player_downed)
	Events.player_revived.connect(_on_player_revived)
	Events.weapon_swapped.connect(_on_weapon_swapped)
	Events.relic_picked.connect(_on_relic_picked)
	Events.currency_gained.connect(_on_currency_gained)
	Events.rope_vote_updated.connect(_on_rope_vote_updated)
	GameState.floor_changed.connect(_on_floor_changed)
	GameState.run_ended.connect(_on_run_ended)
	# A slow poll catches HP ticks, status changes and the host's own relic
	# offer (a solo host has no broadcast to hear) between event batches; cheap
	# reads only, no gameplay.
	_poll = Timer.new()
	_poll.wait_time = POLL_INTERVAL
	_poll.autostart = true
	_poll.timeout.connect(_on_poll)
	add_child(_poll)


func _build_weapon_slots() -> void:
	for slot: HudModel.HudWeaponSlot in hud_model.weapon_slots:
		var widget := WeaponDiamond.new()
		widget.slot_number = str(slot.slot_index + 1)
		widget.custom_minimum_size = WEAPON_DIAMOND_SIZE
		widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
		weapons_box.add_child(widget)


func _build_modals() -> void:
	var root: Control = $Root
	choice_popup = ChoicePopup.new()
	choice_popup.name = "ChoicePopup"
	choice_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	choice_popup.picked.connect(_on_choice_picked)
	root.add_child(choice_popup)
	rope_vote_prompt = RopeVotePrompt.new()
	rope_vote_prompt.name = "RopeVotePrompt"
	rope_vote_prompt.custom_minimum_size = ROPE_VOTE_SIZE
	rope_vote_prompt.set_anchors_preset(Control.PRESET_CENTER)
	rope_vote_prompt.offset_left = -ROPE_VOTE_SIZE.x * 0.5
	rope_vote_prompt.offset_right = ROPE_VOTE_SIZE.x * 0.5
	rope_vote_prompt.offset_top = -ROPE_VOTE_SIZE.y * 0.5
	rope_vote_prompt.offset_bottom = ROPE_VOTE_SIZE.y * 0.5
	rope_vote_prompt.voted.connect(_on_rope_voted)
	root.add_child(rope_vote_prompt)
	pause_layer = Control.new()
	pause_layer.name = "PauseLayer"
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.02, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_layer.add_child(dim)
	pause_menu = CarvedMenu.new()
	pause_menu.name = "PauseMenu"
	pause_items = ScreenModels.pause_items(false, false, false)
	pause_menu.items = pause_items
	pause_menu.position = Vector2(70, 120)
	pause_menu.size = Vector2(200, 140)
	pause_menu.chosen.connect(_on_pause_chosen)
	pause_layer.add_child(pause_menu)
	run_summary = RunSummary.new()
	run_summary.name = "RunSummary"
	run_summary.position = Vector2(330, 90)
	run_summary.size = RUN_SUMMARY_SIZE
	run_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_layer.add_child(run_summary)
	root.add_child(pause_layer)
	inventory_screen = InventoryScreen.new()
	inventory_screen.name = "InventoryScreen"
	root.add_child(inventory_screen)
	death_screen = DeathScreen.new()
	death_screen.name = "DeathScreen"
	death_screen.return_requested.connect(_on_return_requested)
	root.add_child(death_screen)


# --- events -------------------------------------------------------------------

## Param counts below match each signal exactly; Godot errors when a signal is
## emitted with more arguments than the connected method accepts.
func _on_player_joined(_peer_id: int) -> void:
	_on_players_changed()


func _on_player_left(_peer_id: int) -> void:
	_on_players_changed()


func _on_players_changed() -> void:
	hud_model.refresh(NetworkManager.local_peer_id)


func _on_poll() -> void:
	_on_players_changed()
	# The host hears no broadcast of its own offer; its pending offer is read here.
	if not choice_popup.visible and RelicFlow.has_offer(NetworkManager.local_peer_id):
		_open_choice(RelicFlow.offer_ids(NetworkManager.local_peer_id))
	elif choice_popup.visible and NetworkManager.is_host and not RelicFlow.has_offer(NetworkManager.local_peer_id):
		choice_popup.close()


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


func _on_relic_picked(_player: Player, _relic: RelicData) -> void:
	_on_players_changed()
	if _player != null and _player.peer_id == NetworkManager.local_peer_id:
		choice_popup.close()


func _on_currency_gained(_player: Player, _currency: StringName, _amount: int) -> void:
	_on_players_changed()


func _on_floor_changed(floor_index: int, biome: Resource) -> void:
	hud_model.biome_label = _biome_text(biome)
	hud_model.set_floor_label("FLOOR %d" % floor_index)


func _on_relic_offer_received(peer_id: int, ids: Array[StringName]) -> void:
	if peer_id == NetworkManager.local_peer_id:
		_open_choice(ids)


func _on_rope_vote_updated(votes: Dictionary) -> void:
	rope_vote_prompt.apply_votes(votes)
	rope_vote_prompt.total = maxi(living_player_count(), votes.size())
	# Whoever already answered does not see the question again.
	if votes.has(NetworkManager.local_peer_id):
		rope_vote_prompt.visible = false


## How many players still stand (not downed): the people the vote waits for.
func living_player_count() -> int:
	var count: int = 0
	if GameState.run != null:
		for peer_id: int in GameState.run.players:
			var slice: RunPlayerState = GameState.run.get_player(peer_id)
			if slice != null and slice.is_standing():
				count += 1
		return count
	for player: Player in NetworkManager.players.values():
		if not player.is_downed:
			count += 1
	return count


func _open_choice(ids: Array[StringName]) -> void:
	var options: Array[ChoiceOption] = ChoiceOption.from_relic_ids(ids)
	if options.is_empty():
		return
	choice_popup.open(options)


func _on_choice_picked(index: int) -> void:
	choice_popup.close()
	NetworkManager.send_pick_relic_request(index)


func _on_rope_voted(yes: bool) -> void:
	rope_vote_prompt.visible = false
	if NetworkManager.is_host:
		GameState.request_extract_vote(NetworkManager.local_peer_id, yes)
	else:
		NetworkManager.request_vote_rope.rpc_id(NetworkManager.HOST_PEER_ID, yes)


func _fill_pause_items() -> void:
	pause_items = ScreenModels.pause_items(GameState.run != null, NetworkManager.is_active and NetworkManager.peer_ids.size() > 1, _confirming_quit, NetworkManager.is_host and NetworkManager.peer_ids.size() > 1)
	pause_menu.items = pause_items


func _on_pause_chosen(index: int) -> void:
	match ScreenModels.pause_action(pause_items, index):
		&"resume":
			set_paused_view(false)
		&"settings", &"codex":
			# Settings arrive in week 12 and the Codex in week 10 (SPEC-ui-hud).
			pass
		&"quit_to_town":
			if not _confirming_quit:
				_confirming_quit = true
				_fill_pause_items()
				return
			set_paused_view(false)
			if NetworkManager.is_host and GameState.run != null:
				GameState.end_run(RunEndReason.Reason.ABORT)
			else:
				return_to_town_requested.emit()
		&"leave_coop":
			set_paused_view(false)
			leave_coop_requested.emit()


## The run ended: show the kept-versus-lost screen for the local player.
func _on_run_ended(result: RefCounted) -> void:
	var typed: RunResult = result as RunResult
	if typed == null:
		return
	pause_layer.visible = false
	rope_vote_prompt.visible = false
	inventory_screen.close()
	death_screen.show_result(typed, NetworkManager.local_peer_id)


func _on_return_requested() -> void:
	return_to_town_requested.emit()


# --- drawing the model --------------------------------------------------------

func _apply_all() -> void:
	lantern_orb.hp_ratio = hud_model.local_hp_ratio
	lantern_orb.hp_current = hud_model.local_hp_current
	lantern_orb.hp_max = hud_model.local_hp_max
	lantern_orb.is_downed = hud_model.local_is_downed
	_rebuild_teammates()
	_apply_weapon_slots()
	floor_sign.floor_text = hud_model.floor_label
	floor_sign.biome_text = hud_model.biome_label
	currencies.gold = hud_model.gold
	currencies.ore = hud_model.ore_total
	currencies.echo = hud_model.echo_shards
	relic_rope.relics = hud_model.relics
	status_row.statuses = hud_model.statuses
	ability_row.has_active_relic = _holds_active_relic()
	_apply_layout()
	if pause_layer != null and pause_layer.visible:
		_fill_run_summary()


## The minimap follows the layout every peer holds for the current floor.
func _apply_layout() -> void:
	var layout: RefCounted = NetworkManager.last_floor_layout
	if layout == null:
		return
	var raw: Variant = layout.get(&"rooms")
	if raw is Array:
		var rects: Array[Rect2i] = []
		for entry: Variant in raw as Array:
			if entry is Rect2i:
				rects.append(entry)
		lamp_map.rooms = rects


func _apply_weapon_slots() -> void:
	for index: int in weapons_box.get_child_count():
		var widget := weapons_box.get_child(index) as WeaponDiamond
		widget.display_name = hud_model.weapon_slots[index].display_name
		widget.weapon_id = hud_model.weapon_slots[index].weapon_id
		widget.active = hud_model.weapon_slots[index].active
		widget.cooldown_fraction = hud_model.weapon_slots[index].cooldown_fraction


func _rebuild_teammates() -> void:
	for child in teammate_badges.get_children():
		teammate_badges.remove_child(child)
		child.free()
	for teammate: HudModel.HudTeammate in hud_model.teammates:
		var badge := TeammateBadge.new()
		badge.name = "Badge%d" % teammate.peer_id
		badge.display_name = teammate.display_name
		badge.hp_ratio = teammate.hp_ratio
		badge.is_downed = teammate.is_downed
		badge.slot = teammate.slot
		badge.custom_minimum_size = BADGE_SIZE
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		teammate_badges.add_child(badge)


func _holds_active_relic() -> bool:
	for relic: HudModel.HudRelic in hud_model.relics:
		var data: RelicData = RelicFlow.data_for(relic.id)
		if data != null and data.kind == RelicData.Kind.ACTIVE:
			return true
	return false


func _fill_run_summary() -> void:
	var elapsed: int = 0
	if GameState.run != null:
		elapsed = (Time.get_ticks_msec() - GameState.run.time_started) / 1000
	run_summary.rows = [
		PackedStringArray(["Floor", hud_model.floor_label.trim_prefix("FLOOR ")]),
		PackedStringArray(["Gold", CurrencyReadout.format_amount(hud_model.gold)]),
		PackedStringArray(["Ore", CurrencyReadout.format_amount(hud_model.ore_total)]),
		PackedStringArray(["Echo Shards", CurrencyReadout.format_amount(hud_model.echo_shards)]),
		PackedStringArray(["Relics", str(hud_model.relics.size())]),
		PackedStringArray(["Time", RunSummary.format_clock(elapsed)]),
	]


func _biome_text(biome: Resource) -> String:
	if biome == null:
		return ""
	var raw: Variant = biome.get(&"display_name")
	if raw is String and raw != "":
		return raw
	var biome_id: Variant = biome.get(&"id")
	if biome_id is int:
		return "Biome %d" % biome_id
	return ""
