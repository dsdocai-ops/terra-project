class_name Shopkeeper
extends Area2D
## The SHOP room's interactable (SPEC-run-economy "Shops"). Owned by run-economy
## (W5-B3). Stock and prices are `ShopStock`'s; this node is the host-side till.
##
## Sync: host-authoritative. The stock is rolled once, from the run seed and the
## floor, so every peer that asks gets the same shelf; `buy()` is the host body and
## a client's `interact()`/`buy()` forwards up as `purchase_forwarded` (the RPC,
## `request_buy(item_index)`, is networking's to add — the stop-at-the-signal shape
## Chest uses). Gold is the party's shared pool, so any player's purchase spends it.
##
## blocked on Dev A (W3-A3): the SHOP populator registration is a guarded no-op
## until `scripts/generation/floor_generator.gd` exists with `RoomType.SHOP`.
##
## Feedback (G9 polish): a sale flashes the body green and plays the UI confirm
## blip; a refusal flashes red and plays the UI error blip, so the player sees
## and hears why the till kept their gold instead of a silent dead shelf.

signal opened(peer_id: int, stock: Array[ShopStock.Item])
signal purchased(peer_id: int, item_index: int, price: int)
signal purchase_forwarded(peer_id: int, item_index: int)
signal interaction_forwarded(peer_id: int)

const PROMPT_TEXT: String = "Browse Shop"
const HOLD_SECONDS: float = 0.0
const SCENE_PATH: String = "res://scenes/dungeon/interactables/shopkeeper.tscn"
const ROOM_TYPE: StringName = &"SHOP"

const SFX_PURCHASE: StringName = &"ui_confirm"
const SFX_REFUSAL: StringName = &"ui_error"
const FLASH_BOUGHT: Color = Color(0.7, 1.0, 0.7)
const FLASH_REFUSED: Color = Color(1.0, 0.6, 0.6)
const FLASH_SECONDS: float = 0.25

const MERCHANTS_BADGE: StringName = &"merchants_badge"
const GREED_CHAIN: StringName = &"greed_chain"
const HAGGLER: StringName = &"haggler"

const REFUSAL_NONE: StringName = &""
const REFUSAL_NOT_HOST: StringName = &"not_host"
const REFUSAL_NO_RUN: StringName = &"no_run"
const REFUSAL_BAD_INDEX: StringName = &"bad_index"
const REFUSAL_SOLD: StringName = &"sold"
const REFUSAL_DOWNED: StringName = &"downed"
const REFUSAL_POOR: StringName = &"not_enough_gold"
const REFUSAL_NO_ROOM: StringName = &"no_room"
const REFUSAL_NO_DATA: StringName = &"no_data"

static var _populator_registered: bool = false
static var _blocker_logged: bool = false

var prompt_text: String = PROMPT_TEXT
var hold_seconds: float = HOLD_SECONDS
## Vesper replaces the shopkeeper on a lucky floor; set by the populator.
var is_vesper: bool = false
## Why the last buy() refused; REFUSAL_NONE after a sale.
var last_refusal: StringName = REFUSAL_NONE
## The blip the last feedback played; presentation and tests read it.
var last_sfx: StringName = &""

var _stock: Array[ShopStock.Item] = []
var _stocked: bool = false


# --- the Interactable contract ---------------------------------------------


func interact(player: Player) -> void:
	var peer: int = peer_id_of(player)
	if not NetworkManager.is_host:
		if NetworkManager.is_active:
			interaction_forwarded.emit(peer)
		return
	opened.emit(peer, stock())


func peer_id_of(player: Player) -> int:
	return NetworkManager.local_peer_id if player == null else player.peer_id


# --- stock -------------------------------------------------------------------


## The shelf, rolled on first use from the run seed and floor.
func stock() -> Array[ShopStock.Item]:
	if not _stocked and GameState.run != null:
		_stocked = true
		var run: RunState = GameState.run
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash([run.seed, run.floor_index, ROOM_TYPE])
		var pool: Array[RelicData] = RelicRoller.load_pool()
		if is_vesper:
			_stock = ShopStock.build_vesper(rng, pool, run.biome_index)
		else:
			_stock = ShopStock.build(rng, pool, rune_ids(), run.biome_index, _any_badge(run))
	return _stock


## Ability runes on sale. Empty until the abilities module lands (blocked on Dev A).
func rune_ids() -> Array[StringName]:
	return []


## What `item_index` costs this player right now.
func price_of(player: Player, item_index: int) -> int:
	var shelf: Array[ShopStock.Item] = stock()
	if item_index < 0 or item_index >= shelf.size():
		return 0
	return ShopStock.price_for(
		shelf[item_index].base_price,
		haggler_rank(),
		_holds(player, MERCHANTS_BADGE),
		_holds(player, GREED_CHAIN),
	)


## The host's Haggler rank (Delver tree); remote ranks arrive with the party
## (TODO(progression-trees), as in RunEconomyRules).
func haggler_rank() -> int:
	var host_profile: PlayerProfile = _host_profile()
	if host_profile == null:
		return 0
	return int(host_profile.skill_tree.get(String(HAGGLER), 0))


func _host_profile() -> PlayerProfile:
	var source: RefCounted = GameState.profile if GameState.profile != null else SaveManager.profile
	return source as PlayerProfile


# --- the till ---------------------------------------------------------------


## Host only. Sells `item_index` to `player`. Returns true on a sale; a refusal
## leaves everything unchanged and names itself in `last_refusal`.
func buy(player: Player, item_index: int) -> bool:
	last_refusal = _refusal_for(player, item_index)
	if last_refusal == REFUSAL_NOT_HOST:
		if NetworkManager.is_active:
			purchase_forwarded.emit(peer_id_of(player), item_index)
		return false
	if last_refusal != REFUSAL_NONE:
		_refuse_feedback()
		return false
	var run: RunState = GameState.run
	var item: ShopStock.Item = stock()[item_index]
	var price: int = price_of(player, item_index)
	if not _deliver(player, run, item):
		_refuse_feedback()
		return false
	run.shared_gold -= price
	item.sold = true
	last_refusal = REFUSAL_NONE
	purchased.emit(peer_id_of(player), item_index, price)
	_purchase_feedback()
	return true


func _refusal_for(player: Player, item_index: int) -> StringName:
	if not NetworkManager.is_host:
		return REFUSAL_NOT_HOST
	var run: RunState = GameState.run
	if run == null:
		return REFUSAL_NO_RUN
	var slice: RunPlayerState = run.get_player(peer_id_of(player))
	if slice == null or not slice.is_standing():
		return REFUSAL_DOWNED
	var shelf: Array[ShopStock.Item] = stock()
	if item_index < 0 or item_index >= shelf.size():
		return REFUSAL_BAD_INDEX
	if shelf[item_index].sold:
		return REFUSAL_SOLD
	if run.shared_gold < price_of(player, item_index):
		return REFUSAL_POOR
	return REFUSAL_NONE


## Hands the goods over; false (with `last_refusal` set) when they cannot be.
func _deliver(player: Player, run: RunState, item: ShopStock.Item) -> bool:
	var slice: RunPlayerState = run.get_player(peer_id_of(player))
	match item.kind:
		ShopStock.KIND_RELIC:
			var data: RelicData = RelicFlow.data_for(item.id)
			var host: EffectHost = RelicFlow.effect_host_of(player)
			if data == null or host == null or host.add(data) == null:
				last_refusal = REFUSAL_NO_DATA
				return false
			slice.relics.append(item.id)
			RelicFlow.record_codex(item.id)
			Events.relic_picked.emit(player, data)
			NetworkManager.route_relic_picked(player, data)
		ShopStock.KIND_POTION:
			if not PotionController.add_to_belt(slice.potions, _potion_slots(), item.id):
				last_refusal = REFUSAL_NO_ROOM
				return false
		ShopStock.KIND_ORE:
			run.shared_ore[item.id] = int(run.shared_ore.get(item.id, 0)) + item.amount
		ShopStock.KIND_RUNE:
			# blocked on Dev A (W5-A): the abilities module attaches runes.
			last_refusal = REFUSAL_NO_DATA
			return false
	return true


func _potion_slots() -> int:
	var host_profile: PlayerProfile = _host_profile()
	if host_profile == null:
		return 0
	return int(host_profile.potions.get(PlayerProfile.POTION_SLOTS, 0))


func _holds(player: Player, relic_id: StringName) -> bool:
	var host: EffectHost = RelicFlow.effect_host_of(player)
	return host != null and host.has_effect(relic_id)


## The stock size is a property of the shelf, not of who is buying, so the Badge
## counts when any party member holds it.
func _any_badge(run: RunState) -> bool:
	for peer_id: int in run.players:
		var party_player: Player = NetworkManager.get_player(peer_id)
		if party_player != null and _holds(party_player, MERCHANTS_BADGE):
			return true
	return false


# --- the feedback --------------------------------------------------------------


## A sale: the confirm blip and a green body flash the whole room sees (G9).
func _purchase_feedback() -> void:
	_flash(FLASH_BOUGHT)
	_play_feedback(SFX_PURCHASE)


## A refusal: the error blip and a red body flash, so a dead shelf explains
## itself instead of silently doing nothing (G9).
func _refuse_feedback() -> void:
	_flash(FLASH_REFUSED)
	_play_feedback(SFX_REFUSAL)


func _play_feedback(id: StringName) -> void:
	last_sfx = id
	AudioManager.play_sfx(id)


## One-shot body flash that fades back to white. The Body sprite is the scene's
## placeholder visual; a keeper without one still gets its blip.
func _flash(color: Color) -> void:
	var body: Sprite2D = get_node_or_null(^"Body") as Sprite2D
	if body == null:
		return
	body.modulate = color
	var tween: Tween = create_tween()
	tween.tween_property(body, "modulate", Color.WHITE, FLASH_SECONDS)


# --- the SHOP populator and its registration seam -----------------------------


static func shop_populator() -> Callable:
	return Callable(Shopkeeper, &"_populate_shop_room")


static func register_populator() -> bool:
	if _populator_registered:
		return true
	var generator: Script = RoomPopulator.generator_script()
	if generator == null:
		_note_blocked("%s does not exist yet, so a shopkeeper spawns with the registry" % RoomPopulator.GENERATOR_SCRIPT_PATH)
		return false
	if not generator.has_method(RoomPopulator.REGISTER_METHOD):
		_note_blocked("%s has no %s()" % [RoomPopulator.GENERATOR_SCRIPT_PATH, RoomPopulator.REGISTER_METHOD])
		return false
	var room_type: Variant = RoomPopulator.room_type_value(generator, ROOM_TYPE)
	if room_type == null:
		_note_blocked("%s declares no RoomType.SHOP" % RoomPopulator.GENERATOR_SCRIPT_PATH)
		return false
	generator.call(RoomPopulator.REGISTER_METHOD, room_type, shop_populator())
	_populator_registered = true
	print("[run] SHOP populator registered with FloorGenerator")
	return true


static func blocker_warnings() -> int:
	return 1 if _blocker_logged else 0


## Host only. Adds the room's shopkeeper (Vesper on a 10% roll) and returns it,
## or null when it refused.
static func place_in(room: Node, rng: RandomNumberGenerator = null) -> Shopkeeper:
	if not NetworkManager.is_host or room == null:
		return null
	var generator: RandomNumberGenerator = rng if rng != null else RelicRoller.seeded_rng()
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[run] SHOP populator could not load %s" % SCENE_PATH)
		return null
	var keeper: Shopkeeper = packed.instantiate() as Shopkeeper
	if keeper == null:
		return null
	keeper.is_vesper = ShopStock.roll_vesper(generator)
	keeper.position = Vector2.ZERO
	room.add_child(keeper)
	return keeper


static func _populate_shop_room(room: Node) -> void:
	place_in(room)


static func _note_blocked(detail: String) -> void:
	if _blocker_logged:
		return
	_blocker_logged = true
	push_warning("[run] SHOP populator not registered — %s" % RoomPopulator.blocker_line(detail))
