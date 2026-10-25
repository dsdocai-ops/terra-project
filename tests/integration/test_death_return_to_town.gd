extends GutTest
## Integration: die in a solo run, take Return to Town from the death screen, land
## in Hollowmere, then start the next dive from the Tavern's run setup.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _main: Main


func before_each() -> void:
	GameState.run = null
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	add_child_autofree(_main)


func after_each() -> void:
	NetworkManager.disconnect_all()
	GameState.run = null
	GameState.world = null
	GameState.forced_seed = 0


func _local_player() -> Player:
	return NetworkManager.players.get(NetworkManager.local_peer_id)


func test_dying_then_returning_lands_in_town_and_the_tavern_starts_a_new_dive() -> void:
	_main._on_solo()
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = _local_player()
	assert_not_null(player, "the solo player spawned")
	assert_not_null(GameState.run, "a run is live")
	assert_null(_main.town, "no town during a dive")
	player._die()
	assert_null(GameState.run, "the last player dying ends the run")
	var hud: Hud = _main.get_node("HUD") as Hud
	assert_true(hud.death_screen.visible, "the death screen shows")
	hud.death_screen._on_chosen(0)
	assert_false(hud.death_screen.visible, "choosing Return to Town hides it")
	assert_not_null(_main.town, "Hollowmere is up")
	assert_null(GameState.run, "and no run is live in town")
	assert_null(_main.world.floor_node, "the pit floor is gone")
	assert_false(player.is_dead, "the player stands again")
	assert_gt((player.health as Health).current_hp, 0, "with health")
	assert_lt(player.position.distance_to(Main.TOWN_SPAWN), 100.0, "at the town spawn")
	# The Tavern's Dive: pick a selection, ready up, start.
	var setup: RunSetup = _main.town.run_setup
	setup.submit(SelectionState.new(NetworkManager.local_peer_id), _main.town.profile)
	setup.set_ready(NetworkManager.local_peer_id, true)
	var reason: StringName = setup.start([NetworkManager.local_peer_id])
	assert_eq(reason, RunSetup.REFUSAL_NONE, "the run starts")
	await get_tree().process_frame
	assert_not_null(GameState.run, "a new run is live")
	assert_null(_main.town, "the town stepped aside")
	assert_not_null(_main.world.floor_node, "and a fresh floor is painted")
