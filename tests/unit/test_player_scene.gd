extends GutTest
## Tests for scenes/player/player.tscn skeleton. Owned by player-controller.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

const SPEC_NODES: Array[String] = [
	"StatBlock", "Health", "Hurtbox", "StatusEffects", "StateMachine",
	"Sprite", "WeaponPivot", "InputSync", "StateSync", "InteractArea",
]
const SPEC_FIELDS: Array[String] = [
	"peer_id", "character", "class_data", "stat_block", "health", "hurtbox",
	"state_machine", "facing", "facing_index", "aim_position", "is_downed",
	"is_local", "dodge_charges", "dodge_distance_mult", "revive_speed_mult",
]
const SPEC_SIGNALS: Array[String] = ["downed", "revived", "dodge_started", "dodge_finished", "facing_changed"]
const SPEC_METHODS: Array[String] = [
	"is_perfect_dodge_window", "consume_perfect_dodge_window", "reset_dodge_cooldown",
	"play_directional", "request_revive",
]
## Fields whose final type is already known. Resource and Node placeholders
## (character, class_data, stat_block, health) are retyped by later modules.
const SPEC_FIELD_TYPES: Dictionary[String, int] = {
	"peer_id": TYPE_INT, "facing": TYPE_VECTOR2, "facing_index": TYPE_INT,
	"aim_position": TYPE_VECTOR2, "is_downed": TYPE_BOOL, "is_local": TYPE_BOOL,
	"dodge_charges": TYPE_INT, "dodge_distance_mult": TYPE_FLOAT, "revive_speed_mult": TYPE_FLOAT,
}

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


func test_body_collides_with_world_but_not_other_players() -> void:
	# Layer 1 = world (walls), layer 2 = players. Players never block each
	# other; they only collide with walls.
	assert_eq(_player.collision_layer, 2, "on the player layer")
	assert_eq(_player.collision_mask, 1, "collides with the world layer only")
	assert_false(_player.get_collision_mask_value(2), "does not collide with other players")


func test_node_layout_matches_spec() -> void:
	for node_name: String in SPEC_NODES:
		assert_not_null(_player.get_node_or_null(node_name), node_name)


# Co-op slot colors

func test_every_slot_has_its_own_color() -> void:
	assert_eq(Player.SLOT_COLORS.size(), NetworkManager.MAX_PLAYERS, "one color per co-op slot")
	for a in Player.SLOT_COLORS.size():
		for b in range(a + 1, Player.SLOT_COLORS.size()):
			var diff := Vector3(Player.SLOT_COLORS[a].r - Player.SLOT_COLORS[b].r,
				Player.SLOT_COLORS[a].g - Player.SLOT_COLORS[b].g, Player.SLOT_COLORS[a].b - Player.SLOT_COLORS[b].b)
			assert_gt(diff.length(), 0.4, "slots %d and %d are easy to tell apart" % [a, b])


func test_slot_ring_shows_the_slot_color() -> void:
	assert_eq(_player.slot_ring.color, Player.slot_color(0), "P1 color by default")
	_player.slot = 2
	assert_eq(_player.slot_ring.color, Player.SLOT_COLORS[2])


func test_slot_set_before_entering_the_tree_still_colors_the_ring() -> void:
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	p.slot = 3
	add_child_autofree(p)
	assert_eq(p.slot_ring.color, Player.SLOT_COLORS[3])


func test_slot_color_wraps_out_of_range_slots() -> void:
	assert_eq(Player.slot_color(Player.SLOT_COLORS.size() + 1), Player.SLOT_COLORS[1])
	assert_eq(Player.slot_color(-1), Player.SLOT_COLORS[Player.SLOT_COLORS.size() - 1])


func test_slot_ring_draws_under_the_sprite() -> void:
	assert_lt(_player.slot_ring.get_index(), _player.sprite.get_index(), "ring at the feet, sprite on top")


func test_synchronizers_are_multiplayer_synchronizers() -> void:
	assert_true(_player.get_node("InputSync") is MultiplayerSynchronizer)
	assert_true(_player.get_node("StateSync") is MultiplayerSynchronizer)


func test_public_fields_exist() -> void:
	for field: String in SPEC_FIELDS:
		assert_true(field in _player, field)


func test_public_fields_have_their_final_types() -> void:
	for field: String in SPEC_FIELD_TYPES:
		assert_eq(typeof(_player.get(field)), SPEC_FIELD_TYPES[field], field)


func test_public_signals_exist() -> void:
	for sig: String in SPEC_SIGNALS:
		assert_true(_player.has_signal(sig), sig)


func test_public_methods_exist() -> void:
	for method: String in SPEC_METHODS:
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
	for dir: StringName in Facing.SUFFIXES:
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


func test_facing_change_replays_current_animation_for_new_direction() -> void:
	var sprite := _player.get_node("Sprite") as AnimatedSprite2D
	_player.play_directional("walk")
	_player.facing_index = 4
	assert_eq(sprite.animation, &"walk_n", "same animation, new suffix, no extra play call needed")


func test_missing_animation_warns_once_and_keeps_playing() -> void:
	var sprite := _player.get_node("Sprite") as AnimatedSprite2D
	_player.play_directional("idle")
	_player.play_directional("nope")
	_player.play_directional("nope")
	assert_eq(sprite.animation, &"idle_s", "unknown animation does not change the sprite")


func test_component_slots_are_wired() -> void:
	assert_eq(_player.stat_block, _player.get_node("StatBlock"))
	assert_eq(_player.health, _player.get_node("Health"))
	assert_eq(_player.hurtbox, _player.get_node("Hurtbox"))
	assert_eq(_player.state_machine, _player.get_node("StateMachine"))
