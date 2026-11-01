extends GutTest
## A real player carries an EffectHost, so a shrine pick can attach a relic. It
## once did not: every pick was refused and the offer popup reopened forever.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

var _was_host: bool = false


func before_each() -> void:
	_was_host = NetworkManager.is_host


func after_each() -> void:
	NetworkManager.is_host = _was_host


func test_a_hosted_player_gets_an_effect_host() -> void:
	NetworkManager.is_host = true
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	assert_not_null(RelicFlow.effect_host_of(player), "the pick flow can find it")


func test_a_client_copy_carries_none() -> void:
	NetworkManager.is_host = false
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	assert_null(RelicFlow.effect_host_of(player), "the host owns effects")
