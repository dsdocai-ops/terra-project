extends GutTest
## Integration: the ability controller is wired into the player the way the live
## game runs it (SPEC-abilities "AbilityController", W5-G2b). The player scene
## carries an AbilityController child, and a host cast from that controller
## spawns under the World's FX layer, the same parent the ground cracks use.
## Single-instance: the offline peer is the host, so request_cast runs locally,
## as it does on the host. Owned by abilities.

const WORLD_SCENE := "res://scenes/main/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _world: World
var _player: Player


func before_each() -> void:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world
	NetworkManager.start_solo()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_world.entities.add_child(_player)


func after_each() -> void:
	NetworkManager.disconnect_all()
	GameState.world = null


func test_the_player_scene_carries_an_ability_controller() -> void:
	var controller := _player.get_node_or_null("AbilityController") as AbilityController
	assert_not_null(controller, "player.tscn has an AbilityController child")


func test_a_cast_from_the_player_spawns_under_the_worlds_fx_layer() -> void:
	var controller := _player.get_node("AbilityController") as AbilityController
	controller.assign(0, FixtureAbility.make())
	assert_true(controller.request_cast(0, _player.global_position + Vector2(64, 0)), "the cast is accepted")
	var cast := controller.last_cast
	assert_not_null(cast, "the cast node exists")
	if cast == null:
		return
	assert_same(cast.get_parent(), _world.fx, "the cast spawns under the world's FX layer")
