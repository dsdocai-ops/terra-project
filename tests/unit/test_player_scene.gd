extends GutTest
## Tests for scenes/player/player.tscn skeleton. Owned by player-controller.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _player: Player


func before_each() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	assert_not_null(packed, "player scene loads")
	if packed == null:
		return
	_player = packed.instantiate() as Player
	add_child_autofree(_player)


func test_root_is_character_body() -> void:
	assert_true(_player is CharacterBody2D)


func test_node_layout_matches_spec() -> void:
	for name in ["StatBlock", "Health", "Hurtbox", "StatusEffects", "StateMachine", "Sprite", "WeaponPivot", "InputSync", "StateSync", "InteractArea"]:
		assert_not_null(_player.get_node_or_null(name), name)


func test_synchronizers_are_multiplayer_synchronizers() -> void:
	assert_true(_player.get_node("InputSync") is MultiplayerSynchronizer)
	assert_true(_player.get_node("StateSync") is MultiplayerSynchronizer)


func test_public_fields_exist() -> void:
	for field in ["peer_id", "character", "class_data", "stat_block", "health", "hurtbox", "state_machine", "facing", "facing_index", "aim_position", "is_downed", "is_local", "dodge_charges", "dodge_distance_mult", "revive_speed_mult"]:
		assert_true(field in _player, field)


func test_public_signals_exist() -> void:
	for sig in ["downed", "revived", "dodge_started", "dodge_finished", "facing_changed"]:
		assert_true(_player.has_signal(sig), sig)


func test_public_methods_exist() -> void:
	for method in ["is_perfect_dodge_window", "consume_perfect_dodge_window", "reset_dodge_cooldown", "play_directional", "request_revive"]:
		assert_true(_player.has_method(method), method)


func test_defaults() -> void:
	assert_eq(_player.dodge_charges, 1)
	assert_eq(_player.dodge_distance_mult, 1.0)
	assert_eq(_player.revive_speed_mult, 1.0)
	assert_false(_player.is_downed)
	assert_eq(_player.facing, Vector2.DOWN, "faces the camera by default")
	assert_eq(_player.facing_index, 0, "index 0 is south")


func test_is_local_follows_peer_id() -> void:
	_player.peer_id = multiplayer.get_unique_id()
	assert_true(_player.is_local, "matches this peer")
	_player.peer_id = multiplayer.get_unique_id() + 41
	assert_false(_player.is_local, "someone else's player")


func test_sprite_has_idle_and_walk_for_all_eight_directions() -> void:
	var sprite := _player.get_node("Sprite") as AnimatedSprite2D
	assert_not_null(sprite.sprite_frames, "sprite frames assigned")
	for dir in Player.FACING_SUFFIXES:
		assert_true(sprite.sprite_frames.has_animation("idle_%s" % dir), "idle_%s" % dir)
		assert_true(sprite.sprite_frames.has_animation("walk_%s" % dir), "walk_%s" % dir)


func test_play_directional_uses_facing_suffix() -> void:
	var sprite := _player.get_node("Sprite") as AnimatedSprite2D
	_player.facing_index = 6
	_player.play_directional("idle")
	assert_eq(sprite.animation, &"idle_e")
	_player.facing_index = 3
	_player.play_directional("walk")
	assert_eq(sprite.animation, &"walk_nw")


func test_component_slots_are_wired() -> void:
	assert_eq(_player.stat_block, _player.get_node("StatBlock"))
	assert_eq(_player.health, _player.get_node("Health"))
	assert_eq(_player.hurtbox, _player.get_node("Hurtbox"))
	assert_eq(_player.state_machine, _player.get_node("StateMachine"))
