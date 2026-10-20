extends GutTest
## Tests for the `Pickup` scene and its magnet (SPEC-run-economy, W4-B8, G12).
##
## SPEC-run-economy: "Pickups are physical: `Pickup` scene (gold coin, ore
## chunk, echo shard, rune stone, relic, potion) spawned by host, magnetized to
## the nearest player within `pickup_radius` (Ore Magnet makes it room-wide).
## Shared currencies are collected by whoever touches them. Per-player pickups
## (relics, runes) are per-player drops: each player sees only their own
## (design doc), implemented as pickups with `visible_to_peer`."
##
## Every sentence of that paragraph is one case below: the six kinds, the
## nearest-player magnet inside the radius, the standstill outside it, the
## collect that emits `Events.pickup_collected` and frees the node, the
## room-wide radius read off the holder's `EffectHost` by id, and the per-peer
## visibility asserted on the property the `MultiplayerSynchronizer` reads.
##
## Owned by run-economy. Sync: the magnet is host gameplay (the cases assert a
## client's copy does not run it), and the visibility case is the sync seam.
##
## after_each clears the `TimeManager` source this file injects and the
## `NetworkManager` session so no autoload state leaks into the next test file
## (LESSONS). Signals are captured with named method callbacks, never lambdas
## (LESSONS).

const PICKUP_SCENE_PATH: String = "res://scenes/pickups/pickup.tscn"
const PICKUP_SCRIPT_PATH: String = "res://scripts/run/pickup.gd"
const EVENTS_SCRIPT_PATH: String = "res://scripts/autoload/events.gd"
const SAMPLE_EFFECT_PATH: String = "res://tests/helpers/harness_sample_effect.gd"
## The time-effect source this file injects; cleared in after_each.
const TIME_SOURCE: StringName = &"pickup-test"
## The ids the magnet cases use. 1 is never the local peer in this suite, so a
## test player is never mistaken for the machine running it.
const NEAR_PEER: int = 2
const FAR_PEER: int = 3
## The pickup's own radius in the magnet cases, big enough that the fixture
## players sit inside it and small enough that the standstill case is outside.
const TEST_RADIUS: float = 64.0

## What `Events.pickup_collected` carried, one entry per emission.
var _collected: Array[Dictionary] = []
var _root: Node2D = null
var _pickup: Pickup = null


func before_each() -> void:
	_collected.clear()
	NetworkManager.start_solo()
	_root = Node2D.new()
	_root.name = &"PickupTestRoot"
	add_child_autofree(_root)
	Events.pickup_collected.connect(_on_pickup_collected)
	_pickup = make_pickup()


func after_each() -> void:
	if Events.pickup_collected.is_connected(_on_pickup_collected):
		Events.pickup_collected.disconnect(_on_pickup_collected)
	TimeManager.clear_source(TIME_SOURCE)
	NetworkManager.disconnect_all()
	_root = null
	_pickup = null


func _on_pickup_collected(player: Player, pickup: Pickup) -> void:
	_collected.append({"player": player, "pickup": pickup})


# --- fixtures ---------------------------------------------------------------


func pickup_scene() -> PackedScene:
	var packed: PackedScene = load(PICKUP_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % PICKUP_SCENE_PATH)
	return packed


## A pickup from the real scene, under the test root and with its own physics
## tick off, so a case drives `magnet_step()` itself and the assertions are not
## racing the engine's frame. The one case that wants the real tick turns it
## back on.
func make_pickup() -> Pickup:
	var packed: PackedScene = pickup_scene()
	if packed == null:
		return null
	var made: Pickup = packed.instantiate() as Pickup
	assert_not_null(made, "the pickup scene's root is a Pickup")
	if made == null:
		return null
	_root.add_child(made)
	made.set_physics_process(false)
	made.pickup_radius = TEST_RADIUS
	return made


## A real player scene under the test root: the magnet needs a node in the
## `player` group with a global position, and the Ore Magnet case needs the
## `EffectHost` the holder carries. Deliberately *without* a host — a player
## carries one only when a relic is attached (`attach_relic`), which is what
## makes "no host" a case of its own. Its own ticks are off for the same reason
## the pickup's are.
func make_player(peer_id: int, at: Vector2) -> Player:
	var player: Player = (load(EffectHostPlayer.PLAYER_SCENE) as PackedScene).instantiate() as Player
	_root.add_child(player)
	player.name = "PickupTestPlayer%d" % peer_id
	player.peer_id = peer_id
	player.global_position = at
	player.add_to_group(StatusEffects.PLAYER_TAG)
	player.set_physics_process(false)
	player.set_process(false)
	return player


## A pickup that never enters the tree, for the per-peer visibility cases. A
## single-process suite has no second connected peer, and the engine refuses
## `set_visibility_for()` for a peer the `MultiplayerSynchronizer` does not
## know (it answers `ERR_INVALID_PARAMETER`), so those cases drive the
## synchronizer directly — the same two properties the engine reads when it
## sends. The real two-peer path is the two-instance smoke.
func detached_pickup() -> Pickup:
	var packed: PackedScene = pickup_scene()
	if packed == null:
		return null
	var made: Pickup = packed.instantiate() as Pickup
	assert_not_null(made, "the pickup scene's root is a Pickup")
	if made == null:
		return null
	autofree(made)
	return made


## An `EffectHost` on `player` holding a relic with the given id, attached
## through the real `EffectHost.add()`.
func attach_relic(player: Player, id: StringName) -> EffectHost:
	var host: EffectHost = EffectHostPlayer.install(player)
	var source: ContentData = ContentData.new()
	source.id = id
	source.display_name = String(id)
	source.effect_script = load(SAMPLE_EFFECT_PATH) as GDScript
	assert_not_null(host.add(source), "%s attached to the host" % id)
	return host


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# --- the scene and the script ----------------------------------------------


func test_the_pickup_scene_and_script_live_where_spec_project_puts_them() -> void:
	assert_true(FileAccess.file_exists(PICKUP_SCENE_PATH),
		"%s exists (SPEC-project: scenes/<module>/)" % PICKUP_SCENE_PATH)
	assert_true(FileAccess.file_exists(PICKUP_SCRIPT_PATH), "%s exists" % PICKUP_SCRIPT_PATH)


func test_the_pickup_scene_instantiates_as_a_pickup() -> void:
	assert_not_null(_pickup)
	if _pickup == null:
		return
	assert_eq(_pickup.collision_layer, Pickup.PICKUP_LAYER,
		"a pickup sits on no physics layer: the magnet is a distance test, and a coin must not answer the interact scan")
	assert_eq(_pickup.visible_to_peer, Pickup.VISIBLE_TO_ALL,
		"a pickup defaults to every peer seeing it")
	assert_eq(_pickup.amount, Pickup.DEFAULT_AMOUNT, "the scene carries one unit by default")
	assert_true(_pickup.get_node_or_null(NodePath(Pickup.SYNC_NODE_NAME)) is MultiplayerSynchronizer,
		"the scene carries the synchronizer the per-peer visibility is set on")


func test_the_pickup_is_not_an_interactable() -> void:
	# SPEC-player-controller's interact scan duck-types on `prompt_text` and
	# `interact(player)`; a coin is walked over, never prompted at.
	assert_false(_pickup.has_method("interact"), "a pickup is not an interactable")
	assert_false(_has_property(_pickup, "prompt_text"), "a pickup shows no interact prompt")
	assert_false(_has_property(_pickup, "hold_seconds"))


func _has_property(node: Object, property_name: String) -> bool:
	for entry: Dictionary in node.get_property_list():
		if String(entry.get("name", "")) == property_name:
			return true
	return false


func test_the_six_pickup_kinds_are_the_specs_list() -> void:
	assert_eq(Pickup.KINDS,
		[&"gold", &"ore", &"echo", &"rune", &"relic", &"potion"] as Array[StringName],
		"SPEC-run-economy: gold coin, ore chunk, echo shard, rune stone, relic, potion")
	assert_true(Pickup.KINDS.has(Pickup.KIND_GOLD))
	assert_true(Pickup.KINDS.has(Pickup.KIND_POTION), "the last kind in the spec's list is declared too")


func test_the_pickup_records_its_sync_contract() -> void:
	var source: String = _read(PICKUP_SCRIPT_PATH)
	assert_true(source.contains("Sync:"), "every stateful script states who owns it and how it syncs")
	assert_true(source.contains("Events.pickup_collected"), "the collect path emits the bus signal")
	assert_false(source.contains("Engine.time_scale"), "time is read through TimeManager, never the engine")


# --- the magnet -------------------------------------------------------------


func test_a_pickup_inside_the_radius_accelerates_toward_the_player() -> void:
	make_player(NEAR_PEER, Vector2(TEST_RADIUS - 4.0, 0.0))
	assert_not_null(_pickup.nearest_player_in_range(), "the player is inside the pickup's radius")
	_pickup.magnet_step(0.1)
	assert_gt(_pickup.position.x, 0.0, "the pickup drifted toward the player")
	assert_true(is_equal_approx(_pickup.position.y, 0.0), "and straight at them, not off-axis")


func test_a_pickup_outside_the_radius_stays_put() -> void:
	make_player(NEAR_PEER, Vector2(TEST_RADIUS + 40.0, 0.0))
	assert_null(_pickup.nearest_player_in_range(), "the player is outside the pickup's radius")
	_pickup.magnet_step(0.1)
	assert_eq(_pickup.position, Vector2.ZERO, "an out-of-range pickup does not creep")


func test_the_magnet_accelerates_toward_the_nearest_player() -> void:
	make_player(NEAR_PEER, Vector2(20.0, 0.0))
	make_player(FAR_PEER, Vector2(0.0, 60.0))
	_pickup.magnet_step(0.1)
	assert_gt(_pickup.position.x, 0.0, "the pickup moved toward the nearer player")
	assert_true(is_equal_approx(_pickup.position.y, 0.0), "and not toward the farther one")


func test_the_magnet_runs_on_the_physics_tick_and_publishes_the_pose() -> void:
	make_player(NEAR_PEER, Vector2(TEST_RADIUS - 4.0, 0.0))
	_pickup.set_physics_process(true)
	await wait_physics_frames(2)
	assert_gt(_pickup.position.x, 0.0, "the pickup drifts toward the player on its own ticks")
	assert_eq(_pickup.synced_position, _pickup.position,
		"the host publishes the pose StateSync replicates")


func test_the_magnet_reads_time_through_time_manager() -> void:
	make_player(NEAR_PEER, Vector2(TEST_RADIUS - 4.0, 0.0))
	TimeManager.stop_enemies(10.0, TIME_SOURCE)
	assert_eq(TimeManager.scale_for(_pickup), TimeManager.DEFAULT_SCALE,
		"a pickup is not an enemy, so an enemy time stop does not stall it")
	_pickup.magnet_step(0.1)
	assert_gt(_pickup.position.x, 0.0, "the magnet still pulls while the enemies are frozen")


func test_a_client_never_magnetizes_a_pickup() -> void:
	make_player(NEAR_PEER, Vector2(TEST_RADIUS - 4.0, 0.0))
	NetworkManager.is_host = false
	assert_not_null(_pickup.nearest_player_in_range(), "the target is there to be found")
	_pickup.magnet_step(0.1)
	assert_eq(_pickup.position, Vector2.ZERO, "gameplay is host-only: a client moves nothing")


func test_a_downed_player_does_not_vacuum_loot() -> void:
	var player: Player = make_player(NEAR_PEER, Vector2(20.0, 0.0))
	player.is_downed = true
	assert_null(_pickup.nearest_player_in_range(), "a downed player cannot pick anything up")
	_pickup.magnet_step(0.1)
	assert_eq(_pickup.position, Vector2.ZERO)


# --- collecting -------------------------------------------------------------


func test_reaching_the_player_emits_pickup_collected_and_frees_the_node() -> void:
	var player: Player = make_player(NEAR_PEER, Vector2(20.0, 0.0))
	_pickup.position = player.global_position + Vector2(Pickup.COLLECT_DISTANCE - 1.0, 0.0)
	_pickup.magnet_step(0.1)
	assert_eq(_collected.size(), 1, "reaching the player emits pickup_collected exactly once")
	assert_same(_collected[0]["player"], player, "the collecting player is the one it reached")
	assert_same(_collected[0]["pickup"], _pickup, "and the pickup is the one collected")
	assert_true(_pickup.is_queued_for_deletion(), "the collected pickup frees itself")


func test_a_collected_pickup_never_collects_twice() -> void:
	var player: Player = make_player(NEAR_PEER, Vector2(20.0, 0.0))
	_pickup.position = player.global_position + Vector2(Pickup.COLLECT_DISTANCE - 1.0, 0.0)
	_pickup.magnet_step(0.1)
	_pickup.magnet_step(0.1)
	assert_eq(_collected.size(), 1, "a collected pickup is spent")
	assert_true(_pickup.collected)


func test_collect_is_refused_once_already_collected() -> void:
	var player: Player = make_player(NEAR_PEER, Vector2(20.0, 0.0))
	assert_true(_pickup.collect(player), "the first collect is applied")
	assert_false(_pickup.collect(player), "the second is refused")
	assert_eq(_collected.size(), 1)


# --- Ore Magnet widens the radius through the effect host -------------------


func test_ore_magnet_widens_the_radius_through_the_effect_host_id_read() -> void:
	var player: Player = make_player(NEAR_PEER, Vector2(0.0, TEST_RADIUS + 100.0))
	assert_eq(_pickup.magnet_radius(player), TEST_RADIUS, "without the relic the scene's radius stands")
	attach_relic(player, Pickup.ROOM_WIDE_RELIC_ID)
	assert_eq(_pickup.magnet_radius(player), Pickup.ROOM_WIDE_RADIUS,
		"Ore Magnet makes it room-wide (SPEC-run-economy)")
	assert_not_null(_pickup.nearest_player_in_range(), "and the far player is now in range")
	_pickup.magnet_step(0.1)
	assert_gt(_pickup.position.y, 0.0, "so the pickup crosses the room toward them")


func test_the_room_wide_read_is_an_effect_host_id_not_a_player_flag() -> void:
	var player: Player = make_player(NEAR_PEER, Vector2(0.0, TEST_RADIUS + 100.0))
	# A different relic on the same host must not widen anything: the read is
	# the relic's id, not "the holder has some effect".
	attach_relic(player, &"some_other_relic")
	assert_eq(_pickup.magnet_radius(player), TEST_RADIUS)
	assert_null(_pickup.nearest_player_in_range(), "and the far player stays out of range")


func test_a_player_with_no_effect_host_keeps_the_scene_radius() -> void:
	var player: Player = make_player(NEAR_PEER, Vector2(0.0, TEST_RADIUS + 100.0))
	assert_null(player.get_node_or_null(NodePath(EffectHost.NODE_NAME)), "this player carries no host")
	assert_eq(_pickup.magnet_radius(player), TEST_RADIUS)
	assert_eq(_pickup.magnet_radius(null), TEST_RADIUS, "and neither does a missing player widen it")


# --- per-player drops: visible_to_peer --------------------------------------


func test_a_shared_pickup_is_visible_to_every_peer() -> void:
	var pickup: Pickup = detached_pickup()
	var sync: MultiplayerSynchronizer = pickup.state_sync()
	assert_not_null(sync)
	if sync == null:
		return
	pickup.visible_to_peer = Pickup.VISIBLE_TO_ALL
	pickup.apply_visibility()
	assert_true(sync.public_visibility, "a shared pickup is public")
	assert_true(pickup.is_visible_to(NEAR_PEER))
	assert_true(pickup.is_visible_to(FAR_PEER))


func test_a_per_player_pickup_is_visible_to_its_own_peer_only() -> void:
	var pickup: Pickup = detached_pickup()
	var sync: MultiplayerSynchronizer = pickup.state_sync()
	assert_not_null(sync)
	if sync == null:
		return
	pickup.visible_to_peer = NEAR_PEER
	pickup.apply_visibility()
	assert_false(sync.public_visibility, "a per-player drop is not public")
	assert_true(sync.get_visibility_for(NEAR_PEER), "the synchronizer sends it to its peer")
	assert_false(sync.get_visibility_for(FAR_PEER), "and not to anyone else")
	assert_true(pickup.is_visible_to(NEAR_PEER))
	assert_false(pickup.is_visible_to(FAR_PEER))


func test_switching_a_pickup_back_to_shared_clears_the_override() -> void:
	var pickup: Pickup = detached_pickup()
	var sync: MultiplayerSynchronizer = pickup.state_sync()
	assert_not_null(sync)
	if sync == null:
		return
	pickup.visible_to_peer = NEAR_PEER
	pickup.apply_visibility()
	pickup.visible_to_peer = Pickup.VISIBLE_TO_ALL
	pickup.apply_visibility()
	assert_true(sync.public_visibility)
	assert_false(sync.get_visibility_for(NEAR_PEER), "the old per-peer override is cleared")
	assert_true(pickup.is_visible_to(FAR_PEER))


func test_the_scene_ready_applies_the_visibility_it_was_spawned_with() -> void:
	# The spawner knows the peer before the node enters the tree, so `_ready` is
	# where the per-player case is applied in the game. The in-tree copy here is
	# a shared drop (no per-peer call, which needs a connected peer), and the
	# point of the case is that ready leaves it public rather than flipping it.
	var sync: MultiplayerSynchronizer = _pickup.state_sync()
	assert_not_null(sync)
	if sync == null:
		return
	assert_true(sync.public_visibility, "a shared pickup is public straight out of _ready")
	assert_true(_pickup.is_visible_to(NEAR_PEER))


func test_the_scene_defaults_a_pickup_to_every_peer() -> void:
	assert_eq(Pickup.VISIBLE_TO_ALL, 0, "0 is the 'every peer' sentinel a shared currency drop uses")
	assert_eq(_pickup.visible_to_peer, Pickup.VISIBLE_TO_ALL)


# --- the Events retype this goal closes -------------------------------------


func test_the_bus_carries_the_real_pickup_class_and_the_todo_is_gone() -> void:
	var source: String = _read(EVENTS_SCRIPT_PATH)
	assert_false(source.contains("TODO(run-economy): Pickup"),
		"the placeholder TODO line is gone once the real class exists")
	assert_true(source.contains("pickup: Pickup"), "pickup_collected carries the Pickup class")
	var events: Node = get_tree().root.get_node_or_null("Events")
	assert_not_null(events, "the Events autoload is registered")
	if events == null:
		return
	var declared: String = ""
	for entry: Dictionary in events.get_script().get_script_signal_list():
		if String(entry["name"]) != "pickup_collected":
			continue
		var args: Array = entry["args"]
		assert_eq(args.size(), 2, "pickup_collected takes a player and a pickup")
		declared = String(args[1]["class_name"])
	assert_eq(declared, "Pickup", "the second parameter is declared as the real Pickup class")
