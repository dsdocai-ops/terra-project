extends GutTest
## Integration: die in a solo run, take Return to Town from the death screen, and
## come out with a live run, a living player and the death screen gone.

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


func test_returning_to_town_after_dying_starts_fresh() -> void:
	_main._on_solo()
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = _local_player()
	assert_not_null(player, "the solo player spawned")
	assert_not_null(GameState.run, "a run is live")
	var first_run: RunState = GameState.run
	player._die()
	assert_null(GameState.run, "the last player dying ends the run")
	var hud: Hud = _main.get_node("HUD") as Hud
	assert_true(hud.death_screen.visible, "the death screen shows")
	hud.death_screen._on_chosen(0)
	assert_false(hud.death_screen.visible, "choosing Return to Town hides it")
	assert_not_null(GameState.run, "a new run is live")
	assert_ne(GameState.run, first_run, "and it is a new one")
	assert_false(player.is_dead, "the player stands again")
	assert_gt((player.health as Health).current_hp, 0, "with health")
	await get_tree().process_frame
	var start: Vector2 = _main.world.floor_node.start_position()
	assert_lt(player.global_position.distance_to(start), 200.0, "and is back at the start room")
	assert_true(_main.world.floor_node.visited.size() <= 1, "with a fresh fog: only the start room entered")
